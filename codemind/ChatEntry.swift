import Foundation

// Represents a single question-answer pair in the chat history
struct ChatEntry: Codable, Identifiable {
    let id: UUID         // Unique identifier for the list
    let timestamp: Date  // When the entry was created (response received time)
    let question: String // The user's question
    let answer: String   // The AI's answer
    
    // Metadata
    let wordCount: Int?            // Word count of the answer
    let promptTokenCount: Int?     // Tokens in the prompt sent to API
    let candidatesTokenCount: Int? // Tokens in the response from API
    let totalTokenCount: Int?      // Total tokens used by API
    let responseTimeMs: Int?       // Total time for API to respond in ms
    let modelName: String?         // Model used for the response

    // Default initializer
    init(id: UUID = UUID(), 
         timestamp: Date = Date(), 
         question: String, 
         answer: String, 
         wordCount: Int? = nil, 
         promptTokenCount: Int? = nil, 
         candidatesTokenCount: Int? = nil, 
         totalTokenCount: Int? = nil, 
         responseTimeMs: Int? = nil, 
         modelName: String? = nil)
    {
        self.id = id
        self.timestamp = timestamp
        self.question = question
        self.answer = answer
        self.wordCount = wordCount
        self.promptTokenCount = promptTokenCount
        self.candidatesTokenCount = candidatesTokenCount
        self.totalTokenCount = totalTokenCount
        self.responseTimeMs = responseTimeMs
        self.modelName = modelName
    }
} 