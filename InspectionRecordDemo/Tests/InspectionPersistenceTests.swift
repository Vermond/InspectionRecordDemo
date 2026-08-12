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
            targetName: target.name,
            equipmentNumber: target.equipmentNumber,
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            photoData: Data([1, 2, 3]),
            status: .caution,
            memo: "필터 확인 필요"
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
            targetName: target.name,
            equipmentNumber: target.equipmentNumber,
            createdAt: Date(timeIntervalSince1970: 2_000_000),
            photoData: nil,
            status: .normal,
            memo: "이상 없음"
        )
        let updatedRecord = InspectionRecord(
            id: recordID,
            targetID: target.id,
            targetName: target.name,
            equipmentNumber: target.equipmentNumber,
            createdAt: Date(timeIntervalSince1970: 2_000_060),
            photoData: Data([4, 5, 6]),
            status: .abnormal,
            memo: "누유 확인"
        )

        try await database.saveTarget(target)
        try await database.saveRecord(originalRecord)
        try await database.saveRecord(updatedRecord)

        let snapshot = try await database.load()

        XCTAssertEqual(snapshot.records, [updatedRecord])
    }

    func testSaveRecordFailsWhenTargetDoesNotExist() async throws {
        let database = InspectionDatabase(modelContainer: try makeInMemoryContainer())
        let record = InspectionRecord(
            id: UUID(),
            targetID: UUID(),
            targetName: "없는 대상",
            equipmentNumber: "EQ-404",
            createdAt: Date(timeIntervalSince1970: 3_000_000),
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
}
