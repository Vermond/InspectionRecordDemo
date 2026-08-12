import AVFoundation
import ComposableArchitecture
import UIKit

enum CameraAuthorizationStatus: Equatable, Sendable {
    case authorized
    case notDetermined
    case denied
}

struct CameraClient: Sendable {
    var authorizationStatus: @MainActor @Sendable () -> CameraAuthorizationStatus
    var requestAccess: @MainActor @Sendable () async -> Bool
    var isAvailable: @MainActor @Sendable () -> Bool
}

extension CameraClient: DependencyKey {
    static let liveValue = Self(
        authorizationStatus: {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                .authorized
            case .notDetermined:
                .notDetermined
            case .denied, .restricted:
                .denied
            @unknown default:
                .denied
            }
        },
        requestAccess: {
            await AVCaptureDevice.requestAccess(for: .video)
        },
        isAvailable: {
            UIImagePickerController.isSourceTypeAvailable(.camera)
        }
    )

    static let testValue = Self(
        authorizationStatus: { .authorized },
        requestAccess: { true },
        isAvailable: { true }
    )
}

extension DependencyValues {
    var cameraClient: CameraClient {
        get { self[CameraClient.self] }
        set { self[CameraClient.self] = newValue }
    }
}
