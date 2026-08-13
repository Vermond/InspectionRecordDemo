import Foundation

struct SupabaseConfiguration: Sendable {
    let url: URL
    let publishableKey: String

    enum LoadingError: Error, Equatable, Sendable {
        case missingURL
        case invalidURL
        case missingPublishableKey
    }

    static func load() throws -> Self {
        guard let urlValue = setting("SUPABASE_URL") else {
            throw LoadingError.missingURL
        }

        guard let url = URL(string: urlValue),
              url.scheme != nil,
              url.host != nil
        else {
            throw LoadingError.invalidURL
        }

        guard let publishableKey = setting("SUPABASE_PUBLISHABLE_KEY") else {
            throw LoadingError.missingPublishableKey
        }

        return Self(url: url, publishableKey: publishableKey)
    }

    private static func setting(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedValue.isEmpty,
              !trimmedValue.contains("$(")
        else {
            return nil
        }

        return trimmedValue
    }
}
