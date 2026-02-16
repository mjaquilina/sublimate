import Foundation
import GRDB

/// Manages the SQLite database for the application
class DatabaseManager {
    static let shared = DatabaseManager()

    private var dbQueue: DatabaseQueue?
    private var currentDatabasePath: String?

    private static let databasePathKey = "selectedDatabasePath"
    private static let defaultDatabaseName = "sublimate.db"

    private init() {}

    /// Initialize the database at the specified path
    func initialize() throws {
        // Check if user has selected a custom database path
        if let savedPath = UserDefaults.standard.string(forKey: Self.databasePathKey) {
            try initializeDatabase(at: savedPath)
        } else {
            // Use default database
            let defaultPath = try getDefaultDatabasePath()
            try initializeDatabase(at: defaultPath)
        }
    }

    /// Initialize database at a specific path
    func initializeDatabase(at path: String) throws {
        let fileManager = FileManager.default

        // Ensure directory exists
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        // Backup existing database before opening (and before migrations)
        if fileManager.fileExists(atPath: path) {
            let backupPath = path + ".backup"
            do {
                if fileManager.fileExists(atPath: backupPath) {
                    try fileManager.removeItem(atPath: backupPath)
                }
                try fileManager.copyItem(atPath: path, toPath: backupPath)
                print("✅ Pre-migration backup created: \(backupPath)")
            } catch {
                print("⚠️ Pre-migration backup failed: \(error)")
            }
        }

        var config = Configuration()
        config.prepareDatabase { db in
            db.trace { print("SQL: \($0)") }
        }

        dbQueue = try DatabaseQueue(path: path, configuration: config)
        currentDatabasePath = path

        try migrator.migrate(dbQueue!)

        // Save this as the selected database
        UserDefaults.standard.set(path, forKey: Self.databasePathKey)

        print("📁 Database initialized at: \(path)")
    }

    /// Switch to a different database file
    func switchDatabase(to path: String) throws {
        let fileManager = FileManager.default

        // Check if file exists and is accessible
        guard fileManager.fileExists(atPath: path) else {
            throw DatabaseError.fileNotFound
        }

        // Verify we can read the file (sandboxing check)
        guard fileManager.isReadableFile(atPath: path) else {
            throw DatabaseError.noPermission
        }

        // Close current database
        dbQueue = nil

        // Open new database
        try initializeDatabase(at: path)
    }

    /// Create a new database file with the given name
    func createNewDatabase(name: String) throws -> String {
        let appFolder = try getDatabaseDirectory()
        let sanitizedName = name.replacingOccurrences(of: " ", with: "_")
        let fileName = sanitizedName.hasSuffix(".db") ? sanitizedName : "\(sanitizedName).db"
        let newPath = appFolder.appendingPathComponent(fileName).path

        // Check if file already exists
        if FileManager.default.fileExists(atPath: newPath) {
            throw DatabaseError.fileAlreadyExists
        }

        // Create and initialize the new database
        try initializeDatabase(at: newPath)

        return newPath
    }

    /// Get the default database path
    func getDefaultDatabasePath() throws -> String {
        let appFolder = try getDatabaseDirectory()
        return appFolder.appendingPathComponent(Self.defaultDatabaseName).path
    }

    /// Get the directory where databases are stored
    func getDatabaseDirectory() throws -> URL {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let appFolder = appSupport.appendingPathComponent("Sublimate", isDirectory: true)
        try fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)

