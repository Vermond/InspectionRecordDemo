import ComposableArchitecture
import AVFoundation
import CoreLocation
import Foundation
import PhotosUI
import SwiftUI
import UIKit

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

enum LocationRequestSource: Equatable, Sendable {
    case preparation
    case refresh
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

@Reducer
struct InspectionEditorFeature {
    @Dependency(\.cameraClient) private var cameraClient
    @Dependency(\.locationClient) private var locationClient

    private enum LocationRequestID: Hashable {
        case current
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

struct InspectionEditorView: View {
    @Bindable var store: StoreOf<InspectionEditorFeature>
    @Environment(\.openURL) private var openURL
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section("점검 대상") {
                    LabeledContent("대상", value: store.target.name)
                    LabeledContent("장비 번호", value: store.target.equipmentNumber)
                }

                Section("위치") {
                    if store.isLocationLoading {
                        Text("위치 확인 중...")
                            .foregroundStyle(.secondary)
                    } else if let latitude = store.latitude,
                              let longitude = store.longitude {
                        LabeledContent("위도", value: String(format: "%.6f", latitude))
                        LabeledContent("경도", value: String(format: "%.6f", longitude))
                    } else {
                        Text("위치 정보 없음")
                            .foregroundStyle(.secondary)
                    }

                    if store.mode == .create {
                        Button {
                            store.send(.locationRefreshButtonTapped)
                        } label: {
                            Label("현재 위치 다시 확인", systemImage: "location.fill")
                        }
                        .disabled(store.isLocationLoading)
                    }
                }
                
                Section("사진") {
                    if let photoData = store.photoData,
                       let image = UIImage(data: photoData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text("사진 없음")
                            .foregroundStyle(.secondary)
                    }
                    
                    photoActionButtons
                    
                    if let photoErrorMessage = store.photoErrorMessage {
                        Text(photoErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                
                Section("상태") {
                    if store.mode.isEditable {
                        Picker("상태", selection: $store.status) {
                            Text("선택 안 함")
                                .tag(Optional<InspectionStatus>.none)
                            
                            ForEach(InspectionStatus.allCases, id: \.self) { status in
                                Text(status.title)
                                    .tag(Optional<InspectionStatus>.some(status))
                            }
                        }
                    } else {
                        Text(store.status?.title ?? "상태 미지정")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("메모") {
                    if store.mode.isEditable {
                        TextEditor(text: $store.memo)
                            .frame(minHeight: 140)
                    } else if store.memo.isEmpty {
                        Text("메모 없음")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(store.memo)
                    }
                }
            }
            .navigationTitle(store.mode.navigationTitle)
            .task {
                await store.send(.locationPreparationRequested).finish()
            }
            .alert(
                store.locationPrompt == .permissionDenied ? "위치 권한 필요" : "위치 기록 안내",
                isPresented: Binding(
                    get: {
                        store.locationPrompt != nil
                    },
                    set: { isPresented in
                        guard !isPresented else {
                            return
                        }

                        if store.locationPrompt == .permissionDenied {
                            store.send(.locationPermissionDeniedDismissed)
                        } else {
                            store.send(.locationIntroductionDismissed)
                        }
                    }
                )
            ) {
                if store.locationPrompt == .permissionDenied {
                    Button("설정 열기") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                        store.send(.locationPermissionDeniedDismissed)
                    }
                    Button("확인", role: .cancel) {
                        store.send(.locationPermissionDeniedDismissed)
                    }
                } else {
                    Button("확인") {
                        store.send(.locationIntroductionConfirmed)
                    }
                    Button("나중에", role: .cancel) {
                        store.send(.locationIntroductionDismissed)
                    }
                }
            } message: {
                Text(
                    store.locationPrompt == .permissionDenied
                        ? "위치 권한이 거부되어 점검 당시 위치를 기록할 수 없습니다. 위치 정보를 기록하려면 설정에서 권한을 허용해주세요."
                        : "점검 당시 위치를 자동으로 기록합니다. 위치 권한을 허용하면 점검 저장 시 위도와 경도를 함께 보관할 수 있습니다."
                )
            }
            .toolbar {
                if store.mode.isEditable {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") {
                            store.send(.cancelButtonTapped)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장") {
                            store.send(.saveButtonTapped)
                        }
                        .disabled(store.isSaving)
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") {
                            store.send(.closeButtonTapped)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("수정") {
                            store.send(.editButtonTapped)
                        }
                    }
                }
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: { store.isCameraPresented },
                    set: { isPresented in
                        guard !isPresented else {
                            return
                        }

                        store.send(.cameraDismissed)
                    }
                )
            ) {
                SystemCameraView(
                    onImagePicked: { image in
                        guard let data = InspectionPhotoDataNormalizer.normalizedData(from: image) else {
                            store.send(.photoLoadingFailed)
                            return
                        }

                        store.send(.cameraImageCaptured(data))
                    },
                    onCancel: {
                        store.send(.cameraDismissed)
                    }
                )
                .ignoresSafeArea()
            }
            .alert(
                store.cameraError?.title ?? "카메라 오류",
                isPresented: Binding(
                    get: { store.cameraError != nil },
                    set: { isPresented in
                        guard !isPresented else {
                            return
                        }

                        store.send(.cameraErrorDismissed)
                    }
                )
            ) {
                if store.cameraError?.canOpenSettings == true {
                    Button("설정 열기") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                        store.send(.cameraErrorDismissed)
                    }
                }

