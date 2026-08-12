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
}
