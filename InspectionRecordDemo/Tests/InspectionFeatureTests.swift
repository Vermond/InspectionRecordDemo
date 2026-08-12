import ComposableArchitecture
import Foundation
import XCTest
@testable import InspectionRecordDemo

@MainActor
final class InspectionFeatureTests: XCTestCase {
    func testTaskLoadsPersistedSnapshot() async {
        let target = makeTarget()
        let record = makeRecord(for: target)
        let snapshot = InspectionRepository.Snapshot(
            targets: [target],
            records: [record]
        )
        let store = TestStore(initialState: InspectionListFeature.State()) {
            InspectionListFeature()
        } withDependencies: {
            $0.inspectionRepository = InspectionRepository(
                load: { snapshot },
                saveTarget: { _ in },
                saveRecord: { _ in }
            )
        }

        await store.send(.task) {
            $0.isLoading = true
        }
        await store.receive(\.persistenceLoaded.success) {
            $0.targets = [target]
            $0.records = [record]
            $0.isLoading = false
            $0.hasLoadedPersistence = true
        }
    }

    func testSavingTargetUpdatesStateAfterPersistenceSucceeds() async {
        let target = makeTarget()
        var initialState = InspectionListFeature.State()
        initialState.destination = .targetForm(TargetFormFeature.State())
        let store = TestStore(initialState: initialState) {
            InspectionListFeature()
        } withDependencies: {
            $0.inspectionRepository = makeRepository()
        }

        await store.send(
            .destination(.presented(.targetForm(.delegate(.saved(target)))))
        )
        await store.receive(\.targetPersisted) {
            $0.targets = [target]
            $0.destination = nil
        }
    }

    func testSavingTargetKeepsFormOpenWhenPersistenceFails() async {
        let target = makeTarget()
        var initialState = InspectionListFeature.State()
        initialState.destination = .targetForm(TargetFormFeature.State())
        let store = TestStore(initialState: initialState) {
            InspectionListFeature()
        } withDependencies: {
            $0.inspectionRepository = makeRepository(
                saveTarget: { _ in
                    throw InspectionPersistenceError.saveFailed
                }
            )
        }

        await store.send(
            .destination(.presented(.targetForm(.delegate(.saved(target)))))
        )
        await store.receive(\.persistenceFailed) {
            $0.persistenceErrorMessage = InspectionPersistenceError.saveFailed.userMessage
        }
        XCTAssertNotNil(store.state.destination)
    }

    func testSavingInspectionRecordInsertsRecordAfterPersistenceSucceeds() async {
        let target = makeTarget()
        let record = makeRecord(for: target)
        var initialState = InspectionListFeature.State()
        initialState.targets = [target]
        initialState.destination = .inspection(InspectionEditorFeature.State(target: target))
        let store = TestStore(initialState: initialState) {
            InspectionListFeature()
        } withDependencies: {
            $0.inspectionRepository = makeRepository()
        }

        await store.send(
            .destination(.presented(.inspection(.delegate(.saved(record)))))
        )
        await store.receive(\.recordPersisted) {
            $0.records = [record]
            $0.destination = nil
        }
    }

    func testSavingInspectionRecordWithExistingIDReplacesRecord() async {
        let target = makeTarget()
        let originalRecord = makeRecord(for: target, status: .normal, memo: "기존")
        let updatedRecord = InspectionRecord(
            id: originalRecord.id,
            targetID: originalRecord.targetID,
            targetName: originalRecord.targetName,
            equipmentNumber: originalRecord.equipmentNumber,
            createdAt: originalRecord.createdAt,
            photoData: Data([9]),
            status: .abnormal,
            memo: "수정"
        )
        var initialState = InspectionListFeature.State()
        initialState.records = [originalRecord]
        initialState.destination = .inspection(InspectionEditorFeature.State(record: originalRecord))
        let store = TestStore(initialState: initialState) {
            InspectionListFeature()
        } withDependencies: {
            $0.inspectionRepository = makeRepository()
        }

        await store.send(
            .destination(.presented(.inspection(.delegate(.saved(updatedRecord)))))
        )
        await store.receive(\.recordPersisted) {
            $0.records = [updatedRecord]
            $0.destination = nil
        }
    }

