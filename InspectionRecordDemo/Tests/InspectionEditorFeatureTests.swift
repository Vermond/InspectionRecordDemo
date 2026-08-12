import ComposableArchitecture
import Foundation
import XCTest
@testable import InspectionRecordDemo

@MainActor
final class InspectionEditorFeatureTests: XCTestCase {
    func testInspectionCreationCancelSendsCancelledDelegate() async {
        let store = TestStore(
            initialState: InspectionEditorFeature.State(target: makeTarget())
        ) {
            InspectionEditorFeature()
        }

        await store.send(.cancelButtonTapped)
        await store.receive { action in
            guard case .delegate(.cancelled) = action else {
                return false
            }

            return true
        }
    }

    func testInspectionViewCloseSendsCancelledDelegate() async {
        let record = makeRecord(for: makeTarget())
        let store = TestStore(
            initialState: InspectionEditorFeature.State(record: record)
        ) {
            InspectionEditorFeature()
        }

        await store.send(.closeButtonTapped)
        await store.receive { action in
            guard case .delegate(.cancelled) = action else {
                return false
            }

            return true
        }
    }

    func testCreatingInspectionRecordUsesCreatedAtAsUpdatedAtAndPendingStatus() async {
        let target = makeTarget()
        let store = TestStore(
            initialState: InspectionEditorFeature.State(target: target)
        ) {
            InspectionEditorFeature()
        }
        let createdAt = store.state.createdAt

        await store.send(.saveButtonTapped) {
            $0.isSaving = true
        }
        await store.receive { action in
            guard case .locationSaveCompleted(nil) = action else {
                return false
            }

            return true
        } assert: {
            $0.isSaving = false
            $0.isLocationLoading = false
        }
        await store.receive { action in
            guard case let .delegate(.saved(record)) = action else {
                return false
            }

            XCTAssertEqual(record.targetNameSnapshot, target.name)
            XCTAssertEqual(record.equipmentNumberSnapshot, target.equipmentNumber)
            XCTAssertEqual(record.createdAt, createdAt)
            XCTAssertEqual(record.updatedAt, createdAt)
            XCTAssertEqual(record.syncStatus, .pending)
            return true
        }
    }

    func testEditingInspectionRecordKeepsCreatedAtUpdatesUpdatedAtAndSetsPendingStatus() async {
        let target = makeTarget()
        let originalCreatedAt = Date(timeIntervalSince1970: 1_000)
        let originalUpdatedAt = Date(timeIntervalSince1970: 2_000)
        let originalRecord = InspectionRecord(
            id: UUID(),
            targetID: target.id,
            targetNameSnapshot: target.name,
            equipmentNumberSnapshot: target.equipmentNumber,
            createdAt: originalCreatedAt,
            updatedAt: originalUpdatedAt,
            photoData: nil,
            status: .normal,
            memo: "기존",
            syncStatus: .synced
        )
        let store = TestStore(
            initialState: InspectionEditorFeature.State(record: originalRecord)
        ) {
            InspectionEditorFeature()
        }

        await store.send(.editButtonTapped) {
            $0.mode = .editing
            $0.originalSnapshot = InspectionEditorFeature.State.Snapshot(
                photoData: originalRecord.photoData,
                status: originalRecord.status,
                memo: originalRecord.memo
            )
        }
        await store.send(.saveButtonTapped)
        await store.receive { action in
            guard case let .delegate(.saved(record)) = action else {
                return false
            }

            XCTAssertEqual(record.createdAt, originalCreatedAt)
            XCTAssertGreaterThan(record.updatedAt, originalUpdatedAt)
            XCTAssertEqual(record.syncStatus, .pending)
            return true
        }
    }

    func testLocationPreparationAcquiresLocationAndSavingIncludesSnapshot() async {
        let target = makeTarget()
        let sample = makeLocationSample()
        let store = TestStore(
            initialState: InspectionEditorFeature.State(target: target)
        ) {
            InspectionEditorFeature()
        } withDependencies: {
            $0.locationClient = LocationClient(
                authorizationStatus: { .authorized },
                requestWhenInUseAuthorization: { .authorized },
                requestCurrentLocation: { sample }
            )
        }

        await store.send(.locationPreparationRequested)
        await store.receive { action in
            guard case .locationAuthorizationChecked(.authorized, .preparation) = action else {
                return false
            }

            return true
        } assert: {
            $0.isLocationLoading = true
        }
        await store.receive { action in
            guard case .locationUpdated = action else {
                return false
            }

            return true
        } assert: {
            $0.latitude = sample.latitude
            $0.longitude = sample.longitude
            $0.locationCapturedAt = sample.capturedAt
            $0.isLocationLoading = false
        }

        await store.send(.saveButtonTapped)
        await store.receive { action in
            guard case let .delegate(.saved(record)) = action else {
                return false
            }

            XCTAssertEqual(record.latitude, sample.latitude)
            XCTAssertEqual(record.longitude, sample.longitude)
            XCTAssertEqual(record.createdAt, record.updatedAt)
            return true
        }
    }

