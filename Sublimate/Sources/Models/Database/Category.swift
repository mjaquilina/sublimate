import Foundation
import GRDB

/// Represents a merchant category for classification
struct Category: Codable, Identifiable, FetchableRecord, PersistableRecord, Hashable {
    var id: UUID
    var name: String
    var icon: String?  // SF Symbol name
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         name: String,
         icon: String? = nil,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.icon = icon
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // GRDB mapping
    static let databaseTableName = "categories"

    enum CodingKeys: String, CodingKey {
        case id, name, icon, createdAt, updatedAt
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let icon = Column(CodingKeys.icon)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        // Auto-update timestamps handled in migration
    }

    // Custom encoding to ensure UUID is stored as string, not binary
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString, forKey: .id)  // Encode as string
        try container.encode(name, forKey: .name)
        try container.encode(icon, forKey: .icon)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    // Custom decoding to handle both string and binary UUID formats
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try to decode ID as string first, then fall back to UUID
        if let idString = try? container.decode(String.self, forKey: .id) {
            guard let uuid = UUID(uuidString: idString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .id,
                    in: container,
                    debugDescription: "Invalid UUID string: \(idString)"
                )
            }
            self.id = uuid
        } else {
            self.id = try container.decode(UUID.self, forKey: .id)
        }

        self.name = try container.decode(String.self, forKey: .name)
        self.icon = try container.decodeIfPresent(String.self, forKey: .icon)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
