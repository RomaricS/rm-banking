import Foundation
import Supabase
import AkweKit

enum AppConfig {
    static var supabaseURL: URL? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String, !s.isEmpty, s.hasPrefix("http") else { return nil }
        return URL(string: s)
    }
    static var supabaseKey: String { (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String) ?? "" }
    static var linkDomain: String { (Bundle.main.object(forInfoDictionaryKey: "AKWE_LINK_DOMAIN") as? String) ?? "akwe.app" }
    /// No backend configured → demo mode with sample data.
    static var isDemo: Bool { supabaseURL == nil || supabaseKey.isEmpty }
}

/// All network access. Every table read is RLS-scoped to the signed-in user by Supabase.
final class Backend: @unchecked Sendable {
    let client: SupabaseClient

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = Backend.parseTimestamp(s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(s)"))
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static func parseTimestamp(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        // Postgres sometimes omits the "T" or uses "+00" offsets
        let fixed = s.replacingOccurrences(of: " ", with: "T").replacingOccurrences(of: #"\+00$"#, with: "+00:00", options: .regularExpression)
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: fixed) ?? { f.formatOptions = [.withInternetDateTime]; return f.date(from: fixed) }()
    }

    init(url: URL, key: String) {
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(db: .init(encoder: Backend.encoder, decoder: Backend.decoder))
        )
    }

    // MARK: Auth

    func signInWithApple(idToken: String, nonce: String) async throws {
        try await client.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
    }

    func currentUserId() async -> UUID? { try? await client.auth.session.user.id }

    func signOut() async { try? await client.auth.signOut() }

    // MARK: Reads

    func fetch<T: Decodable>(_ table: String, order: String? = nil, ascending: Bool = true, limit: Int? = nil, since: (column: String, value: String)? = nil) async throws -> [T] {
        var query = client.from(table).select()
        if let since { query = query.gte(since.column, value: since.value) }
        if let order {
            let ordered = query.order(order, ascending: ascending)
            if let limit { return try await ordered.limit(limit).execute().value }
            return try await ordered.execute().value
        }
        return try await query.execute().value
    }

    func profile(_ id: UUID) async throws -> Profile {
        try await client.from("profiles").select().eq("id", value: id).single().execute().value
    }

    func paySchedule() async throws -> PaySchedule? {
        let rows: [PaySchedule] = try await client.from("pay_schedules").select().execute().value
        return rows.first
    }

    func prefs() async throws -> NotificationPrefs? {
        let rows: [NotificationPrefs] = try await client.from("notification_prefs").select().execute().value
        return rows.first
    }

    /// Transactions: up to ~2 years, paged (PostgREST max_rows = 5000).
    func transactions(since: Day) async throws -> [Transaction] {
        var all: [Transaction] = []
        var from = 0
        let page = 1000
        while true {
            let rows: [Transaction] = try await client.from("transactions").select()
                .gte("date", value: since.description)
                .order("date", ascending: false)
                .range(from: from, to: from + page - 1)
                .execute().value
            all += rows
            if rows.count < page { break }
            from += page
        }
        return all
    }

    func fxRates(since: Day) async throws -> [FXRate] {
        var all: [FXRate] = []
        var from = 0
        while true {
            let rows: [FXRate] = try await client.from("fx_rates").select().gte("date", value: since.description)
                .order("date").range(from: from, to: from + 4999).execute().value
            all += rows
            if rows.count < 5000 { break }
            from += 5000
        }
        return all
    }

    // MARK: Writes

    func update<V: Encodable>(_ table: String, id: UUID, _ values: V) async throws {
        try await client.from(table).update(values).eq("id", value: id).execute()
    }

    func insert<V: Encodable>(_ table: String, _ values: V) async throws {
        try await client.from(table).insert(values).execute()
    }

    func upsert<V: Encodable>(_ table: String, _ values: V, onConflict: String? = nil) async throws {
        try await client.from(table).upsert(values, onConflict: onConflict).execute()
    }

    func delete(_ table: String, id: UUID) async throws {
        try await client.from(table).delete().eq("id", value: id).execute()
    }

    func insertReturning<V: Encodable, R: Decodable>(_ table: String, _ values: V) async throws -> R {
        try await client.from(table).insert(values).select().single().execute().value
    }

    // MARK: Edge functions

    func invoke<R: Decodable>(_ name: String, _ body: [String: AnyJSON] = [:]) async throws -> R {
        try await client.functions.invoke(name, options: FunctionInvokeOptions(body: body), decoder: Backend.decoder)
    }

    func invokeVoid(_ name: String, _ body: [String: AnyJSON] = [:]) async throws {
        try await client.functions.invoke(name, options: FunctionInvokeOptions(body: body))
    }
}