    func testLocationIntroductionPrecedesPermissionRequestAndLocationAcquisition() async {
        let sample = makeLocationSample()
        let store = TestStore(
            initialState: InspectionEditorFeature.State(target: makeTarget())
        ) {
            InspectionEditorFeature()
        } withDependencies: {
            $0.locationClient = LocationClient(
                authorizationStatus: { .notDetermined },
                requestWhenInUseAuthorization: { .authorized },
                requestCurrentLocation: { sample }
            )
        }

        await store.send(.locationPreparationRequested)
        await store.receive { action in
            guard case .locationAuthorizationChecked(.notDetermined, .preparation) = action else {
                return false
            }

            return true
        } assert: {
            $0.locationPrompt = .introduction(.preparation)
        }
        await store.send(.locationIntroductionConfirmed) {
            $0.locationPrompt = nil
            $0.isLocationLoading = true
        }
        await store.receive { action in
            guard case .locationAuthorizationChecked(.authorized, .preparation) = action else {
                return false
            }

            return true
        }
        await store.receive { action in
            guard case .locationUpdated = action else {
                return false
            }

            return true
        } assert: {
            $0.latitude = sample.latitude
            $0.longitude = sample.longitude
            $0.locationCapturedAt = sample.capturedAt
            $0.isLocationLoading = false
        }
    }

    func testLocationPermissionDenialDuringPreparationSkipsWarning() async {
        let store = TestStore(
            initialState: InspectionEditorFeature.State(target: makeTarget())
        ) {
            InspectionEditorFeature()
        } withDependencies: {
            $0.locationClient = LocationClient(
                authorizationStatus: { .notDetermined },
                requestWhenInUseAuthorization: { .denied },
                requestCurrentLocation: { nil }
            )
        }

        await store.send(.locationPreparationRequested)
        await store.receive { action in
            guard case .locationAuthorizationChecked(.notDetermined, .preparation) = action else {
                return false
            }

            return true
        } assert: {
            $0.locationPrompt = .introduction(.preparation)
        }

        await store.send(.locationIntroductionConfirmed) {
            $0.locationPrompt = nil
            $0.isLocationLoading = true
        }
        await store.receive { action in
            guard case .locationAuthorizationChecked(.denied, .preparation) = action else {
                return false
            }

            return true
        } assert: {
            $0.isLocationLoading = false
            $0.locationPrompt = nil
        }
    }

    func testLocationRefreshWithDeniedPermissionPresentsWarning() async {
        let store = TestStore(
            initialState: InspectionEditorFeature.State(target: makeTarget())
        ) {
            InspectionEditorFeature()
        } withDependencies: {
            $0.locationClient = LocationClient(
                authorizationStatus: { .denied },
                requestWhenInUseAuthorization: { .denied },
                requestCurrentLocation: { nil }
            )
        }

        await store.send(.locationRefreshButtonTapped)
        await store.receive { action in
            guard case .locationAuthorizationChecked(.denied, .refresh) = action else {
                return false
            }

            return true
        } assert: {
            $0.locationPrompt = .permissionDenied
        }

        await store.send(.locationPermissionDeniedDismissed) {
            $0.locationPrompt = nil
        }
    }

    func testLocationPermissionDeniedStillSavesRecordWithoutLocation() async {
        let store = TestStore(
            initialState: InspectionEditorFeature.State(target: makeTarget())
        ) {
            InspectionEditorFeature()
        } withDependencies: {
            $0.locationClient = LocationClient(
                authorizationStatus: { .denied },
                requestWhenInUseAuthorization: { .denied },
                requestCurrentLocation: { nil }
            )
        }

        await store.send(.saveButtonTapped) {
            $0.isSaving = true
        }
        await store.receive { action in
            guard case .locationSaveCompleted(nil) = action else {
                return false
            }

            return true
        } assert: {
            $0.isSaving = false
            $0.isLocationLoading = false
        }
        await store.receive { action in
            guard case let .delegate(.saved(record)) = action else {
                return false
            }

            XCTAssertNil(record.latitude)
            XCTAssertNil(record.longitude)
            return true
        }
    }

