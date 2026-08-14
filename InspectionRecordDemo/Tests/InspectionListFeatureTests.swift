import ComposableArchitecture
import Foundation
import XCTest
@testable import InspectionRecordDemo

private final class TestLocationPreference: @unchecked Sendable {
    var isSuppressed = false
}

@MainActor
final class InspectionListFeatureTests: XCTestCase {
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
                loadPendingRecords: { [] },
                saveTarget: { _ in },
                saveRecord: { _ in },
                updateSyncStatus: { _, _ in }
            )
            $0.inspectionTargetsClient = .testValue
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
        await store.receive(\.serverTargetsLoaded)
    }

    func testServerTargetDoesNotReplacePendingLocalTarget() async {
        let targetID = UUID()
        let localTarget = makeTarget(
            id: targetID,
            name: "로컬 대상",
            updatedAt: Date(timeIntervalSince1970: 1_000),
            syncStatus: .pending
        )
        let serverTarget = SupabaseInspectionTarget(
            id: targetID,
            name: "서버 대상",
            equipmentNumber: "SERVER-001",
            createdAt: localTarget.createdAt,
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        var initialState = InspectionListFeature.State()
        initialState.targets = [localTarget]
        let store = TestStore(initialState: initialState) {
            InspectionListFeature()
        }

        await store.send(.serverTargetsLoaded([serverTarget.domainValue]))
    }

    func testTaskLoadsServerTargetsIntoList() async {
        let serverTarget = SupabaseInspectionTarget(
            id: UUID(),
            name: "서버 설비",
            equipmentNumber: "SERVER-001",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let expectedTarget = serverTarget.domainValue
        let store = TestStore(initialState: InspectionListFeature.State()) {
            InspectionListFeature()
        } withDependencies: {
            $0.inspectionRepository = makeRepository()
            $0.inspectionTargetsClient = InspectionTargetsClient(
                fetch: { [serverTarget] },
                upsert: { $0 }
            )
        }

        await store.send(.task) {
            $0.isLoading = true
        }
        await store.receive(\.persistenceLoaded.success) {
            $0.isLoading = false
            $0.hasLoadedPersistence = true
        }
        await store.receive(\.serverTargetsLoaded) {
            $0.targets = [expectedTarget]
        }
    }

    func testNewerServerTargetReplacesOlderSyncedLocalTarget() async {
        let targetID = UUID()
        let localTarget = makeTarget(
            id: targetID,
            name: "기존 대상",
            updatedAt: Date(timeIntervalSince1970: 1_000),
            syncStatus: .synced
        )
        let serverTarget = SupabaseInspectionTarget(
            id: targetID,
            name: "최신 대상",
            equipmentNumber: "SERVER-001",
            createdAt: localTarget.createdAt,
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let expectedTarget = serverTarget.domainValue
        var initialState = InspectionListFeature.State()
        initialState.targets = [localTarget]
        let store = TestStore(initialState: initialState) {
            InspectionListFeature()
        } withDependencies: {
            $0.inspectionRepository = makeRepository()
        }

        await store.send(.serverTargetsLoaded([serverTarget.domainValue])) {
            $0.targets = [expectedTarget]
        }
    }

    func testOlderServerTargetDoesNotReplaceNewerSyncedLocalTarget() async {
        let targetID = UUID()
        let localTarget = makeTarget(
            id: targetID,
            name: "최신 로컬 대상",
            updatedAt: Date(timeIntervalSince1970: 2_000),
            syncStatus: .synced
        )
        let serverTarget = SupabaseInspectionTarget(
            id: targetID,
            name: "오래된 서버 대상",
            equipmentNumber: "SERVER-001",
            createdAt: localTarget.createdAt,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        var initialState = InspectionListFeature.State()
        initialState.targets = [localTarget]
        let store = TestStore(initialState: initialState) {
            InspectionListFeature()
        }

        await store.send(.serverTargetsLoaded([serverTarget.domainValue]))
    }

    func testTargetDetailButtonPresentsTargetDetailWithLatestInspectionDate() async {
        let target = makeTarget()
        let latestRecord = makeRecord(
            for: target,
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        var initialState = InspectionListFeature.State()
        initialState.targets = [target]
        initialState.records = [latestRecord]
        let store = TestStore(initialState: initialState) {
            InspectionListFeature()
        } withDependencies: {
            $0.inspectionRepository = makeRepository()
        }

        await store.send(.targetDetailButtonTapped(target.id)) {
            $0.destination = .targetDetail(
                TargetDetailFeature.State(
                    target: target,
                    latestInspectionAt: latestRecord.createdAt
                )
            )
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
        await store.receive(\.targetSynced) {
            $0.targets = [
                InspectionTarget(
                    id: target.id,
                    name: target.name,
                    equipmentNumber: target.equipmentNumber,
                    createdAt: target.createdAt,
                    updatedAt: target.updatedAt,
                    syncStatus: .synced
                )
            ]
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

    func testSavingTargetKeepsPendingStateWhenServerUpsertFails() async {
        let target = makeTarget()
        var initialState = InspectionListFeature.State()
        initialState.destination = .targetForm(TargetFormFeature.State())
        let store = TestStore(initialState: initialState) {
            InspectionListFeature()
        } withDependencies: {
            $0.inspectionRepository = makeRepository()
            $0.inspectionTargetsClient = InspectionTargetsClient(
                fetch: { [] },
                upsert: { _ in
                    throw InspectionPersistenceError.saveFailed
                }
            )
        }

        await store.send(
            .destination(.presented(.targetForm(.delegate(.saved(target)))))
        )
        await store.receive(\.targetPersisted) {
            $0.targets = [target]
            $0.destination = nil
        }
        await store.receive(\.targetSyncFailed) {
            $0.persistenceErrorMessage = "점검 대상은 로컬에 저장되었지만 서버 동기화에 실패했습니다."
        }
        XCTAssertEqual(store.state.targets.first?.syncStatus, .pending)
    }

    func testTargetSyncPreservesLocalUpdatedAt() async {
        let localUpdatedAt = Date(timeIntervalSince1970: 1_000)
        let serverUpdatedAt = Date(timeIntervalSince1970: 2_000)
        let target = makeTarget(updatedAt: localUpdatedAt)
        let serverTarget = SupabaseInspectionTarget(
            id: target.id,
            name: "서버 응답 대상",
            equipmentNumber: "SERVER-001",
            createdAt: target.createdAt,
            updatedAt: serverUpdatedAt
        )
        var initialState = InspectionListFeature.State()
        initialState.destination = .targetForm(TargetFormFeature.State())
        let store = TestStore(initialState: initialState) {
            InspectionListFeature()
        } withDependencies: {
            $0.inspectionRepository = makeRepository()
            $0.inspectionTargetsClient = InspectionTargetsClient(
                fetch: { [] },
                upsert: { _ in serverTarget }
            )
        }

        await store.send(
            .destination(.presented(.targetForm(.delegate(.saved(target)))))
        )
        await store.receive(\.targetPersisted) {
            $0.targets = [target]
            $0.destination = nil
        }
        await store.receive(\.targetSynced) {
            $0.targets = [
                InspectionTarget(
                    id: target.id,
                    name: serverTarget.name,
                    equipmentNumber: serverTarget.equipmentNumber,
                    createdAt: serverTarget.createdAt,
                    updatedAt: localUpdatedAt,
                    syncStatus: .synced
                )
            ]
        }
    }

    func testSavingTargetFromDetailUpdatesTargetWithoutChangingRecordSnapshots() async {
        let target = makeTarget()
        let record = makeRecord(for: target)
        var updatedTarget = target
        updatedTarget.name = "변경된 설비"
        updatedTarget.equipmentNumber = "EQ-002"
        updatedTarget.updatedAt = Date(timeIntervalSince1970: 2_000)

        var initialState = InspectionListFeature.State()
        initialState.targets = [target]
        initialState.records = [record]
        initialState.destination = .targetDetail(
            TargetDetailFeature.State(
                target: target,
                latestInspectionAt: record.createdAt
            )
        )
        let store = TestStore(initialState: initialState) {
            InspectionListFeature()
        } withDependencies: {
            $0.inspectionRepository = makeRepository()
        }

        await store.send(
            .destination(
                .presented(
                    .targetDetail(
                        .delegate(.targetSaveRequested(updatedTarget))
                    )
                )
            )
        )
        await store.receive(\.targetPersisted) {
            $0.targets = [updatedTarget]
            $0.records = [record]
            $0.destination = .targetDetail(
                TargetDetailFeature.State(
                    target: updatedTarget,
                    latestInspectionAt: record.createdAt
                )
            )
        }
        await store.receive(\.targetSynced) {
            var syncedTarget = updatedTarget
            syncedTarget.syncStatus = .synced
            $0.targets = [syncedTarget]
            $0.records = [record]
            $0.destination = .targetDetail(
                TargetDetailFeature.State(
                    target: syncedTarget,
                    latestInspectionAt: record.createdAt
                )
            )
        }
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
            $0.isLocationPermissionWarningPresented = true
        }
    }

    func testSavingInspectionRecordWithExistingIDReplacesRecord() async {
        let target = makeTarget()
        let originalRecord = makeRecord(for: target, status: .normal, memo: "기존")
        let updatedRecord = InspectionRecord(
            id: originalRecord.id,
            targetID: originalRecord.targetID,
            targetNameSnapshot: originalRecord.targetNameSnapshot,
            equipmentNumberSnapshot: originalRecord.equipmentNumberSnapshot,
            createdAt: originalRecord.createdAt,
            updatedAt: Date(timeIntervalSince1970: 1_000_060),
            photoData: Data([9]),
            status: .abnormal,
            memo: "수정",
            syncStatus: .pending
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
            $0.isLocationPermissionWarningPresented = true
        }
    }

    func testSavingRecordWithoutLocationShowsWarningWhenNotSuppressed() async {
        let target = makeTarget()
        let record = makeRecord(for: target)
        var initialState = InspectionListFeature.State()
        initialState.targets = [target]
        initialState.destination = .inspection(InspectionEditorFeature.State(target: target))
        let store = TestStore(initialState: initialState) {
            InspectionListFeature()
        } withDependencies: {
            $0.inspectionRepository = makeRepository()
            $0.locationPreferences = LocationPreferencesClient(
                suppressLocationPermissionWarning: { false },
                setSuppressLocationPermissionWarning: { _ in }
            )
        }

        await store.send(
            .destination(.presented(.inspection(.delegate(.saved(record)))))
        )
        await store.receive(\.recordPersisted) {
            $0.records = [record]
            $0.destination = nil
            $0.isLocationPermissionWarningPresented = true
        }
    }

    func testSavingRecordWithoutLocationHidesWarningWhenSuppressed() async {
        let target = makeTarget()
        let record = makeRecord(for: target)
        var initialState = InspectionListFeature.State()
        initialState.targets = [target]
        initialState.destination = .inspection(InspectionEditorFeature.State(target: target))
        let store = TestStore(initialState: initialState) {
            InspectionListFeature()
        } withDependencies: {
            $0.inspectionRepository = makeRepository()
            $0.locationPreferences = LocationPreferencesClient(
                suppressLocationPermissionWarning: { true },
                setSuppressLocationPermissionWarning: { _ in }
            )
        }

        await store.send(
            .destination(.presented(.inspection(.delegate(.saved(record)))))
        )
        await store.receive(\.recordPersisted) {
            $0.records = [record]
            $0.destination = nil
            $0.isLocationPermissionWarningPresented = false
        }
    }

    func testSuppressLocationWarningPersistsPreference() async {
        let preference = TestLocationPreference()
        var initialState = InspectionListFeature.State()
        initialState.isLocationPermissionWarningPresented = true
        let store = TestStore(initialState: initialState) {
            InspectionListFeature()
        } withDependencies: {
            $0.locationPreferences = LocationPreferencesClient(
                suppressLocationPermissionWarning: { preference.isSuppressed },
                setSuppressLocationPermissionWarning: { value in
                    preference.isSuppressed = value
                }
            )
        }

        await store.send(.locationPermissionWarningSuppressionRequested) {
            $0.isLocationPermissionWarningPresented = false
        }

        XCTAssertTrue(preference.isSuppressed)
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

    private func makeRepository(
        saveTarget: @escaping @Sendable (InspectionTarget) async throws -> Void = { _ in },
        saveRecord: @escaping @Sendable (InspectionRecord) async throws -> Void = { _ in }
    ) -> InspectionRepository {
        InspectionRepository(
            load: {
                InspectionRepository.Snapshot(targets: [], records: [])
            },
            loadPendingRecords: {
                []
            },
            saveTarget: saveTarget,
            saveRecord: saveRecord,
            updateSyncStatus: { _, _ in }
        )
    }

    private func makeTarget(
        id: UUID = UUID(),
        name: String = "냉각 설비",
        equipmentNumber: String = "EQ-001",
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        syncStatus: SyncStatus = .pending
    ) -> InspectionTarget {
        InspectionTarget(
            id: id,
            name: name,
            equipmentNumber: equipmentNumber,
            createdAt: createdAt,
            updatedAt: updatedAt,
            syncStatus: syncStatus
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
}
