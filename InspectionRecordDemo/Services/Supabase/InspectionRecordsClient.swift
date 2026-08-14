import ComposableArchitecture
import Foundation
import ImageIO
import Supabase

enum InspectionRecordPhotoAction: String, Equatable, Sendable {
    case keep
    case upload
    case delete
}

enum InspectionRecordsClientError: Error, Equatable, Sendable {
    case photoRequired
    case invalidJPEG
    case photoTooLarge
    case invalidResponse
    case server(code: String, retryable: Bool?, statusCode: Int?)
}

private struct InspectionRecordPayload: Codable, Sendable {
    let id: UUID
    let targetID: UUID
    let targetNameSnapshot: String
    let equipmentNumberSnapshot: String
    let status: String?
    let memo: String
    let latitude: Double?
    let longitude: Double?
    let photoPath: String?
    let createdAt: Date
    let updatedAt: Date

    init(record: InspectionRecord) {
        self.id = record.id
        self.targetID = record.targetID
        self.targetNameSnapshot = record.targetNameSnapshot
        self.equipmentNumberSnapshot = record.equipmentNumberSnapshot
        self.status = record.status?.rawValue
        self.memo = record.memo
        self.latitude = record.latitude
        self.longitude = record.longitude
        self.photoPath = nil
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.targetID = try (
            container.decodeIfPresent(UUID.self, forKey: .targetID)
                ?? container.decode(UUID.self, forKey: .targetIDSnakeCase)
        )
        self.targetNameSnapshot = try (
            container.decodeIfPresent(
                String.self,
                forKey: .targetNameSnapshot
            ) ?? container.decode(
                String.self,
                forKey: .targetNameSnapshotSnakeCase
            )
        )
        self.equipmentNumberSnapshot = try (
            container.decodeIfPresent(
                String.self,
                forKey: .equipmentNumberSnapshot
            ) ?? container.decode(
                String.self,
                forKey: .equipmentNumberSnapshotSnakeCase
            )
        )
        self.status = try container.decodeIfPresent(
            String.self,
            forKey: .status
        )
        self.memo = try container.decode(String.self, forKey: .memo)
        self.latitude = try container.decodeIfPresent(
            Double.self,
            forKey: .latitude
        )
        self.longitude = try container.decodeIfPresent(
            Double.self,
            forKey: .longitude
        )
        self.photoPath = try (
            container.decodeIfPresent(String.self, forKey: .photoPath)
                ?? container.decodeIfPresent(String.self, forKey: .photoPathCamel)
        )
        self.createdAt = try (
            container.decodeIfPresent(Date.self, forKey: .createdAt)
                ?? container.decode(Date.self, forKey: .createdAtSnakeCase)
        )
        self.updatedAt = try (
            container.decodeIfPresent(Date.self, forKey: .updatedAt)
                ?? container.decode(Date.self, forKey: .updatedAtSnakeCase)
        )
    }

