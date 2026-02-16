import Foundation
import GRDB

/// Service for storing sensitive data in the app database
/// Replaces keychain storage to avoid macOS keychain access prompts
class KeychainService {
    static let shared = KeychainService()

    private init() {}

    // MARK: - YNAB Token

    func saveYNABToken(_ token: String) -> Bool {
        return saveToken(token, forKey: "ynab_api_token")
    }

    func getYNABToken() -> String? {
        return getToken(forKey: "ynab_api_token")
    }

    func deleteYNABToken() -> Bool {
        return deleteToken(forKey: "ynab_api_token")
    }

    // MARK: - Claude API Key

    func saveClaudeAPIKey(_ key: String) -> Bool {
        return saveToken(key, forKey: "claude_api_key")
    }

    func getClaudeAPIKey() -> String? {
        return getToken(forKey: "claude_api_key")
    }

    func deleteClaudeAPIKey() -> Bool {
        return deleteToken(forKey: "claude_api_key")
    }

    // MARK: - Generic Token Storage

    func saveToken(_ token: String, forKey key: String) -> Bool {
        do {
            try DatabaseManager.shared.write { db in
                try db.execute(
                    sql: "INSERT OR REPLACE INTO app_settings (key, value) VALUES (?, ?)",
                    arguments: [key, token]
                )
            }
            return true
        } catch {
            print("Error saving setting '\(key)': \(error)")
            return false
        }
    }

    func getToken(forKey key: String) -> String? {
        do {
            return try DatabaseManager.shared.read { db in
                try String.fetchOne(db, sql: "SELECT value FROM app_settings WHERE key = ?", arguments: [key])
            }
        } catch {
            print("Error reading setting '\(key)': \(error)")
            return nil
        }
    }

    func deleteToken(forKey key: String) -> Bool {
        do {
            try DatabaseManager.shared.write { db in
                try db.execute(sql: "DELETE FROM app_settings WHERE key = ?", arguments: [key])
            }
            return true
        } catch {
            print("Error deleting setting '\(key)': \(error)")
            return false
        }
    }

    // MARK: - Clear All

    func clearAll() -> Bool {
        do {
            try DatabaseManager.shared.write { db in
                try db.execute(sql: "DELETE FROM app_settings")
            }
            return true
        } catch {
            print("Error clearing settings: \(error)")
            return false
        }
    }
}