    func testSavingWithStaleLocationRefreshesSnapshot() async {
        let sample = makeLocationSample(latitude: 35.1796, longitude: 129.0756)
        var initialState = InspectionEditorFeature.State(target: makeTarget())
        initialState.latitude = 37.5665
        initialState.longitude = 126.9780
        initialState.locationCapturedAt = Date(timeIntervalSinceNow: -600)

        let store = TestStore(initialState: initialState) {
            InspectionEditorFeature()
        } withDependencies: {
            $0.locationClient = LocationClient(
                authorizationStatus: { .authorized },
                requestWhenInUseAuthorization: { .authorized },
                requestCurrentLocation: { sample }
            )
        }

        await store.send(.saveButtonTapped) {
            $0.isSaving = true
        }
        await store.receive { action in
            guard case .locationSaveCompleted = action else {
                return false
            }

            return true
        } assert: {
            $0.isSaving = false
            $0.isLocationLoading = false
            $0.latitude = sample.latitude
            $0.longitude = sample.longitude
            $0.locationCapturedAt = sample.capturedAt
        }
        await store.receive { action in
            guard case let .delegate(.saved(record)) = action else {
                return false
            }

            XCTAssertEqual(record.latitude, sample.latitude)
            XCTAssertEqual(record.longitude, sample.longitude)
            return true
        }
    }

    func testLocationRefreshUsesNewLocation() async {
        let sample = makeLocationSample(latitude: 35.1796, longitude: 129.0756)
        let store = TestStore(
            initialState: InspectionEditorFeature.State(target: makeTarget())
        ) {
            InspectionEditorFeature()
        } withDependencies: {
            $0.locationClient = LocationClient(
                authorizationStatus: { .authorized },
                requestWhenInUseAuthorization: { .authorized },
                requestCurrentLocation: { sample }
            )
        }

        await store.send(.locationRefreshButtonTapped)
        await store.receive { action in
            guard case .locationAuthorizationChecked(.authorized, .refresh) = action else {
                return false
            }

            return true
        } assert: {
            $0.isLocationLoading = true
        }
        await store.receive { action in
            guard case .locationUpdated = action else {
                return false
            }

            return true
        } assert: {
            $0.latitude = sample.latitude
            $0.longitude = sample.longitude
            $0.locationCapturedAt = sample.capturedAt
            $0.isLocationLoading = false
        }
    }

    func testEditingRecordPreservesExistingLocationSnapshot() async {
        let target = makeTarget()
        let record = makeRecord(
            for: target,
            latitude: 37.5665,
            longitude: 126.9780
        )
        let store = TestStore(
            initialState: InspectionEditorFeature.State(record: record)
        ) {
            InspectionEditorFeature()
        } withDependencies: {
            $0.locationClient = LocationClient(
                authorizationStatus: { .denied },
                requestWhenInUseAuthorization: { .denied },
                requestCurrentLocation: { nil }
            )
        }

        await store.send(.editButtonTapped) {
            $0.mode = .editing
            $0.originalSnapshot = InspectionEditorFeature.State.Snapshot(
                photoData: record.photoData,
                status: record.status,
                memo: record.memo,
                latitude: record.latitude,
                longitude: record.longitude
            )
        }
        await store.send(.saveButtonTapped)
        await store.receive { action in
            guard case let .delegate(.saved(updatedRecord)) = action else {
                return false
            }

            XCTAssertEqual(updatedRecord.latitude, record.latitude)
            XCTAssertEqual(updatedRecord.longitude, record.longitude)
            return true
        }
    }

    func testCameraButtonPresentsCameraWhenAuthorized() async {
        let store = TestStore(
            initialState: InspectionEditorFeature.State(target: makeTarget())
        ) {
            InspectionEditorFeature()
        } withDependencies: {
            $0.cameraClient = CameraClient(
                authorizationStatus: { .authorized },
                requestAccess: { false },
                isAvailable: { true }
            )
        }

        await store.send(.cameraButtonTapped)
        await store.receive(\.cameraPresentationRequested) {
            $0.isCameraPresented = true
        }
    }

    func testCameraButtonRequestsPermissionAndShowsErrorWhenDenied() async {
        let store = TestStore(
            initialState: InspectionEditorFeature.State(target: makeTarget())
        ) {
            InspectionEditorFeature()
        } withDependencies: {
            $0.cameraClient = CameraClient(
                authorizationStatus: { .notDetermined },
                requestAccess: { false },
                isAvailable: { true }
            )
        }

        await store.send(.cameraButtonTapped)
        await store.receive(\.cameraPermissionDenied) {
            $0.cameraError = .permissionDenied
        }
    }

