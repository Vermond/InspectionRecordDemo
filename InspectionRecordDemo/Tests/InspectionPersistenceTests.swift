import Foundation
import SwiftData
import XCTest
@testable import InspectionRecordDemo

@MainActor
final class InspectionPersistenceTests: XCTestCase {
    func testSaveAndLoadPreservesTargetAndRecordAfterCreatingNewDatabaseActor() async throws {
        let container = try makeInMemoryContainer()
        let database = InspectionDatabase(modelContainer: container)
        let target = InspectionTarget(
            id: UUID(),
            name: "냉각 설비",
            equipmentNumber: "EQ-001"
        )
        let record = InspectionRecord(
            id: UUID(),
            targetID: target.id,
            targetNameSnapshot: target.name,
            equipmentNumberSnapshot: target.equipmentNumber,
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_000_060),
            photoData: Data([1, 2, 3]),
            status: .caution,
            memo: "필터 확인 필요",
            syncStatus: .synced
        )

        try await database.saveTarget(target)
        try await database.saveRecord(record)

        let reloadedDatabase = InspectionDatabase(modelContainer: container)
        let snapshot = try await reloadedDatabase.load()

        XCTAssertEqual(snapshot.targets, [target])
        XCTAssertEqual(snapshot.records, [record])
    }

    func testSaveRecordWithSameIDUpdatesExistingRecord() async throws {
        let container = try makeInMemoryContainer()
        let database = InspectionDatabase(modelContainer: container)
        let target = InspectionTarget(
            id: UUID(),
            name: "압축기",
            equipmentNumber: "EQ-002"
        )
        let recordID = UUID()
        let originalRecord = InspectionRecord(
            id: recordID,
            targetID: target.id,
            targetNameSnapshot: target.name,
            equipmentNumberSnapshot: target.equipmentNumber,
            createdAt: Date(timeIntervalSince1970: 2_000_000),
            updatedAt: Date(timeIntervalSince1970: 2_000_000),
            photoData: nil,
            status: .normal,
            memo: "이상 없음",
            syncStatus: .synced
        )
        let updatedRecord = InspectionRecord(
            id: recordID,
            targetID: target.id,
            targetNameSnapshot: target.name,
            equipmentNumberSnapshot: target.equipmentNumber,
            createdAt: Date(timeIntervalSince1970: 2_000_000),
            updatedAt: Date(timeIntervalSince1970: 2_000_120),
            photoData: Data([4, 5, 6]),
            status: .abnormal,
            memo: "누유 확인",
            syncStatus: .pending
        )

        try await database.saveTarget(target)
        try await database.saveRecord(originalRecord)
        try await database.saveRecord(updatedRecord)

        let snapshot = try await database.load()

        XCTAssertEqual(snapshot.records, [updatedRecord])
    }

    func testUpdatingTargetDoesNotChangeRecordSnapshot() async throws {
        let container = try makeInMemoryContainer()
        let database = InspectionDatabase(modelContainer: container)
        let target = InspectionTarget(
            id: UUID(),
            name: "기존 설비",
            equipmentNumber: "EQ-003"
        )
        let record = InspectionRecord(
            id: UUID(),
            targetID: target.id,
            targetNameSnapshot: target.name,
            equipmentNumberSnapshot: target.equipmentNumber,
            createdAt: Date(timeIntervalSince1970: 2_500_000),
            updatedAt: Date(timeIntervalSince1970: 2_500_000),
            photoData: nil,
            status: .normal,
            memo: "기록 당시 정보"
        )
        let updatedTarget = InspectionTarget(
            id: target.id,
            name: "변경된 설비",
            equipmentNumber: "EQ-004"
        )

        try await database.saveTarget(target)
        try await database.saveRecord(record)
        try await database.saveTarget(updatedTarget)

        let snapshot = try await database.load()

        XCTAssertEqual(snapshot.records.first?.targetNameSnapshot, target.name)
        XCTAssertEqual(snapshot.records.first?.equipmentNumberSnapshot, target.equipmentNumber)
    }

    func testLoadPendingRecordsReturnsOnlyPendingRecordsSortedByUpdatedAt() async throws {
        let container = try makeInMemoryContainer()
        let database = InspectionDatabase(modelContainer: container)
        let target = InspectionTarget(
            id: UUID(),
            name: "펌프",
            equipmentNumber: "EQ-005"
        )
        let olderPendingRecord = makeRecord(
            target: target,
            id: UUID(),
            updatedAt: Date(timeIntervalSince1970: 4_000_000),
            syncStatus: .pending
        )
        let newerPendingRecord = makeRecord(
            target: target,
            id: UUID(),
            updatedAt: Date(timeIntervalSince1970: 4_000_120),
            syncStatus: .pending
        )
        let syncedRecord = makeRecord(
            target: target,
            id: UUID(),
            updatedAt: Date(timeIntervalSince1970: 4_000_240),
            syncStatus: .synced
        )

        try await database.saveTarget(target)
        try await database.saveRecord(olderPendingRecord)
        try await database.saveRecord(newerPendingRecord)
        try await database.saveRecord(syncedRecord)

        let pendingRecords = try await database.loadPendingRecords()

        XCTAssertEqual(pendingRecords, [newerPendingRecord, olderPendingRecord])
    }

    func testUpdateSyncStatusPersistsStatusChange() async throws {
        let container = try makeInMemoryContainer()
        let database = InspectionDatabase(modelContainer: container)
        let target = InspectionTarget(
            id: UUID(),
            name: "송풍기",
            equipmentNumber: "EQ-006"
        )
        let record = makeRecord(
            target: target,
            id: UUID(),
            updatedAt: Date(timeIntervalSince1970: 5_000_000),
            syncStatus: .pending
        )

        try await database.saveTarget(target)
        try await database.saveRecord(record)
        try await database.updateSyncStatus(for: record.id, to: .synced)

        let snapshot = try await database.load()
        let pendingRecords = try await database.loadPendingRecords()

        XCTAssertEqual(snapshot.records.first?.syncStatus, .synced)
        XCTAssertEqual(pendingRecords, [])
    }

    func testSaveRecordFailsWhenTargetDoesNotExist() async throws {
        let database = InspectionDatabase(modelContainer: try makeInMemoryContainer())
        let record = InspectionRecord(
            id: UUID(),
            targetID: UUID(),
            targetNameSnapshot: "없는 대상",
            equipmentNumberSnapshot: "EQ-404",
            createdAt: Date(timeIntervalSince1970: 3_000_000),
            updatedAt: Date(timeIntervalSince1970: 3_000_000),
            photoData: nil,
            status: nil,
            memo: ""
        )

        do {
            try await database.saveRecord(record)
            XCTFail("존재하지 않는 대상의 이력 저장은 실패해야 합니다.")
        } catch let error as InspectionPersistenceError {
            XCTAssertEqual(error, .targetNotFound)
        } catch {
            XCTFail("예상하지 못한 오류가 발생했습니다: \(error)")
        }
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            for: InspectionTargetModel.self,
            InspectionRecordModel.self,
            isStoredInMemoryOnly: true
        )

        return try ModelContainer(
            for: InspectionTargetModel.self,
            InspectionRecordModel.self,
            configurations: configuration
        )
    }

    private func makeRecord(
        target: InspectionTarget,
        id: UUID,
        updatedAt: Date,
        syncStatus: SyncStatus
    ) -> InspectionRecord {
        InspectionRecord(
            id: id,
            targetID: target.id,
            targetNameSnapshot: target.name,
            equipmentNumberSnapshot: target.equipmentNumber,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            photoData: nil,
            status: .normal,
            memo: "",
            syncStatus: syncStatus
        )
    }
}
