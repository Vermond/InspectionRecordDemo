import ComposableArchitecture
import Foundation

@Reducer
struct InspectionEditorFeature {
    @Dependency(\.cameraClient) private var cameraClient
    @Dependency(\.locationClient) private var locationClient

    private enum LocationRequestID: Hashable {
        case current
    }

    enum LocationRequestSource: Equatable, Sendable {
        case preparation
        case refresh
    }

    enum Mode: Equatable, Sendable {
        case create
        case view
        case editing

        var isEditable: Bool {
            self == .create || self == .editing
        }

        var navigationTitle: String {
            switch self {
            case .create:
                "점검 작성"
            case .view, .editing:
                "점검 기록"
            }
        }
    }

    @ObservableState
    struct State: Equatable {
        enum LocationPrompt: Equatable, Sendable {
            case introduction(LocationRequestSource)
            case permissionDenied
        }

        enum CameraError: Equatable, Sendable {
            case permissionDenied
            case unavailable

            var title: String {
                switch self {
                case .permissionDenied:
                    "카메라 권한 필요"
                case .unavailable:
                    "카메라 사용 불가"
                }
            }

            var message: String {
                switch self {
                case .permissionDenied:
                    "점검 사진을 촬영하려면 카메라 접근 권한이 필요합니다. 설정에서 권한을 허용해주세요."
                case .unavailable:
                    "이 기기에서는 카메라를 사용할 수 없습니다."
                }
            }

            var canOpenSettings: Bool {
                self == .permissionDenied
            }
        }

        struct Snapshot: Equatable {
            let photoData: Data?
            let status: InspectionStatus?
            let memo: String
            let latitude: Double?
            let longitude: Double?
            let locationCapturedAt: Date?

            init(
                photoData: Data?,
                status: InspectionStatus?,
                memo: String,
                latitude: Double? = nil,
                longitude: Double? = nil,
                locationCapturedAt: Date? = nil
            ) {
                self.photoData = photoData
                self.status = status
                self.memo = memo
                self.latitude = latitude
                self.longitude = longitude
                self.locationCapturedAt = locationCapturedAt
            }
        }

        private static let locationFreshnessInterval: TimeInterval = 5 * 60

        let target: InspectionTarget
        let recordID: UUID?
        let createdAt: Date
        var mode: Mode
        var photoData: Data?
        var status: InspectionStatus?
        var memo: String
        var latitude: Double?
        var longitude: Double?
        var locationCapturedAt: Date?
        var isLocationLoading = false
        var locationPrompt: LocationPrompt?
        var isSaving = false
        var originalSnapshot: Snapshot?
        var photoErrorMessage: String?
        var isCameraPresented = false
        var cameraError: CameraError?

        init(target: InspectionTarget) {
            self.target = target
            self.recordID = nil
            self.createdAt = Date()
            self.mode = .create
            self.photoData = nil
            self.status = nil
            self.memo = ""
            self.latitude = nil
            self.longitude = nil
            self.locationCapturedAt = nil
            self.originalSnapshot = nil
            self.photoErrorMessage = nil
            self.isCameraPresented = false
            self.cameraError = nil
        }

        init(record: InspectionRecord) {
            self.target = InspectionTarget(
                id: record.targetID,
                name: record.targetNameSnapshot,
                equipmentNumber: record.equipmentNumberSnapshot
            )
            self.recordID = record.id
            self.createdAt = record.createdAt
            self.mode = .view
            self.photoData = record.photoData
            self.status = record.status
            self.memo = record.memo
            self.latitude = record.latitude
            self.longitude = record.longitude
            self.locationCapturedAt = nil
            self.originalSnapshot = nil
            self.photoErrorMessage = nil
            self.isCameraPresented = false
            self.cameraError = nil
        }

        var snapshot: Snapshot {
            Snapshot(
                photoData: photoData,
                status: status,
                memo: memo,
                latitude: latitude,
                longitude: longitude,
                locationCapturedAt: locationCapturedAt
            )
        }