    func testCameraButtonShowsUnavailableErrorWhenCameraIsUnavailable() async {
        let store = TestStore(
            initialState: InspectionEditorFeature.State(target: makeTarget())
        ) {
            InspectionEditorFeature()
        } withDependencies: {
            $0.cameraClient = CameraClient(
                authorizationStatus: { .authorized },
                requestAccess: { true },
                isAvailable: { false }
            )
        }

        await store.send(.cameraButtonTapped)
        await store.receive(\.cameraUnavailable) {
            $0.cameraError = .unavailable
        }
    }

    func testCameraButtonShowsErrorWhenPermissionWasAlreadyDenied() async {
        let store = TestStore(
            initialState: InspectionEditorFeature.State(target: makeTarget())
        ) {
            InspectionEditorFeature()
        } withDependencies: {
            $0.cameraClient = CameraClient(
                authorizationStatus: { .denied },
                requestAccess: { true },
                isAvailable: { true }
            )
        }

        await store.send(.cameraButtonTapped)
        await store.receive(\.cameraPermissionDenied) {
            $0.cameraError = .permissionDenied
        }
    }

    func testCameraButtonPresentsCameraAfterPermissionRequestSucceeds() async {
        let store = TestStore(
            initialState: InspectionEditorFeature.State(target: makeTarget())
        ) {
            InspectionEditorFeature()
        } withDependencies: {
            $0.cameraClient = CameraClient(
                authorizationStatus: { .notDetermined },
                requestAccess: { true },
                isAvailable: { true }
            )
        }

        await store.send(.cameraButtonTapped)
        await store.receive(\.cameraPresentationRequested) {
            $0.isCameraPresented = true
        }
    }

    func testCapturedCameraImageReplacesCurrentPhoto() async {
        var initialState = InspectionEditorFeature.State(target: makeTarget())
        initialState.photoData = Data([9])
        initialState.isCameraPresented = true
        initialState.cameraError = .unavailable
        initialState.photoErrorMessage = "기존 오류"

        let store = TestStore(
            initialState: initialState
        ) {
            InspectionEditorFeature()
        }
        let photoData = Data([1, 2, 3])

        await store.send(.cameraImageCaptured(photoData)) {
            $0.photoData = photoData
            $0.isCameraPresented = false
            $0.cameraError = nil
            $0.photoErrorMessage = nil
        }
    }

    func testPhotoDataLoadedReplacesCurrentPhotoAndClearsError() async {
        var initialState = InspectionEditorFeature.State(target: makeTarget())
        initialState.photoData = Data([9])
        initialState.photoErrorMessage = "기존 오류"

        let store = TestStore(
            initialState: initialState
        ) {
            InspectionEditorFeature()
        }
        let photoData = Data([4, 5, 6])

        await store.send(.photoDataLoaded(photoData)) {
            $0.photoData = photoData
            $0.photoErrorMessage = nil
        }
    }

    func testPhotoLoadingFailedKeepsExistingPhotoAndShowsError() async {
        var initialState = InspectionEditorFeature.State(target: makeTarget())
        initialState.photoData = Data([9])

        let store = TestStore(initialState: initialState) {
            InspectionEditorFeature()
        }

        await store.send(.photoLoadingFailed) {
            $0.photoErrorMessage = "사진을 불러오지 못했습니다."
        }

        XCTAssertEqual(store.state.photoData, Data([9]))
    }

    func testDeletePhotoClearsPhotoInEditingMode() async {
        let target = makeTarget()
        let record = makeRecord(for: target, photoData: Data([1, 2, 3]))
        var initialState = InspectionEditorFeature.State(record: record)
        initialState.mode = .editing
        initialState.photoData = Data([1, 2, 3])

        let store = TestStore(initialState: initialState) {
            InspectionEditorFeature()
        }

        await store.send(.deletePhotoButtonTapped) {
            $0.photoData = nil
        }
    }

