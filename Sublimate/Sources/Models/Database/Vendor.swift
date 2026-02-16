import Foundation
import GRDB

struct Vendor: Codable, Identifiable, FetchableRecord, PersistableRecord, Hashable {
    static let databaseTableName = "vendors"

    var id: UUID
    var name: String
    var displayName: String  // User-friendly name
    var defaultCategoryId: UUID?  // Optional default category
    var defaultToOnlineTransaction: Bool
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, displayName, defaultCategoryId, defaultToOnlineTransaction, createdAt, updatedAt
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let displayName = Column(CodingKeys.displayName)
        static let defaultCategoryId = Column(CodingKeys.defaultCategoryId)
        static let defaultToOnlineTransaction = Column(CodingKeys.defaultToOnlineTransaction)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    init(id: UUID = UUID(), name: String, displayName: String, defaultCategoryId: UUID? = nil, defaultToOnlineTransaction: Bool = false, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.defaultCategoryId = defaultCategoryId
        self.defaultToOnlineTransaction = defaultToOnlineTransaction
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Custom encoding to ensure UUIDs are stored as strings
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(defaultCategoryId?.uuidString, forKey: .defaultCategoryId)
        try container.encode(defaultToOnlineTransaction, forKey: .defaultToOnlineTransaction)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    // Custom decoding to handle both string and binary UUID formats
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode id
        if let idString = try? container.decode(String.self, forKey: .id) {
            guard let uuid = UUID(uuidString: idString) else {
                throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Invalid UUID string")
            }
            self.id = uuid
        } else {
            self.id = try container.decode(UUID.self, forKey: .id)
        }

        self.name = try container.decode(String.self, forKey: .name)
        self.displayName = try container.decode(String.self, forKey: .displayName)

        // Decode defaultCategoryId
        if let catIdString = try? container.decodeIfPresent(String.self, forKey: .defaultCategoryId) {
            self.defaultCategoryId = UUID(uuidString: catIdString)
        } else {
            self.defaultCategoryId = try container.decodeIfPresent(UUID.self, forKey: .defaultCategoryId)
        }

        self.defaultToOnlineTransaction = try container.decodeIfPresent(Bool.self, forKey: .defaultToOnlineTransaction) ?? false

        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
