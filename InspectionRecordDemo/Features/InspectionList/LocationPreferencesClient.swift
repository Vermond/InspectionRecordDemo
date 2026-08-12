import ComposableArchitecture
import Foundation

struct LocationPreferencesClient: Sendable {
    var suppressLocationPermissionWarning: @Sendable () -> Bool
    var setSuppressLocationPermissionWarning: @Sendable (Bool) -> Void
}

extension LocationPreferencesClient: DependencyKey {
    private static let suppressWarningKey = "suppressLocationPermissionWarning"

    static let liveValue = Self(
        suppressLocationPermissionWarning: {
            UserDefaults.standard.bool(forKey: suppressWarningKey)
        },
        setSuppressLocationPermissionWarning: { value in
            UserDefaults.standard.set(value, forKey: suppressWarningKey)
        }
    )

    static let testValue = Self(
        suppressLocationPermissionWarning: { false },
        setSuppressLocationPermissionWarning: { _ in }
    )
}

extension DependencyValues {
    var locationPreferences: LocationPreferencesClient {
        get { self[LocationPreferencesClient.self] }
        set { self[LocationPreferencesClient.self] = newValue }
    }
}