        var hasFreshLocation: Bool {
            guard latitude != nil,
                  longitude != nil,
                  let locationCapturedAt
            else {
                return false
            }

            let age = Date().timeIntervalSince(locationCapturedAt)
            return age >= 0 && age <= Self.locationFreshnessInterval
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case editButtonTapped
        case closeButtonTapped
        case saveButtonTapped
        case cancelButtonTapped
        case locationPreparationRequested
        case locationAuthorizationChecked(LocationAuthorizationStatus, LocationRequestSource)
        case locationIntroductionConfirmed
        case locationIntroductionDismissed
        case locationRefreshButtonTapped
        case locationUpdated(LocationSample)
        case locationUnavailable
        case locationPermissionDeniedDismissed
        case locationSaveCompleted(LocationSample?)
        case cameraButtonTapped
        case cameraPresentationRequested
        case cameraPermissionDenied
        case cameraUnavailable
        case cameraImageCaptured(Data)
        case cameraDismissed
        case cameraErrorDismissed
        case deletePhotoButtonTapped
        case photoDataLoaded(Data)
        case photoLoadingFailed
        case delegate(Delegate)

        enum Delegate: Equatable {
            case saved(InspectionRecord)
            case cancelled
        }
    }

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { (state: inout State, action: Action) -> EffectOf<Self> in
            switch action {
            case .binding:
                return .none

            case .editButtonTapped:
                guard state.mode == .view else {
                    return .none
                }

                state.originalSnapshot = state.snapshot
                state.mode = .editing
                return .none

            case .closeButtonTapped:
                return .send(.delegate(.cancelled))

            case .saveButtonTapped:
                guard state.mode.isEditable, !state.isSaving else {
                    return .none
                }

                if state.mode == .create, !state.hasFreshLocation {
                    state.isSaving = true
                    return requestLocationForSaving()
                }

                let updatedAt = state.mode == .create ? state.createdAt : Date()
                let record = Self.makeRecord(
                    from: state,
                    updatedAt: updatedAt,
                    latitude: state.latitude,
                    longitude: state.longitude
                )
                return .send(.delegate(.saved(record)))

            case .locationPreparationRequested:
                return requestLocationAuthorization(
                    source: .preparation,
                    state: &state
                )

            case .locationRefreshButtonTapped:
                return requestLocationAuthorization(
                    source: .refresh,
                    state: &state
                )

            case let .locationAuthorizationChecked(status, source):
                guard state.mode == .create else {
                    return .none
                }

                switch status {
                case .authorized:
                    state.locationPrompt = nil
                    state.isLocationLoading = true
                    let locationClient = self.locationClient

                    return .run { send in
                        if let sample = await locationClient.requestCurrentLocation() {
                            await send(.locationUpdated(sample))
                        } else {
                            await send(.locationUnavailable)
                        }
                    }
                    .cancellable(id: LocationRequestID.current, cancelInFlight: true)

                case .notDetermined:
                    state.isLocationLoading = false
                    state.locationPrompt = .introduction(source)
                    return .none

                case .denied:
                    state.isLocationLoading = false
                    state.locationPrompt = source == .refresh ? .permissionDenied : nil
                    return .none
                }

            case .locationIntroductionConfirmed:
                guard state.mode == .create else {
                    return .none
                }

                guard case let .introduction(source) = state.locationPrompt else {
                    return .none
                }

                state.locationPrompt = nil
                state.isLocationLoading = true
                let locationClient = self.locationClient
                return .run { send in
                    await send(
                        .locationAuthorizationChecked(
                            await locationClient.requestWhenInUseAuthorization(),
                            source
                        )
                    )
                }
                .cancellable(id: LocationRequestID.current, cancelInFlight: true)

            case .locationIntroductionDismissed:
                state.locationPrompt = nil
                return .none

            case .locationPermissionDeniedDismissed:
                state.locationPrompt = nil
                return .none

            case let .locationUpdated(sample):
                guard state.mode == .create else {
                    return .none
                }

                state.latitude = sample.latitude
                state.longitude = sample.longitude
                state.locationCapturedAt = sample.capturedAt
                state.isLocationLoading = false
                return .none

            case .locationUnavailable:
                state.isLocationLoading = false
                return .none

            case let .locationSaveCompleted(sample):
                state.isSaving = false
                state.isLocationLoading = false

                if let sample {
                    state.latitude = sample.latitude
                    state.longitude = sample.longitude
                    state.locationCapturedAt = sample.capturedAt
                } else {
                    state.latitude = nil
                    state.longitude = nil
                    state.locationCapturedAt = nil
                }

                let record = Self.makeRecord(
                    from: state,
                    updatedAt: state.createdAt,
                    latitude: sample?.latitude,
                    longitude: sample?.longitude
                )
                return .send(.delegate(.saved(record)))

            case .cameraButtonTapped:
                guard state.mode.isEditable else {
                    return .none
                }

                state.cameraError = nil
                let cameraClient = self.cameraClient

                return .run { send in
                    guard await cameraClient.isAvailable() else {
                        await send(.cameraUnavailable)
                        return
                    }

                    switch await cameraClient.authorizationStatus() {
                    case .authorized:
                        await send(.cameraPresentationRequested)
                    case .notDetermined:
                        if await cameraClient.requestAccess() {
                            await send(.cameraPresentationRequested)
                        } else {
                            await send(.cameraPermissionDenied)
                        }
                    case .denied:
                        await send(.cameraPermissionDenied)
                    }
                }

            case .cameraPresentationRequested:
                state.isCameraPresented = true
                return .none

            case let .cameraImageCaptured(data):
                state.photoData = data
                state.photoErrorMessage = nil
                state.isCameraPresented = false
                state.cameraError = nil
                return .none

            case .cameraDismissed:
                state.isCameraPresented = false
                return .none

            case .cameraPermissionDenied:
                state.cameraError = .permissionDenied
                return .none

            case .cameraUnavailable:
                state.cameraError = .unavailable
                return .none

            case .cameraErrorDismissed:
                state.cameraError = nil
                return .none

            case .deletePhotoButtonTapped:
                guard state.mode.isEditable else {
                    return .none
                }

                state.photoData = nil
                state.photoErrorMessage = nil
                return .none

            case .cancelButtonTapped:
                switch state.mode {
                case .create:
                    state.isSaving = false
                    return .merge(
                        .cancel(id: LocationRequestID.current),
                        .send(.delegate(.cancelled))
                    )
                case .view:
                    return .none
                case .editing:
                    if let originalSnapshot = state.originalSnapshot {
                        state.photoData = originalSnapshot.photoData
                        state.status = originalSnapshot.status
                        state.memo = originalSnapshot.memo
                        state.latitude = originalSnapshot.latitude
                        state.longitude = originalSnapshot.longitude
                        state.locationCapturedAt = originalSnapshot.locationCapturedAt
                    }

                    state.originalSnapshot = nil
                    state.mode = .view
                    return .none
                }

            case let .photoDataLoaded(data):
                state.photoData = data
                state.photoErrorMessage = nil
                return .none

            case .photoLoadingFailed:
                state.photoErrorMessage = "사진을 불러오지 못했습니다."
                return .none

            case .delegate:
                return .none
            }
        }
    }

