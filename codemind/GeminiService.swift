import Foundation
import GoogleGenerativeAI

// Define potential errors for the Gemini service
enum GeminiError: Error, LocalizedError {
    case apiKeyMissing
    case modelInitializationFailed(Error)
    case contentGenerationFailed(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "API Key is missing. Please add it in settings."
        case .modelInitializationFailed(let underlyingError):
            return "Failed to initialize the AI model: \(underlyingError.localizedDescription)"
        case .contentGenerationFailed(let underlyingError):
            return "Failed to generate content: \(underlyingError.localizedDescription)"
        case .invalidResponse:
            return "Received an invalid response from the API."
        }
    }
}

// Define a struct to hold the generation result including metadata
struct GenerationResult {
    let text: String
    let wordCount: Int
    let promptTokenCount: Int?
    let candidatesTokenCount: Int?
    let totalTokenCount: Int?
    let responseTimeMs: Int
    let modelName: String
}

struct GeminiService {
    
    private let modelName = "gemini-2.0-flash" // Keep model name consistent

    // Function to generate response from Gemini API
    // Takes the conversation history and the latest prompt as input
    // Returns a Result type: either the GenerationResult or an error (GeminiError)
    func generateResponse(history: [ModelContent], latestPrompt: String, apiKey: String) async -> Result<GenerationResult, GeminiError> {
        // Ensure the API key is not empty
        guard !apiKey.isEmpty else {
            return .failure(.apiKeyMissing)
        }

        // Initialize the GenerativeModel with the API key
        let model = GenerativeModel(name: self.modelName, apiKey: apiKey)
        
        // Start a chat session with the provided history
        let chat = model.startChat(history: history)
        
        let startTime = Date()

        do {
            // Send the latest prompt to the ongoing chat session
            let response = try await chat.sendMessage(latestPrompt)
            
            let endTime = Date()
            let responseTimeMs = Int(endTime.timeIntervalSince(startTime) * 1000)

            // Extract the text from the response
            guard let text = response.text else {
                return .failure(.invalidResponse)
            }
            
            // Calculate word count
            let wordCount = text.split { $0.isWhitespace || $0.isNewline }.count
            
            // Extract token counts (assuming response.usageMetadata exists)
            // Note: For chat history, token counts might reflect the whole session up to this point
            let promptTokenCount = response.usageMetadata?.promptTokenCount
            let candidatesTokenCount = response.usageMetadata?.candidatesTokenCount
            let totalTokenCount = response.usageMetadata?.totalTokenCount

            // Create the result struct
            let result = GenerationResult(
                text: text, 
                wordCount: wordCount, 
                promptTokenCount: promptTokenCount,
                candidatesTokenCount: candidatesTokenCount,
                totalTokenCount: totalTokenCount,
                responseTimeMs: responseTimeMs,
                modelName: self.modelName
            )
            
            return .success(result)
            
        } catch {
            // Handle errors during API communication
            print("Gemini API Error: \(error)") // Log the specific error
            return .failure(.contentGenerationFailed(error))
        }
    }
} 