import ComposableArchitecture
import Contacts
import CoreLocation
import Foundation

struct GeocodingClient: Sendable {
    var reverseGeocode: @MainActor @Sendable (_ latitude: Double, _ longitude: Double) async -> String?
}

@MainActor
private final class LiveGeocoder {
    static let shared = LiveGeocoder()

    private let geocoder = CLGeocoder()
    private let addressFormatter = CNPostalAddressFormatter()

    func reverseGeocode(latitude: Double, longitude: Double) async -> String? {
        guard latitude.isFinite,
              longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude)
        else {
            return nil
        }

        geocoder.cancelGeocode()

        let preferredLocale = Locale.preferredLanguages.first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { identifier in
                identifier.isEmpty ? nil : Locale(identifier: identifier)
            }
            ?? Locale.current

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(
                CLLocation(latitude: latitude, longitude: longitude),
                preferredLocale: preferredLocale
            )

            guard let placemark = placemarks.first else {
                return nil
            }

            if let postalAddress = placemark.postalAddress {
                let formattedAddress = addressFormatter
                    .string(from: postalAddress)
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !formattedAddress.isEmpty {
                    return formattedAddress
                }
            }

            let fallbackAddress = [
                placemark.administrativeArea,
                placemark.locality,
                placemark.subLocality,
                placemark.thoroughfare,
                placemark.subThoroughfare
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

            return fallbackAddress.isEmpty ? placemark.name : fallbackAddress
        } catch {
            return nil
        }
    }
}

extension GeocodingClient: DependencyKey {
    static let liveValue = Self(
        reverseGeocode: { latitude, longitude in
            await LiveGeocoder.shared.reverseGeocode(
                latitude: latitude,
                longitude: longitude
            )
        }
    )

    static let testValue = Self(
        reverseGeocode: { _, _ in nil }
    )
}

extension DependencyValues {
    var geocodingClient: GeocodingClient {
        get { self[GeocodingClient.self] }
        set { self[GeocodingClient.self] = newValue }
    }
}
