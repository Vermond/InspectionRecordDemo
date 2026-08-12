import ComposableArchitecture
import CoreLocation
import Foundation

enum LocationAuthorizationStatus: Equatable, Sendable {
    case authorized
    case notDetermined
    case denied
}

struct LocationSample: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let capturedAt: Date
}

struct LocationClient: Sendable {
    var authorizationStatus: @MainActor @Sendable () -> LocationAuthorizationStatus
    var requestWhenInUseAuthorization: @MainActor @Sendable () async -> LocationAuthorizationStatus
    var requestCurrentLocation: @MainActor @Sendable () async -> LocationSample?
}

@MainActor
private final class LiveLocationManager: NSObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = LiveLocationManager()

    private static let locationCacheMaxAge: TimeInterval = 5 * 60
    private static let locationCacheMaxAccuracy: CLLocationAccuracy = 50
    private static let locationRequestTimeout: Duration = .seconds(5)

    private let manager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<LocationAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<LocationSample?, Never>?
    private var locationRequestTimeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func authorizationStatus() -> LocationAuthorizationStatus {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            .authorized
        case .notDetermined:
            .notDetermined
        case .denied, .restricted:
            .denied
        @unknown default:
            .denied
        }
    }

    private nonisolated static func locationServicesEnabledOffMain() async -> Bool {
        await Task.detached(priority: .utility) {
            CLLocationManager.locationServicesEnabled()
        }.value
    }

    func requestWhenInUseAuthorization() async -> LocationAuthorizationStatus {
        let currentStatus = authorizationStatus()
        guard currentStatus == .notDetermined else {
            return currentStatus
        }

        return await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func requestCurrentLocation() async -> LocationSample? {
        guard authorizationStatus() == .authorized,
              locationContinuation == nil
        else {
            return nil
        }

        if let cachedLocation = validCachedLocation() {
            return cachedLocation
        }

        guard await Self.locationServicesEnabledOffMain(),
              authorizationStatus() == .authorized,
              locationContinuation == nil
        else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            locationRequestTimeoutTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: Self.locationRequestTimeout)
                    guard !Task.isCancelled else {
                        return
                    }

                    self?.finishLocationRequest(with: nil)
                } catch {
                    return
                }
            }
            manager.requestLocation()
        }
    }

    private func validCachedLocation() -> LocationSample? {
        guard let location = manager.location,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= Self.locationCacheMaxAccuracy,
              location.coordinate.latitude.isFinite,
              location.coordinate.longitude.isFinite
        else {
            return nil
        }

        let age = Date().timeIntervalSince(location.timestamp)
        guard age >= 0, age <= Self.locationCacheMaxAge else {
            return nil
        }

        return LocationSample(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            capturedAt: location.timestamp
        )
    }

    private func finishLocationRequest(with sample: LocationSample?) {
        guard let continuation = locationContinuation else {
            return
        }

        locationContinuation = nil
        manager.stopUpdatingLocation()
        locationRequestTimeoutTask?.cancel()
        locationRequestTimeoutTask = nil
        continuation.resume(returning: sample)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = authorizationStatus()

        if let continuation = authorizationContinuation {
            authorizationContinuation = nil
            continuation.resume(returning: status)
        }

        guard status != .authorized, locationContinuation != nil else {
            return
        }

        finishLocationRequest(with: nil)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard locationContinuation != nil else {
            return
        }

        guard let location = locations.last,
              location.horizontalAccuracy >= 0,
              location.coordinate.latitude.isFinite,
              location.coordinate.longitude.isFinite
        else {
            finishLocationRequest(with: nil)
            return
        }

        finishLocationRequest(
            with: LocationSample(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                capturedAt: location.timestamp
            )
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finishLocationRequest(with: nil)
    }
}

extension LocationClient: DependencyKey {
    static let liveValue = Self(
        authorizationStatus: {
            LiveLocationManager.shared.authorizationStatus()
        },
        requestWhenInUseAuthorization: {
            await LiveLocationManager.shared.requestWhenInUseAuthorization()
        },
        requestCurrentLocation: {
            await LiveLocationManager.shared.requestCurrentLocation()
        }
    )

    static let testValue = Self(
        authorizationStatus: { .authorized },
        requestWhenInUseAuthorization: { .authorized },
        requestCurrentLocation: { nil }
    )
}

extension DependencyValues {
    var locationClient: LocationClient {
        get { self[LocationClient.self] }
        set { self[LocationClient.self] = newValue }
    }
}