    private func requestLocationAuthorization(
        source: LocationRequestSource,
        state: inout State
    ) -> EffectOf<Self> {
        guard state.mode == .create,
              !state.isSaving,
              !state.isLocationLoading
        else {
            return .none
        }

        let locationClient = self.locationClient
        return .run { send in
            await send(
                .locationAuthorizationChecked(
                    await locationClient.authorizationStatus(),
                    source
                )
            )
        }
    }

    private func requestLocationForSaving() -> EffectOf<Self> {
        let locationClient = self.locationClient
        return .run { send in
            guard await locationClient.authorizationStatus() == .authorized else {
                await send(.locationSaveCompleted(nil))
                return
            }

            await send(
                .locationSaveCompleted(
                    await locationClient.requestCurrentLocation()
                )
            )
        }
        .cancellable(id: LocationRequestID.current, cancelInFlight: true)
    }

    private static func makeRecord(
        from state: State,
        updatedAt: Date,
        latitude: Double?,
        longitude: Double?
    ) -> InspectionRecord {
        InspectionRecord(
            id: state.recordID ?? UUID(),
            targetID: state.target.id,
            targetNameSnapshot: state.target.name,
            equipmentNumberSnapshot: state.target.equipmentNumber,
            createdAt: state.createdAt,
            updatedAt: updatedAt,
            photoData: state.photoData,
            status: state.status,
            memo: state.memo,
            syncStatus: .pending,
            latitude: latitude,
            longitude: longitude
        )
    }
}
