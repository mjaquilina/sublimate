import Foundation
import GRDB

/// Stores learned mappings from vendor names to categories and display names
struct VendorMapping: Codable, Identifiable {
    var id: UUID
    var rawVendorName: String
    var normalizedVendorName: String
    var displayName: String
    var category: String?
    var useCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), rawVendorName: String, normalizedVendorName: String, displayName: String,
         category: String? = nil, useCount: Int = 1, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.rawVendorName = rawVendorName
        self.normalizedVendorName = normalizedVendorName
        self.displayName = displayName
        self.category = category
        self.useCount = useCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB Persistence
extension VendorMapping: FetchableRecord, PersistableRecord {
    static let databaseTableName = "vendor_mappings"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let rawVendorName = Column(CodingKeys.rawVendorName)
        static let normalizedVendorName = Column(CodingKeys.normalizedVendorName)
        static let displayName = Column(CodingKeys.displayName)
        static let category = Column(CodingKeys.category)
        static let useCount = Column(CodingKeys.useCount)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    mutating func willUpdate(_ db: Database, column: String) throws {
        updatedAt = Date()
    }
}

// MARK: - Query Methods
extension VendorMapping {
    static func normalize(_ vendorName: String) -> String {
        vendorName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func findMapping(_ db: Database, vendorName: String) throws -> VendorMapping? {
        let normalized = normalize(vendorName)

        // Try exact match first
        if let exact = try VendorMapping
            .filter(Columns.normalizedVendorName == normalized)
            .fetchOne(db) {
            return exact
        }

        // Try substring match
        let all = try VendorMapping.fetchAll(db)
        for mapping in all {
            if normalized.contains(mapping.normalizedVendorName) ||
               mapping.normalizedVendorName.contains(normalized) {
                return mapping
            }
        }

        return nil
    }

    static func createOrUpdate(_ db: Database, rawName: String, displayName: String, category: String?) throws -> VendorMapping {
        let normalized = normalize(rawName)

        if var existing = try findMapping(db, vendorName: rawName) {
            existing.useCount += 1
            existing.updatedAt = Date()
            // Update display name and category if provided
            if !displayName.isEmpty {
                existing.displayName = displayName
            }
            if let category = category {
                existing.category = category
            }
            try existing.update(db)
            return existing
        } else {
            var newMapping = VendorMapping(
                rawVendorName: rawName,
                normalizedVendorName: normalized,
                displayName: displayName.isEmpty ? rawName : displayName,
                category: category
            )
            try newMapping.insert(db)
            return newMapping
        }
    }

    mutating func incrementUseCount(_ db: Database) throws {
        useCount += 1
        updatedAt = Date()
        try update(db)
    }
}
