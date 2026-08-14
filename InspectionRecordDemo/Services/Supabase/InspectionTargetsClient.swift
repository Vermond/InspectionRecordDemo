import ComposableArchitecture
import Foundation
import Supabase

struct SupabaseInspectionTarget: Decodable, Equatable, Sendable {
    let id: UUID
    var name: String
    var equipmentNumber: String
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case equipmentNumber = "equipment_number"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

extension SupabaseInspectionTarget {
    init(target: InspectionTarget) {
        self.init(
            id: target.id,
            name: target.name,
            equipmentNumber: target.equipmentNumber,
            createdAt: target.createdAt,
            updatedAt: target.updatedAt
        )
    }

    var domainValue: InspectionTarget {
        InspectionTarget(
            id: id,
            name: name,
            equipmentNumber: equipmentNumber,
            createdAt: createdAt,
            updatedAt: updatedAt,
            syncStatus: .synced
        )
    }

    func domainValue(preservingUpdatedAt updatedAt: Date) -> InspectionTarget {
        InspectionTarget(
            id: id,
            name: name,
            equipmentNumber: equipmentNumber,
            createdAt: createdAt,
            updatedAt: updatedAt,
            syncStatus: .synced
        )
    }
}

private struct SupabaseInspectionTargetUpsertPayload: Encodable, Sendable {
    let id: UUID
    let name: String
    let equipmentNumber: String
    let createdAt: Date
    let updatedAt: Date

    init(target: SupabaseInspectionTarget) {
        self.id = target.id
        self.name = target.name
        self.equipmentNumber = target.equipmentNumber
        self.createdAt = target.createdAt
        self.updatedAt = target.updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case equipmentNumber = "equipment_number"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct InspectionTargetsClient: Sendable {
    var fetch: @Sendable () async throws -> [SupabaseInspectionTarget]
    var upsert: @Sendable (_ target: SupabaseInspectionTarget) async throws -> SupabaseInspectionTarget
}

extension InspectionTargetsClient: DependencyKey {
    static let liveValue = Self(
        fetch: {
            let client = try makeSupabaseClient()

            return try await client
                .from("inspection_targets")
                .select("id, name, equipment_number, created_at, updated_at")
                .execute()
                .value
        },
        upsert: { target in
            let client = try makeSupabaseClient()

            return try await client
                .from("inspection_targets")
                .upsert(
                    SupabaseInspectionTargetUpsertPayload(target: target),
                    onConflict: "id"
                )
                .select("id, name, equipment_number, created_at, updated_at")
                .single()
                .execute()
                .value
        }
    )

    static let testValue = Self(
        fetch: { [] },
        upsert: { $0 }
    )
}

extension DependencyValues {
    var inspectionTargetsClient: InspectionTargetsClient {
        get { self[InspectionTargetsClient.self] }
        set { self[InspectionTargetsClient.self] = newValue }
    }
}
