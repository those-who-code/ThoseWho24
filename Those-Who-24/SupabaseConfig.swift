import SwiftDotenv
import Foundation

// MARK: - Supabase project credentials
enum SupabaseConfig {
    private static let configured: Void = {
        if let path = Bundle.main.path(forResource: ".env", ofType: nil) {
            try? Dotenv.configure(atPath: path)
        } else {
            fatalError("Could not find .env in app bundle — add it to Copy Bundle Resources")
        }
    }()

    static let url: URL = {
        _ = configured
        guard let urlString = Dotenv["PROJECT_URL"]?.stringValue,
              let url = URL(string: urlString) else {
            fatalError("PROJECT_URL is missing or invalid in .env")
        }
        return url
    }()

    static let anonKey: String = {
        _ = configured
        guard let key = Dotenv["PUBLISHABLE_API_KEY"]?.stringValue else {
            fatalError("PUBLISHABLE_API_KEY is missing in .env")
        }
        return key
    }()
}