    func testDeletingPhotoThenSavingSendsRecordWithoutPhoto() async {
        let target = makeTarget()
        let originalRecord = makeRecord(for: target, photoData: Data([1, 2, 3]))
        var initialState = InspectionEditorFeature.State(record: originalRecord)
        initialState.mode = .editing

        let store = TestStore(initialState: initialState) {
            InspectionEditorFeature()
        }

        await store.send(.deletePhotoButtonTapped) {
            $0.photoData = nil
        }
        await store.send(.saveButtonTapped)
        await store.receive { action in
            guard case let .delegate(.saved(record)) = action else {
                return false
            }

            XCTAssertEqual(record.id, originalRecord.id)
            XCTAssertEqual(record.targetID, originalRecord.targetID)
            XCTAssertEqual(record.targetNameSnapshot, originalRecord.targetNameSnapshot)
            XCTAssertEqual(record.equipmentNumberSnapshot, originalRecord.equipmentNumberSnapshot)
            XCTAssertEqual(record.createdAt, originalRecord.createdAt)
            XCTAssertGreaterThan(record.updatedAt, originalRecord.updatedAt)
            XCTAssertEqual(record.syncStatus, .pending)
            XCTAssertNil(record.photoData)
            XCTAssertEqual(record.status, originalRecord.status)
            XCTAssertEqual(record.memo, originalRecord.memo)
            return true
        }
    }

    func testInspectionEditingCancelRestoresOriginalSnapshot() async {
        let target = makeTarget()
        let record = makeRecord(for: target, status: .normal, memo: "기존 메모")
        let store = TestStore(
            initialState: InspectionEditorFeature.State(record: record)
        ) {
            InspectionEditorFeature()
        }

        await store.send(.editButtonTapped) {
            $0.mode = .editing
            $0.originalSnapshot = InspectionEditorFeature.State.Snapshot(
                photoData: record.photoData,
                status: record.status,
                memo: record.memo
            )
        }
        await store.send(.binding(.set(\.memo, "변경된 메모"))) {
            $0.memo = "변경된 메모"
        }
        await store.send(.cancelButtonTapped) {
            $0.mode = .view
            $0.photoData = record.photoData
            $0.status = record.status
            $0.memo = record.memo
            $0.originalSnapshot = nil
        }
    }

    func testInspectionEditingCancelRestoresOriginalPhotoAfterReplacement() async {
        let target = makeTarget()
        let record = makeRecord(for: target, photoData: Data([1]), status: .normal)
        let store = TestStore(
            initialState: InspectionEditorFeature.State(record: record)
        ) {
            InspectionEditorFeature()
        }

        await store.send(.editButtonTapped) {
            $0.mode = .editing
            $0.originalSnapshot = InspectionEditorFeature.State.Snapshot(
                photoData: record.photoData,
                status: record.status,
                memo: record.memo
            )
        }
        await store.send(.cameraImageCaptured(Data([2]))) {
            $0.photoData = Data([2])
        }
        await store.send(.cancelButtonTapped) {
            $0.mode = .view
            $0.photoData = record.photoData
            $0.status = record.status
            $0.memo = record.memo
            $0.originalSnapshot = nil
        }
    }

    func testInspectionEditingCancelRestoresOriginalPhotoAfterDeletion() async {
        let target = makeTarget()
        let record = makeRecord(for: target, photoData: Data([1]), status: .normal)
        let store = TestStore(
            initialState: InspectionEditorFeature.State(record: record)
        ) {
            InspectionEditorFeature()
        }

        await store.send(.editButtonTapped) {
            $0.mode = .editing
            $0.originalSnapshot = InspectionEditorFeature.State.Snapshot(
                photoData: record.photoData,
                status: record.status,
                memo: record.memo
            )
        }
        await store.send(.deletePhotoButtonTapped) {
            $0.photoData = nil
        }
        await store.send(.cancelButtonTapped) {
            $0.mode = .view
            $0.photoData = record.photoData
            $0.status = record.status
            $0.memo = record.memo
            $0.originalSnapshot = nil
        }
    }

    private func makeTarget() -> InspectionTarget {
        InspectionTarget(
            id: UUID(),
            name: "냉각 설비",
            equipmentNumber: "EQ-001"
        )
    }

    private func makeRecord(
        for target: InspectionTarget,
        createdAt: Date = Date(timeIntervalSince1970: 1_000),
        photoData: Data? = nil,
        status: InspectionStatus? = .normal,
        memo: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil
    ) -> InspectionRecord {
        InspectionRecord(
            id: UUID(),
            targetID: target.id,
            targetNameSnapshot: target.name,
            equipmentNumberSnapshot: target.equipmentNumber,
            createdAt: createdAt,
            updatedAt: createdAt,
            photoData: photoData,
            status: status,
            memo: memo,
            syncStatus: .pending,
            latitude: latitude,
            longitude: longitude
        )
    }

    private func makeLocationSample(
        latitude: Double = 37.5665,
        longitude: Double = 126.9780,
        capturedAt: Date = Date()
    ) -> LocationSample {
        LocationSample(
            latitude: latitude,
            longitude: longitude,
            capturedAt: capturedAt
        )
    }
}
