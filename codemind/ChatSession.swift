import Foundation

// Represents a single chat session, containing multiple entries
struct ChatSession: Identifiable, Codable, Equatable {
    var id: UUID                // Unique identifier for the session
    var title: String           // Title of the chat (e.g., first user question)
    var createdAt: Date         // When the session was started
    var entries: [ChatEntry]    // The actual question-answer pairs in this session
    var isFavorite: Bool = false // Favorite status
    var colorHex: String?       // Add colorHex property
    var folderId: UUID?         // Add folderId property

    // CodingKeys for manual Codable conformance
    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, entries, isFavorite, colorHex, folderId
    }

    // Initializer
    init(id: UUID = UUID(), title: String? = nil, createdAt: Date = Date(), entries: [ChatEntry] = [], isFavorite: Bool = false, colorHex: String? = nil, folderId: UUID? = nil) {
        self.id = id
        // If no title is provided, use a placeholder or generate later
        self.title = title ?? "Chat \(DateFormatter.shortDateTime.string(from: createdAt))"
        self.createdAt = createdAt
        self.entries = entries
        self.isFavorite = isFavorite
        self.colorHex = colorHex
        self.folderId = folderId
    }

    // Manual Decodable initializer to handle optional colorHex and folderId
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        entries = try container.decode([ChatEntry].self, forKey: .entries)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false // Handle potential missing value for older data
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) // Decode optional colorHex
        folderId = try container.decodeIfPresent(UUID.self, forKey: .folderId) // Decode optional folderId
    }

    // Manual Encodable function (optional, but good practice if custom init exists)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(entries, forKey: .entries)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encodeIfPresent(colorHex, forKey: .colorHex) // Encode optional colorHex
        try container.encodeIfPresent(folderId, forKey: .folderId) // Encode optional folderId
    }

    // Helper to get a short preview of the first question for the title
    static func generateTitle(from text: String, maxLength: Int = 50) -> String {
        let firstLine = text.split(separator: "\n").first ?? Substring(text)
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maxLength))
    }

    // Explicitly conform to Equatable by comparing IDs
    static func == (lhs: ChatSession, rhs: ChatSession) -> Bool {
        lhs.id == rhs.id
    }
}

// Helper extension for DateFormatter
extension DateFormatter {
    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
} 