import Foundation

// Represents a single question-answer pair in the chat history
struct ChatEntry: Codable, Identifiable {
    let id: UUID         // Unique identifier for the list
    let timestamp: Date  // When the entry was created
    let question: String // The user's question
    let answer: String   // The AI's answer

    // Default initializer
    init(id: UUID = UUID(), timestamp: Date = Date(), question: String, answer: String) {
        self.id = id
        self.timestamp = timestamp
        self.question = question
        self.answer = answer
    }
} 