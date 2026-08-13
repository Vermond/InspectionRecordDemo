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

    func testSyncsInspectionRecordWithAllPhotoActionsInSupabase() async throws {
        let targetID = try XCTUnwrap(
            UUID(uuidString: "22222222-2222-2222-2222-222222222222")
        )
        let photoData = try XCTUnwrap(
            Data(base64Encoded: Self.testJPEGBase64)
        )
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let record = InspectionRecord(
            id: UUID(),
            targetID: targetID,
            targetNameSnapshot: "1층 공조기",
            equipmentNumberSnapshot: "AHU-001",
            createdAt: createdAt,
            updatedAt: createdAt.addingTimeInterval(60),
            photoData: photoData,
            status: nil,
            memo: "사진 동기화 통합 테스트",
            latitude: nil,
            longitude: nil
        )

        let client = InspectionRecordsClient.liveValue
        let uploaded = try await client.sync(record, .upload)

        XCTAssertEqual(uploaded.id, record.id)
        XCTAssertEqual(uploaded.targetID, record.targetID)
        XCTAssertEqual(
            uploaded.targetNameSnapshot,
            record.targetNameSnapshot
        )
        XCTAssertEqual(
            uploaded.equipmentNumberSnapshot,
            record.equipmentNumberSnapshot
        )
        XCTAssertNil(uploaded.status)
        XCTAssertEqual(uploaded.memo, record.memo)
        XCTAssertEqual(uploaded.createdAt, record.createdAt)
        XCTAssertEqual(uploaded.updatedAt, record.updatedAt)
        XCTAssertNil(uploaded.latitude)
        XCTAssertNil(uploaded.longitude)
        XCTAssertEqual(uploaded.photoData, photoData)
        XCTAssertEqual(uploaded.syncStatus, .synced)

        var keepRecord = uploaded
        keepRecord.updatedAt = createdAt.addingTimeInterval(120)
        keepRecord.memo = "사진 유지 통합 테스트"
        let kept = try await client.sync(keepRecord, .keep)

        XCTAssertEqual(kept.id, record.id)
        XCTAssertEqual(kept.updatedAt, keepRecord.updatedAt)
        XCTAssertEqual(kept.memo, keepRecord.memo)
        XCTAssertEqual(kept.photoData, photoData)
        XCTAssertEqual(kept.syncStatus, .synced)

        var deleteRecord = kept
        deleteRecord.updatedAt = createdAt.addingTimeInterval(180)
        let deleted = try await client.sync(deleteRecord, .delete)

        XCTAssertEqual(deleted.id, record.id)
        XCTAssertEqual(deleted.updatedAt, deleteRecord.updatedAt)
        XCTAssertNil(deleted.photoData)
        XCTAssertEqual(deleted.syncStatus, .synced)
    }

    func testRejectsInspectionRecordPhotoOverFiveMiB() async {
        let record = InspectionRecord(
            id: UUID(),
            targetID: UUID(),
            targetNameSnapshot: "테스트 대상",
            equipmentNumberSnapshot: "TEST-001",
            createdAt: Date(),
            updatedAt: Date(),
            photoData: Data(
                repeating: 0xFF,
                count: 5 * 1024 * 1024 + 1
            ),
            status: nil,
            memo: ""
        )

        do {
            _ = try await InspectionRecordsClient.liveValue.sync(
                record,
                .upload
            )
            XCTFail("5MiB를 초과한 사진은 전송 전에 거부되어야 합니다.")
        } catch let error as InspectionRecordsClientError {
            XCTAssertEqual(error, .photoTooLarge)
        } catch {
            XCTFail("예상하지 못한 오류: \(error)")
        }
    }

    func testRejectsNonJPEGInspectionRecordPhoto() async {
        let record = InspectionRecord(
            id: UUID(),
            targetID: UUID(),
            targetNameSnapshot: "테스트 대상",
            equipmentNumberSnapshot: "TEST-001",
            createdAt: Date(),
            updatedAt: Date(),
            photoData: Data([0x89, 0x50, 0x4E, 0x47]),
            status: nil,
            memo: ""
        )

        do {
            _ = try await InspectionRecordsClient.liveValue.sync(
                record,
                .upload
            )
            XCTFail("JPEG가 아닌 사진은 전송 전에 거부되어야 합니다.")
        } catch let error as InspectionRecordsClientError {
            XCTAssertEqual(error, .invalidJPEG)
        } catch {
            XCTFail("예상하지 못한 오류: \(error)")
        }
    }

    private static let testJPEGBase64 =
        "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAH/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAEFAqf/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/Aaf/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/Aaf/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAY/Aqf/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/IV//2gAMAwEAAgADAAAAEP/EABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQMBAT8QH//EABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQIBAT8QH//EABQQAQAAAAAAAAAAAAAAAAAAABD/2gAIAQEAAT8QH//Z"
}
