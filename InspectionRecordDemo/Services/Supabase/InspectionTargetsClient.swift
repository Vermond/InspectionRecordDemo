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

private struct SupabaseInspectionTargetInsertPayload: Encodable, Sendable {
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

private struct SupabaseInspectionTargetUpdatePayload: Encodable, Sendable {
    let name: String
    let equipmentNumber: String
    let updatedAt: Date

    init(target: SupabaseInspectionTarget) {
        self.name = target.name
        self.equipmentNumber = target.equipmentNumber
        self.updatedAt = target.updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case name
        case equipmentNumber = "equipment_number"
        case updatedAt = "updated_at"
    }
}

struct InspectionTargetsClient: Sendable {
    var fetch: @Sendable () async throws -> [SupabaseInspectionTarget]
    var insert: @Sendable (_ target: SupabaseInspectionTarget) async throws -> SupabaseInspectionTarget
    var update: @Sendable (_ target: SupabaseInspectionTarget) async throws -> SupabaseInspectionTarget
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
        insert: { target in
            let client = try makeSupabaseClient()

            return try await client
                .from("inspection_targets")
                .insert(SupabaseInspectionTargetInsertPayload(target: target))
                .select("id, name, equipment_number, created_at, updated_at")
                .single()
                .execute()
                .value
        },
        update: { target in
            let client = try makeSupabaseClient()

            return try await client
                .from("inspection_targets")
                .update(SupabaseInspectionTargetUpdatePayload(target: target))
                .eq("id", value: target.id.uuidString)
                .select("id, name, equipment_number, created_at, updated_at")
                .single()
                .execute()
                .value
        }
    )

    static let testValue = Self(
        fetch: { [] },
        insert: { $0 },
        update: { $0 }
    )
}

private func makeSupabaseClient() throws -> SupabaseClient {
    let configuration = try SupabaseConfiguration.load()
    return SupabaseClient(
        supabaseURL: configuration.url,
        supabaseKey: configuration.publishableKey
    )
}

extension DependencyValues {
    var inspectionTargetsClient: InspectionTargetsClient {
        get { self[InspectionTargetsClient.self] }
        set { self[InspectionTargetsClient.self] = newValue }
    }
}
