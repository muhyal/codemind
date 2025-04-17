import Foundation

// Represents a single chat session, containing multiple entries
struct ChatSession: Codable, Identifiable, Equatable {
    let id: UUID                // Unique identifier for the session
    var title: String           // Title of the chat (e.g., first user question)
    let createdAt: Date         // When the session was started
    var entries: [ChatEntry]    // The actual question-answer pairs in this session

    // Initializer
    init(id: UUID = UUID(), title: String? = nil, createdAt: Date = Date(), entries: [ChatEntry] = []) {
        self.id = id
        // If no title is provided, use a placeholder or generate later
        self.title = title ?? "New Chat \(DateFormatter.shortDateTime.string(from: createdAt))"
        self.createdAt = createdAt
        self.entries = entries
    }

    // Helper to get a short preview of the first question for the title
    static func generateTitle(from question: String) -> String {
        let maxLength = 30
        if question.count <= maxLength {
            return question
        } else {
            return String(question.prefix(maxLength)) + "..."
        }
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