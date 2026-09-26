import Foundation

// MARK: - Supabase project credentials
enum SupabaseConfig {
    static let url = URL(string: "https://grliixgrwhzwgmarvmhi.supabase.co")!

    // Supabase publishable keys identify the project and are intentionally safe
    // to ship in a client app. Authorization remains enforced by Auth and RLS.
    static let anonKey = "sb_publishable_5HnQxMR829sOaiEOx80g-w_tNbAP_uS"
}