        return appFolder
    }

    /// List all database files in the database directory
    func listDatabaseFiles() throws -> [DatabaseFileInfo] {
        let directory = try getDatabaseDirectory()
        let fileManager = FileManager.default

        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])

        let dbFiles = contents.filter { $0.pathExtension == "db" }

        return try dbFiles.map { url in
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let size = attributes[.size] as? Int64 ?? 0
            let modifiedDate = attributes[.modificationDate] as? Date ?? Date()
            let isCurrent = url.path == currentDatabasePath

            return DatabaseFileInfo(
                name: url.lastPathComponent,
                path: url.path,
                size: size,
                modifiedDate: modifiedDate,
                isCurrent: isCurrent
            )
        }.sorted { $0.modifiedDate > $1.modifiedDate }
    }

    /// Get the current database file path
    func getCurrentDatabasePath() -> String? {
        return currentDatabasePath
    }

    /// Get the database queue for performing operations
    func database() throws -> DatabaseQueue {
        guard let queue = dbQueue else {
            throw DatabaseError.notInitialized
        }
        return queue
    }

    /// Get the database file URL
    /// Get the current database file URL
    func getDatabaseURL() throws -> URL {
        guard let path = currentDatabasePath else {
            throw DatabaseError.notInitialized
        }
        return URL(fileURLWithPath: path)
    }

    /// Perform a database operation
    func read<T>(_ operation: (Database) throws -> T) throws -> T {
        try database().read(operation)
    }

    /// Perform a write operation
    func write<T>(_ operation: (Database) throws -> T) throws -> T {
        try database().write(operation)
    }

    // MARK: - Backup

    /// Copy the current database file to <path>.backup, overwriting any previous backup
    func backupDatabase() {
        guard let path = currentDatabasePath else {
            print("⚠️ Cannot backup: no database path set")
            return
        }

        let backupPath = path + ".backup"
        let fileManager = FileManager.default

        do {
            if fileManager.fileExists(atPath: backupPath) {
                try fileManager.removeItem(atPath: backupPath)
            }
            try fileManager.copyItem(atPath: path, toPath: backupPath)
            print("✅ Database backed up to: \(backupPath)")
        } catch {
            print("❌ Database backup failed: \(error)")
        }
    }

    // MARK: - Database Migrations

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // DISABLED: This erases user data when schema changes!
        // #if DEBUG
        // migrator.eraseDatabaseOnSchemaChange = true
        // #endif

        migrator.registerMigration("v1_initial_schema") { db in
            // Create cards table
            try db.create(table: "cards") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("issuer", .text).notNull()
                t.column("lastFour", .text).notNull()
                t.column("notes", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Create point_types table
            try db.create(table: "point_types") { t in
                t.column("id", .text).primaryKey()
                t.column("cardId", .text).notNull()
                    .references("cards", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("cashValuePerPoint", .numeric).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "idx_point_types_card_id", on: "point_types", columns: ["cardId"])

            // Create point_balances table
            try db.create(table: "point_balances") { t in
                t.column("id", .text).primaryKey()
                t.column("pointTypeId", .text).notNull().unique()
                    .references("point_types", onDelete: .cascade)
                t.column("balance", .numeric).notNull().defaults(to: 0)
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "idx_point_balances_point_type_id", on: "point_balances", columns: ["pointTypeId"])

            // Create earning_rules table
            try db.create(table: "earning_rules") { t in
                t.column("id", .text).primaryKey()
                t.column("cardId", .text).notNull()
                    .references("cards", onDelete: .cascade)
                t.column("pointTypeId", .text).notNull()
                    .references("point_types", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("matchType", .text).notNull()
                t.column("matchValues", .text).notNull()  // JSON array
                t.column("pointsPerDollar", .numeric).notNull()
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "idx_earning_rules_card_id", on: "earning_rules", columns: ["cardId"])
            try db.create(index: "idx_earning_rules_active", on: "earning_rules", columns: ["isActive"])

            // Create spend_offers table
            try db.create(table: "spend_offers") { t in
                t.column("id", .text).primaryKey()
                t.column("cardId", .text).notNull()
                    .references("cards", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("offerType", .text).notNull()
                t.column("matchType", .text).notNull()
                t.column("matchValues", .text).notNull()  // JSON array
                t.column("rewardPercentage", .numeric)
                t.column("maxRewardAmount", .numeric)
                t.column("flatBonusAmount", .numeric)
                t.column("spendThreshold", .numeric)
                t.column("countRequired", .integer)
                t.column("transactionMinAmount", .numeric)
                t.column("pointTypeId", .text)
                    .references("point_types", onDelete: .setNull)
                t.column("startDate", .datetime).notNull()
                t.column("endDate", .datetime).notNull()
                t.column("currentSpend", .numeric).notNull().defaults(to: 0)
                t.column("currentCount", .integer).notNull().defaults(to: 0)
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "idx_spend_offers_card_id", on: "spend_offers", columns: ["cardId"])
            try db.create(index: "idx_spend_offers_active", on: "spend_offers", columns: ["isActive"])
            try db.create(index: "idx_spend_offers_dates", on: "spend_offers", columns: ["startDate", "endDate"])

            // Create rebates table
            try db.create(table: "rebates") { t in
                t.column("id", .text).primaryKey()
                t.column("cardId", .text).notNull()
                    .references("cards", onDelete: .cascade)
                t.column("vendor", .text).notNull()
                t.column("rebateType", .text).notNull()
                t.column("rebateValue", .numeric).notNull()
                t.column("maxAmount", .numeric)
                t.column("maxUses", .integer)
                t.column("usesRemaining", .integer)
                t.column("startDate", .datetime)
                t.column("endDate", .datetime)
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "idx_rebates_card_id", on: "rebates", columns: ["cardId"])
            try db.create(index: "idx_rebates_vendor", on: "rebates", columns: ["vendor"])
            try db.create(index: "idx_rebates_active", on: "rebates", columns: ["isActive"])

            // Create transactions table
            try db.create(table: "transactions") { t in
                t.column("id", .text).primaryKey()
                t.column("cardId", .text).notNull()
                    .references("cards", onDelete: .cascade)
                t.column("date", .datetime).notNull()
                t.column("vendor", .text).notNull()
                t.column("merchantCategory", .text)
                t.column("amount", .numeric).notNull()
                t.column("transactionType", .text).notNull()
                t.column("rewardEligible", .boolean).notNull().defaults(to: true)
                t.column("notes", .text)
                t.column("ynabTransactionId", .text).unique()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "idx_transactions_card_id", on: "transactions", columns: ["cardId"])
            try db.create(index: "idx_transactions_date", on: "transactions", columns: ["date"])
            try db.create(index: "idx_transactions_vendor", on: "transactions", columns: ["vendor"])
            try db.create(index: "idx_transactions_ynab_id", on: "transactions", columns: ["ynabTransactionId"])

            // Create transaction_rewards table
            try db.create(table: "transaction_rewards") { t in
                t.column("id", .text).primaryKey()
                t.column("transactionId", .text).notNull()
                    .references("transactions", onDelete: .cascade)
                t.column("rewardSourceType", .text).notNull()
                t.column("rewardSourceId", .text).notNull()
                t.column("pointTypeId", .text)
                    .references("point_types", onDelete: .setNull)
                t.column("pointsEarned", .numeric)
                t.column("cashValue", .numeric).notNull()
                t.column("description", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "idx_transaction_rewards_transaction_id", on: "transaction_rewards", columns: ["transactionId"])
            try db.create(index: "idx_transaction_rewards_source", on: "transaction_rewards", columns: ["rewardSourceType", "rewardSourceId"])

            // Create point_redemptions table
            try db.create(table: "point_redemptions") { t in
                t.column("id", .text).primaryKey()
                t.column("pointTypeId", .text).notNull()
                    .references("point_types", onDelete: .cascade)
                t.column("date", .datetime).notNull()
                t.column("pointsRedeemed", .numeric).notNull()
                t.column("redemptionType", .text).notNull()
                t.column("cashValue", .numeric)
                t.column("description", .text).notNull()
                t.column("linkedTransactionId", .text)
                    .references("transactions", onDelete: .setNull)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "idx_point_redemptions_point_type_id", on: "point_redemptions", columns: ["pointTypeId"])
            try db.create(index: "idx_point_redemptions_date", on: "point_redemptions", columns: ["date"])

            // Create statement_credit_links table
            try db.create(table: "statement_credit_links") { t in
                t.column("id", .text).primaryKey()
                t.column("transactionId", .text).notNull().unique()
                    .references("transactions", onDelete: .cascade)
                t.column("sourceType", .text).notNull()
                t.column("sourceId", .text)
                t.column("notes", .text)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "idx_statement_credit_links_transaction_id", on: "statement_credit_links", columns: ["transactionId"])

            // Create ynab_account_mappings table
            try db.create(table: "ynab_account_mappings") { t in
                t.column("id", .text).primaryKey()
                t.column("ynabBudgetId", .text).notNull()
                t.column("ynabAccountId", .text).notNull()
                t.column("ynabAccountName", .text).notNull()
                t.column("cardId", .text).notNull()
                    .references("cards", onDelete: .cascade)
                t.column("lastImportDate", .datetime)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.uniqueKey(["ynabBudgetId", "ynabAccountId"])
            }
            try db.create(index: "idx_ynab_mappings_card_id", on: "ynab_account_mappings", columns: ["cardId"])

            // Create vendor_mappings table
            try db.create(table: "vendor_mappings") { t in
                t.column("id", .text).primaryKey()
                t.column("rawVendorName", .text).notNull()
                t.column("normalizedVendorName", .text).notNull().unique()
                t.column("displayName", .text).notNull()
                t.column("category", .text)
                t.column("useCount", .integer).notNull().defaults(to: 1)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "idx_vendor_mappings_normalized", on: "vendor_mappings", columns: ["normalizedVendorName"])
        }

        // Add categories table
        migrator.registerMigration("v2_add_categories") { db in
            try db.create(table: "categories") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull().unique()
                t.column("icon", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "idx_categories_name", on: "categories", columns: ["name"])

            // Insert default categories using proper GRDB insert
            let defaultCategories = [
                ("Dining", "fork.knife"),
                ("Groceries", "cart"),
                ("Gas", "fuelpump"),
                ("Travel", "airplane"),
                ("Shopping", "bag"),
                ("Entertainment", "theatermasks"),
                ("Utilities", "bolt"),
                ("Healthcare", "cross.case"),
                ("Transportation", "car"),
                ("Home Improvement", "hammer"),
                ("Electronics", "laptopcomputer"),
                ("Subscriptions", "arrow.triangle.2.circlepath"),
                ("Other", "ellipsis.circle")
            ]

            // Import Category here to avoid circular dependency issues
            struct CategoryRecord: Codable, FetchableRecord, PersistableRecord {
                static let databaseTableName = "categories"
                var id: String  // Store as string in migration
                var name: String
                var icon: String?
                var createdAt: Date
                var updatedAt: Date
            }

            for (name, icon) in defaultCategories {
                let category = CategoryRecord(
                    id: UUID().uuidString,
                    name: name,
                    icon: icon,
                    createdAt: Date(),
                    updatedAt: Date()
                )
                try category.insert(db)
            }
        }

        migrator.registerMigration("v3_add_vendors") { db in
            try db.create(table: "vendors") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull().unique()  // Normalized name for matching
                t.column("displayName", .text).notNull()    // User-friendly display name
                t.column("defaultCategoryId", .text)
                    .references("categories", onDelete: .setNull)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "idx_vendors_name", on: "vendors", columns: ["name"])
        }

        migrator.registerMigration("v4_add_earning_caps") { db in
            // Create earning_caps table
            try db.create(table: "earning_caps") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("maxSpend", .numeric).notNull()
                t.column("currentSpend", .numeric).notNull().defaults(to: 0)
                t.column("startDate", .datetime).notNull()
                t.column("endDate", .datetime).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "idx_earning_caps_dates", on: "earning_caps", columns: ["startDate", "endDate"])

            // Create earning_rule_caps junction table
            try db.create(table: "earning_rule_caps") { t in
                t.column("earningRuleId", .text).notNull()
                    .references("earning_rules", onDelete: .cascade)
                t.column("earningCapId", .text).notNull()
                    .references("earning_caps", onDelete: .cascade)
                t.primaryKey(["earningRuleId", "earningCapId"])
            }
            try db.create(index: "idx_earning_rule_caps_rule", on: "earning_rule_caps", columns: ["earningRuleId"])
            try db.create(index: "idx_earning_rule_caps_cap", on: "earning_rule_caps", columns: ["earningCapId"])
        }

        migrator.registerMigration("v5_add_linked_transaction_id") { db in
            // Add linkedTransactionId column to transactions table for statement credit linking
            try db.alter(table: "transactions") { t in
                t.add(column: "linkedTransactionId", .text)
                    .references("transactions", onDelete: .setNull)
            }
            try db.create(index: "idx_transactions_linked_id", on: "transactions", columns: ["linkedTransactionId"])
        }

        migrator.registerMigration("v6_fix_category_uuids") { db in
            // Convert binary UUID data to string format
            print("🔧 Converting category UUIDs from binary to string format...")

            let rows = try Row.fetchAll(db, sql: "SELECT * FROM categories")
            print("📊 Found \(rows.count) categories to convert")

            for row in rows {
                let name: String = row["name"]

                // Try to get the ID - it might be Data or String
                var uuidString: String?

                if let data = row["id"] as? Data, data.count == 16 {
                    // Binary UUID - convert to string
                    let uuid = UUID(uuid: (
                        data[0], data[1], data[2], data[3],
                        data[4], data[5], data[6], data[7],
                        data[8], data[9], data[10], data[11],
                        data[12], data[13], data[14], data[15]
                    ))
                    uuidString = uuid.uuidString
                    print("  Converting '\(name)': binary -> \(uuidString!)")
                } else if let str = row["id"] as? String {
                    // Already a string
                    uuidString = str
                    print("  '\(name)': already string format ✓")
                } else {
                    print("  ⚠️ Unknown ID format for '\(name)', generating new UUID")
                    uuidString = UUID().uuidString
                }

                // Update the row with string UUID
                try db.execute(
                    sql: "UPDATE categories SET id = ? WHERE name = ?",
                    arguments: [uuidString!, name]
                )
            }

            print("✅ Category UUID conversion complete")
        }

        migrator.registerMigration("v7_fix_all_binary_uuids") { db in
            // Re-run category UUID conversion with correct code
            print("🔧 [v7] Converting category UUIDs from binary to string format...")

            let categoryRows = try Row.fetchAll(db, sql: "SELECT * FROM categories")
            print("📊 [v7] Found \(categoryRows.count) categories")

            for row in categoryRows {
                let name: String = row["name"]
                var uuidString: String?

                if let data = row["id"] as? Data, data.count == 16 {
                    let uuid = UUID(uuid: (
                        data[0], data[1], data[2], data[3],
                        data[4], data[5], data[6], data[7],
                        data[8], data[9], data[10], data[11],
                        data[12], data[13], data[14], data[15]
                    ))
                    uuidString = uuid.uuidString
                    print("  [v7] Converting category '\(name)': binary -> \(uuidString!)")
                } else if let str = row["id"] as? String {
                    uuidString = str
                    print("  [v7] Category '\(name)': already string ✓")
                } else {
                    print("  [v7] ⚠️ Unknown format for '\(name)'")
                    uuidString = UUID().uuidString
                }

                try db.execute(
                    sql: "UPDATE categories SET id = ? WHERE name = ?",
                    arguments: [uuidString!, name]
                )
            }

            print("✅ [v7] Category conversion complete")

            // Convert vendor UUIDs
            print("🔧 [v7] Converting vendor UUIDs from binary to string format...")

            let vendorRows = try Row.fetchAll(db, sql: "SELECT * FROM vendors")
            print("📊 [v7] Found \(vendorRows.count) vendors")

            for row in vendorRows {
                let name: String = row["name"]

                // Convert id
                var idString: String?
                if let data = row["id"] as? Data, data.count == 16 {
                    let uuid = UUID(uuid: (
                        data[0], data[1], data[2], data[3],
                        data[4], data[5], data[6], data[7],
                        data[8], data[9], data[10], data[11],
                        data[12], data[13], data[14], data[15]
                    ))
                    idString = uuid.uuidString
                    print("  [v7] Converting vendor '\(name)': binary -> \(idString!)")
                } else if let str = row["id"] as? String {
                    idString = str
                    print("  [v7] Vendor '\(name)': already string ✓")
                } else {
                    print("  [v7] ⚠️ Unknown format for '\(name)'")
                    idString = UUID().uuidString
                }

                // Convert defaultCategoryId if present
                var categoryIdString: String? = nil
                if let data = row["defaultCategoryId"] as? Data, data.count == 16 {
                    let uuid = UUID(uuid: (
                        data[0], data[1], data[2], data[3],
                        data[4], data[5], data[6], data[7],
                        data[8], data[9], data[10], data[11],
                        data[12], data[13], data[14], data[15]
                    ))
                    categoryIdString = uuid.uuidString
                } else if let str = row["defaultCategoryId"] as? String {
                    categoryIdString = str
                }

                try db.execute(
                    sql: "UPDATE vendors SET id = ?, defaultCategoryId = ? WHERE name = ?",
                    arguments: [idString!, categoryIdString, name]
                )
            }

            print("✅ [v7] Vendor conversion complete")
        }

        migrator.registerMigration("v8_removed") { db in
            // Placeholder - v7 handles everything
            print("✅ [v8] Skipped (combined into v7)")
        }

        migrator.registerMigration("v9_add_app_settings") { db in
            try db.create(table: "app_settings") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }
        }

        migrator.registerMigration("v10_add_include_in_optimizations") { db in
            try db.alter(table: "spend_offers") { t in
                t.add(column: "includeInOptimizations", .boolean).notNull().defaults(to: true)
            }
        }

        migrator.registerMigration("v11_add_online_transaction_fields") { db in
            // Add onlineTransaction to transactions table
            try db.alter(table: "transactions") { t in
                t.add(column: "onlineTransaction", .boolean).notNull().defaults(to: false)
            }

            // Add defaultToOnlineTransaction to vendors table
            try db.alter(table: "vendors") { t in
                t.add(column: "defaultToOnlineTransaction", .boolean).notNull().defaults(to: false)
            }
        }

        return migrator
    }
}

// MARK: - Custom Errors

enum DatabaseError: Error, LocalizedError {
    case notInitialized
    case configurationError
    case fileAlreadyExists
    case fileNotFound
    case noPermission

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Database is not initialized"
        case .configurationError:
            return "Database configuration error"
        case .fileAlreadyExists:
            return "A database file with this name already exists"
        case .fileNotFound:
            return "Database file not found"
        case .noPermission:
            return "Cannot access this file. Due to app sandboxing, database files must be located in the app's container (Application Support folder). Please create a new database or select a file from the 'Available Databases' list."
        }
    }
}

struct DatabaseFileInfo: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let size: Int64
    let modifiedDate: Date
    let isCurrent: Bool

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}