    func inspectionRecord(
        preservingPhotoData photoData: Data?,
        syncStatus: SyncStatus
    ) -> InspectionRecord {
        InspectionRecord(
            id: id,
            targetID: targetID,
            targetNameSnapshot: targetNameSnapshot,
            equipmentNumberSnapshot: equipmentNumberSnapshot,
            createdAt: createdAt,
            updatedAt: updatedAt,
            photoData: photoData,
            status: status.flatMap(InspectionStatus.init(rawValue:)),
            memo: memo,
            syncStatus: syncStatus,
            latitude: latitude,
            longitude: longitude
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case targetID = "targetId"
        case targetIDSnakeCase = "target_id"
        case targetNameSnapshot
        case targetNameSnapshotSnakeCase = "target_name_snapshot"
        case equipmentNumberSnapshot
        case equipmentNumberSnapshotSnakeCase = "equipment_number_snapshot"
        case status
        case memo
        case latitude
        case longitude
        case photoPath = "photo_path"
        case photoPathCamel = "photoPath"
        case createdAt
        case createdAtSnakeCase = "created_at"
        case updatedAt
        case updatedAtSnakeCase = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(targetID, forKey: .targetID)
        try container.encode(targetNameSnapshot, forKey: .targetNameSnapshot)
        try container.encode(equipmentNumberSnapshot, forKey: .equipmentNumberSnapshot)
        try container.encode(status, forKey: .status)
        try container.encode(memo, forKey: .memo)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

private struct SyncInspectionResponse: Decodable, Sendable {
    let success: Bool
    let record: InspectionRecordPayload?
    let code: String?
    let retryable: Bool?
}

struct InspectionRecordsClient: Sendable {
    var fetch: @Sendable () async throws -> [InspectionRecord]
    var sync: @Sendable (
        _ record: InspectionRecord,
        _ photoAction: InspectionRecordPhotoAction
    ) async throws -> InspectionRecord
}

extension InspectionRecordsClient: DependencyKey {
    static let liveValue = Self(
        fetch: {
            let client = try makeSupabaseClient()
            let payloads: [InspectionRecordPayload] = try await client
                .from("inspection_records")
                .select(
                    "id, target_id, target_name_snapshot, "
                        + "equipment_number_snapshot, status, memo, latitude, "
                        + "longitude, photo_path, created_at, updated_at"
                )
                .execute()
                .value

            return payloads.map {
                $0.inspectionRecord(
                    preservingPhotoData: nil,
                    syncStatus: .synced
                )
            }
        },
        sync: { record, photoAction in
            let photoData = try validatePhoto(
                record.photoData,
                for: photoAction
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let recordData = try encoder.encode(InspectionRecordPayload(record: record))
            let multipart = makeMultipartBody(
                recordData: recordData,
                photoAction: photoAction,
                photoData: photoData
            )
            let options = FunctionInvokeOptions(
                method: .post,
                headers: ["Content-Type": multipart.contentType],
                body: multipart.body
            )
            let client = try makeSupabaseClient()

            do {
                let responseData: Data = try await client.functions.invoke(
                    "sync-inspection",
                    options: options,
                    decode: { data, _ in data }
                )
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let response = try decoder.decode(
                    SyncInspectionResponse.self,
                    from: responseData
                )

                guard response.success,
                      let responseRecord = response.record,
                      responseRecord.id == record.id
                else {
                    if let code = response.code {
                        throw InspectionRecordsClientError.server(
                            code: code,
                            retryable: response.retryable,
                            statusCode: nil
                        )
                    }

                    throw InspectionRecordsClientError.invalidResponse
                }

                let synchronizedPhotoData: Data?
                switch photoAction {
                case .keep, .upload:
                    synchronizedPhotoData = record.photoData
                case .delete:
                    synchronizedPhotoData = nil
                }

                return responseRecord.inspectionRecord(
                    preservingPhotoData: synchronizedPhotoData,
                    syncStatus: .synced
                )
            } catch let FunctionsError.httpError(statusCode, data) {
                let decoder = JSONDecoder()
                if let response = try? decoder.decode(
                    SyncInspectionResponse.self,
                    from: data
                ),
                   let code = response.code {
                    throw InspectionRecordsClientError.server(
                        code: code,
                        retryable: response.retryable,
                        statusCode: statusCode
                    )
                }

                throw FunctionsError.httpError(code: statusCode, data: data)
            }
        }
    )

    static let testValue = Self(
        fetch: { [] },
        sync: { record, _ in record }
    )
}

private let maximumPhotoSize = 5 * 1024 * 1024

private func validatePhoto(
    _ photoData: Data?,
    for photoAction: InspectionRecordPhotoAction
) throws -> Data? {
    guard photoAction == .upload else {
        return nil
    }

    guard let photoData else {
        throw InspectionRecordsClientError.photoRequired
    }

    guard photoData.count <= maximumPhotoSize else {
        throw InspectionRecordsClientError.photoTooLarge
    }

    guard let imageSource = CGImageSourceCreateWithData(
              photoData as CFData,
              nil
          ),
          let imageType = CGImageSourceGetType(imageSource),
          (imageType as String) == "public.jpeg"
    else {
        throw InspectionRecordsClientError.invalidJPEG
    }

    return photoData
}

private func makeMultipartBody(
    recordData: Data,
    photoAction: InspectionRecordPhotoAction,
    photoData: Data?
) -> (body: Data, contentType: String) {
    var form = MultipartFormData()
    form.appendField(
        name: "record",
        value: String(decoding: recordData, as: UTF8.self)
    )
    form.appendField(name: "photoAction", value: photoAction.rawValue)

    if let photoData {
        form.appendFile(
            name: "photo",
            filename: "photo.jpg",
            contentType: "image/jpeg",
            data: photoData
        )
    }

    return (
        body: form.finalizedData(),
        contentType: "multipart/form-data; boundary=\(form.boundary)"
    )
}

private struct MultipartFormData: Sendable {
    let boundary = "Boundary-\(UUID().uuidString)"
    private var data = Data()

    mutating func appendField(name: String, value: String) {
        appendUTF8("--\(boundary)\r\n")
        appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendUTF8("\(value)\r\n")
    }

    mutating func appendFile(
        name: String,
        filename: String,
        contentType: String,
        data: Data
    ) {
        appendUTF8("--\(boundary)\r\n")
        appendUTF8(
            "Content-Disposition: form-data; name=\"\(name)\"; "
                + "filename=\"\(filename)\"\r\n"
        )
        appendUTF8("Content-Type: \(contentType)\r\n\r\n")
        self.data.append(data)
        appendUTF8("\r\n")
    }

    func finalizedData() -> Data {
        var finalizedData = data
        finalizedData.append(contentsOf: "--\(boundary)--\r\n".utf8)
        return finalizedData
    }

    private mutating func appendUTF8(_ string: String) {
        data.append(contentsOf: string.utf8)
    }
}

extension DependencyValues {
    var inspectionRecordsClient: InspectionRecordsClient {
        get { self[InspectionRecordsClient.self] }
        set { self[InspectionRecordsClient.self] = newValue }
    }
}