                Button("확인", role: .cancel) {
                    store.send(.cameraErrorDismissed)
                }
            } message: {
                Text(store.cameraError?.message ?? "카메라를 사용할 수 없습니다.")
            }
        }
    }

    @ViewBuilder
    private var photoActionButtons: some View {
        switch store.mode {
        case .create:
            HStack(spacing: 8) {
                cameraButton(title: "촬영")
                photoLibraryButton(title: "선택")
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)

        case .editing:
            let isPhotoMissing = store.photoData == nil

            HStack(spacing: 8) {
                cameraButton(title: "촬영")
                photoLibraryButton(title: "선택")
                Button(role: .destructive) {
                    store.send(.deletePhotoButtonTapped)
                } label: {
                    Label("삭제", systemImage: "trash")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isPhotoMissing ? Color.secondary.opacity(0.75) : Color.red)
                        .frame(maxWidth: .infinity)
                }
                .tint(isPhotoMissing ? Color.secondary.opacity(0.75) : Color.red)
                .disabled(isPhotoMissing)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)

        case .view:
            EmptyView()
        }
    }

    private func cameraButton(title: String) -> some View {
        Button {
            store.send(.cameraButtonTapped)
        } label: {
            Label(title, systemImage: "camera")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private func photoLibraryButton(title: String) -> some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
            Label(title, systemImage: "photo.on.rectangle")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem else {
                return
            }

            Task { @MainActor in
                defer {
                    selectedPhoto = nil
                }

                do {
                    guard let data = try await newItem.loadTransferable(type: Data.self),
                          let normalizedData = InspectionPhotoDataNormalizer.normalizedData(from: data)
                    else {
                        store.send(.photoLoadingFailed)
                        return
                    }

                    store.send(.photoDataLoaded(normalizedData))
                } catch {
                    store.send(.photoLoadingFailed)
                }
            }
        }
    }
}

@MainActor
private enum InspectionPhotoDataNormalizer {
    private static let maximumDimension: CGFloat = 2_048
    private static let compressionQuality: CGFloat = 0.8

    static func normalizedData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else {
            return nil
        }

        return normalizedData(from: image)
    }

    static func normalizedData(from image: UIImage) -> Data? {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > 0 else {
            return nil
        }

        let scale = min(1, maximumDimension / longestSide)
        let targetSize = CGSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let renderedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return renderedImage.jpegData(compressionQuality: compressionQuality)
    }
}

struct SystemCameraView: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onImagePicked: onImagePicked,
            onCancel: onCancel
        )
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImagePicked: (UIImage) -> Void
        let onCancel: () -> Void

        init(
            onImagePicked: @escaping (UIImage) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onImagePicked = onImagePicked
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                onCancel()
                return
            }

            onImagePicked(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
