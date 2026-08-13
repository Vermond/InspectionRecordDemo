import ComposableArchitecture
import Foundation
import Supabase

struct SupabaseInspectionTarget: Decodable, Equatable, Sendable {
    let id: UUID
    let name: String
    let equipmentNumber: String
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

struct InspectionTargetsClient: Sendable {
    var fetch: @Sendable () async throws -> [SupabaseInspectionTarget]
}

extension InspectionTargetsClient: DependencyKey {
    static let liveValue = Self(
        fetch: {
            let configuration = try SupabaseConfiguration.load()
            let client = SupabaseClient(
                supabaseURL: configuration.url,
                supabaseKey: configuration.publishableKey
            )

            return try await client
                .from("inspection_targets")
                .select("id, name, equipment_number, created_at, updated_at")
                .execute()
                .value
        }
    )

    static let testValue = Self(
        fetch: { [] }
    )
}

extension DependencyValues {
    var inspectionTargetsClient: InspectionTargetsClient {
        get { self[InspectionTargetsClient.self] }
        set { self[InspectionTargetsClient.self] = newValue }
    }
}
