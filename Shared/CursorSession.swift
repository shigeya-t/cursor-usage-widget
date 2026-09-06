import Foundation
import Security
import SQLite3

enum CursorSessionError: LocalizedError {
    case databaseMissing
    case databaseOpenFailed
    case tokenMissing
    case tokenExpired
    case invalidToken

    var errorDescription: String? {
        switch self {
        case .databaseMissing: return "Cursor state database not found"
        case .databaseOpenFailed: return "Could not open Cursor state database"
        case .tokenMissing: return "No Cursor access token in local state"
        case .tokenExpired: return "Cursor access token expired"
        case .invalidToken: return "Invalid Cursor access token"
        }
    }
}

/// Cursor.app のローカルセッションと手動 Cookie を解決する。
enum CursorSession {
    private static let keychainService = "jp.shigeya.AIUsageWidget.cursor"
    private static let keychainAccount = "WorkosCursorSessionToken"
    private static let accessTokenKey = "cursorAuth/accessToken"

    static var defaultStateDBURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    /// Cookie ヘッダ値（`user_…%3A%3AeyJ…` 形式）を返す。
    static func resolveCookieValue() throws -> String {
        if let manual = loadManualCookie(), !manual.isEmpty {
            return normalizeCookieValue(manual)
        }
        return try cookieFromAppState()
    }

    static func hasAnyCredential() -> Bool {
        if let manual = loadManualCookie(), !manual.isEmpty { return true }
        return (try? cookieFromAppState()) != nil
    }

    static func saveManualCookie(_ raw: String) throws {
        let normalized = normalizeCookieValue(raw)
        guard !normalized.isEmpty else { throw CursorSessionError.invalidToken }
        // 簡易検証: JWT 部分があること
        _ = try parseCookieParts(normalized)
        try storeKeychain(normalized)
    }

    static func clearManualCookie() {
        deleteKeychain()
    }

    static func loadManualCookie() -> String? {
        readKeychain()
    }

    // MARK: - App state

    static func cookieFromAppState(dbURL: URL = defaultStateDBURL) throws -> String {
        let jwt = try readAccessToken(from: dbURL)
        guard let expiry = jwtExpiry(jwt), expiry.timeIntervalSinceNow > 60 else {
            throw CursorSessionError.tokenExpired
        }
        let sub = try jwtSubject(jwt)
        let cookie = "\(sub)%3A%3A\(jwt)"
        return cookie
    }

    static func readAccessToken(from dbURL: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw CursorSessionError.databaseMissing
        }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        let openResult: Int32
        // WAL が無い idle なファイルでは immutable を試す
        let uri = dbURL.path.hasPrefix("/") ? "file:\(dbURL.path)?immutable=1" : dbURL.path
        if sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK {
            openResult = SQLITE_OK
        } else {
            sqlite3_close(db)
            db = nil
            openResult = sqlite3_open_v2(dbURL.path, &db, flags, nil)
        }
        guard openResult == SQLITE_OK, let db else {
            throw CursorSessionError.databaseOpenFailed
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw CursorSessionError.databaseOpenFailed
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, accessTokenKey, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw CursorSessionError.tokenMissing
        }

        if let cString = sqlite3_column_text(statement, 0) {
            let text = String(cString: cString)
            if !text.isEmpty { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        let blob = sqlite3_column_blob(statement, 0)
        let bytes = sqlite3_column_bytes(statement, 0)
        guard let blob, bytes > 0 else { throw CursorSessionError.tokenMissing }
        let data = Data(bytes: blob, count: Int(bytes))
        if let utf8 = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !utf8.isEmpty
        {
            return utf8
        }
        // BOM なし UTF-16LE
        if data.count % 2 == 0,
           let utf16 = String(data: data, encoding: .utf16LittleEndian)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !utf16.isEmpty
        {
            return utf16.filter { $0 != "\0" }
        }
        throw CursorSessionError.tokenMissing
    }

    // MARK: - Cookie parsing

    static func normalizeCookieValue(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("cookie:") {
            value = String(value.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        if let range = value.range(of: "WorkosCursorSessionToken=", options: .caseInsensitive) {
            value = String(value[range.upperBound...])
            if let semi = value.firstIndex(of: ";") {
                value = String(value[..<semi])
            }
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // `user::jwt` → URL-encoded form
        if value.contains("::"), !value.contains("%3A%3A") {
            value = value.replacingOccurrences(of: "::", with: "%3A%3A")
        }
        // bare JWT: try to attach sub
        if !value.contains("%3A%3A"), value.split(separator: ".").count == 3,
           let sub = try? jwtSubject(value)
        {
            value = "\(sub)%3A%3A\(value)"
        }
        return value
    }

    static func parseCookieParts(_ cookie: String) throws -> (userID: String, jwt: String) {
        let normalized = normalizeCookieValue(cookie)
        let parts = normalized.components(separatedBy: "%3A%3A")
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw CursorSessionError.invalidToken
        }
        return (parts[0], parts[1])
    }

    static func jwtSubject(_ jwt: String) throws -> String {
        let segments = jwt.split(separator: ".")
        guard segments.count >= 2 else { throw CursorSessionError.invalidToken }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String,
              !sub.isEmpty
        else {
            throw CursorSessionError.invalidToken
        }
        return sub
    }

    static func jwtExpiry(_ jwt: String) -> Date? {
        let segments = jwt.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    // MARK: - Keychain

    private static func storeKeychain(_ value: String) throws {
        deleteKeychain()
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CursorSessionError.invalidToken
        }
    }

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
