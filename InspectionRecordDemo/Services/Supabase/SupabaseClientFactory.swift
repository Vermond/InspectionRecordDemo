import Foundation
import Supabase

func makeSupabaseClient() throws -> SupabaseClient {
    let configuration = try SupabaseConfiguration.load()
    return SupabaseClient(
        supabaseURL: configuration.url,
        supabaseKey: configuration.publishableKey
    )
}