    func testSavingInspectionRecordKeepsEditorOpenWhenPersistenceFails() async {
        let target = makeTarget()
        let record = makeRecord(for: target, photoData: nil)
        var initialState = InspectionListFeature.State()
        initialState.targets = [target]
        initialState.destination = .inspection(InspectionEditorFeature.State(target: target))
        let store = TestStore(initialState: initialState) {
            InspectionListFeature()
        } withDependencies: {
            $0.inspectionRepository = makeRepository(
                saveRecord: { _ in
                    throw InspectionPersistenceError.saveFailed
                }
            )
        }

        await store.send(
            .destination(.presented(.inspection(.delegate(.saved(record)))))
        )
        await store.receive(\.persistenceFailed) {
            $0.persistenceErrorMessage = InspectionPersistenceError.saveFailed.userMessage
        }
        XCTAssertNotNil(store.state.destination)
    }

    func testLatestRecordAndHistorySearchUseCurrentState() {
        let target = makeTarget()
        let olderRecord = makeRecord(
            for: target,
            createdAt: Date(timeIntervalSince1970: 10),
            status: .normal,
            memo: "이상 없음"
        )
        let latestRecord = makeRecord(
            for: target,
            createdAt: Date(timeIntervalSince1970: 20),
            status: .caution,
            memo: "필터 교체"
        )
        var state = InspectionListFeature.State()
        state.records = [olderRecord, latestRecord]

        XCTAssertEqual(state.latestRecordsByTargetID[target.id], latestRecord)

        state.searchText = "필터"
        XCTAssertEqual(state.filteredRecords, [latestRecord])
    }

    func testInspectionCreationCancelSendsCancelledDelegate() async {
        let store = TestStore(
            initialState: InspectionEditorFeature.State(target: makeTarget())
        ) {
            InspectionEditorFeature()
        }

        await store.send(.cancelButtonTapped)
        await store.receive(\.delegate, .cancelled)
    }

    func testInspectionViewCloseSendsCancelledDelegate() async {
        let record = makeRecord(for: makeTarget())
        let store = TestStore(
            initialState: InspectionEditorFeature.State(record: record)
        ) {
            InspectionEditorFeature()
        }

        await store.send(.closeButtonTapped)
        await store.receive(\.delegate, .cancelled)
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

        let store = TestStore(initialState: initialState) {
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
        let expectedRecord = InspectionRecord(
            id: originalRecord.id,
            targetID: originalRecord.targetID,
            targetName: originalRecord.targetName,
            equipmentNumber: originalRecord.equipmentNumber,
            createdAt: originalRecord.createdAt,
            photoData: nil,
            status: originalRecord.status,
            memo: originalRecord.memo
        )

        await store.send(.deletePhotoButtonTapped) {
            $0.photoData = nil
        }
        await store.send(.saveButtonTapped)
        await store.receive(\.delegate, .saved(expectedRecord))
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

    private func makeRepository(
        saveTarget: @escaping @Sendable (InspectionTarget) async throws -> Void = { _ in },
        saveRecord: @escaping @Sendable (InspectionRecord) async throws -> Void = { _ in }
    ) -> InspectionRepository {
        InspectionRepository(
            load: {
                InspectionRepository.Snapshot(targets: [], records: [])
            },
            saveTarget: saveTarget,
            saveRecord: saveRecord
        )
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
        memo: String = ""
    ) -> InspectionRecord {
        InspectionRecord(
            id: UUID(),
            targetID: target.id,
            targetName: target.name,
            equipmentNumber: target.equipmentNumber,
            createdAt: createdAt,
            photoData: photoData,
            status: status,
            memo: memo
        )
    }
}
