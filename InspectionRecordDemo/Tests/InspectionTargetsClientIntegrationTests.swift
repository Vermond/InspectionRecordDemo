import Foundation
import XCTest
@testable import InspectionRecordDemo

@MainActor
final class InspectionTargetsClientIntegrationTests: XCTestCase {
    func testFetchesInspectionTargetFromSupabase() async throws {
        let expectedID = try XCTUnwrap(
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")
        )

        let targets = try await InspectionTargetsClient.liveValue.fetch()
        let target = try XCTUnwrap(
            targets.first(where: { $0.id == expectedID }),
            "Supabase inspection_targets에 테스트 대상이 없습니다."
        )

        XCTAssertEqual(target.name, "테스트")
        XCTAssertEqual(target.equipmentNumber, "TEST123")
        XCTAssertLessThanOrEqual(target.createdAt, target.updatedAt)
    }

    func testInsertsAndUpdatesInspectionTargetInSupabase() async throws {
        let id = UUID()
        let suffix = String(id.uuidString.prefix(8))
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let insertedName = "API 추가 \(suffix)"
        let insertedEquipmentNumber = "API-\(suffix)"
        let insertedTarget = SupabaseInspectionTarget(
            id: id,
            name: insertedName,
            equipmentNumber: insertedEquipmentNumber,
            createdAt: createdAt,
            updatedAt: createdAt
        )

        let client = InspectionTargetsClient.liveValue
        let inserted = try await client.insert(insertedTarget)

        XCTAssertEqual(inserted.id, id)
        XCTAssertEqual(inserted.name, insertedName)
        XCTAssertEqual(inserted.equipmentNumber, insertedEquipmentNumber)
        XCTAssertEqual(
            inserted.createdAt.timeIntervalSince1970,
            createdAt.timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertEqual(
            inserted.updatedAt.timeIntervalSince1970,
            createdAt.timeIntervalSince1970,
            accuracy: 0.001
        )

        let updatedAt = Date(timeIntervalSince1970: 1_700_000_060)
        let updatedName = "API 수정 \(suffix)"
        let updatedEquipmentNumber = "API-UPDATED-\(suffix)"
        var updateTarget = inserted
        updateTarget.name = updatedName
        updateTarget.equipmentNumber = updatedEquipmentNumber
        updateTarget.updatedAt = updatedAt

        let updated = try await client.update(updateTarget)

        XCTAssertEqual(updated.id, id)
        XCTAssertEqual(updated.name, updatedName)
        XCTAssertEqual(updated.equipmentNumber, updatedEquipmentNumber)
        XCTAssertEqual(
            updated.createdAt.timeIntervalSince1970,
            inserted.createdAt.timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertEqual(
            updated.updatedAt.timeIntervalSince1970,
            updatedAt.timeIntervalSince1970,
            accuracy: 0.001
        )
    }
}
