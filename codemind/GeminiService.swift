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

struct GeminiService {

    // Function to generate response from Gemini API
    // Takes the user prompt and API key as input
    // Returns a Result type: either the generated text (String) or an error (GeminiError)
    func generateResponse(prompt: String, apiKey: String) async -> Result<String, GeminiError> {
        // Ensure the API key is not empty
        guard !apiKey.isEmpty else {
            return .failure(.apiKeyMissing)
        }

        // Initialize the GenerativeModel with the API key
        // Note: Error handling during initialization might be needed based on the SDK's behavior
        let model = GenerativeModel(name: "gemini-1.5-flash", apiKey: apiKey)

        do {
            // Send the prompt to the Gemini API
            let response = try await model.generateContent(prompt)

            // Extract the text from the response
            // Handle potential nil or empty text
            if let text = response.text {
                return .success(text)
            } else {
                return .failure(.invalidResponse) // Or a more specific error
            }
        } catch {
            // Handle errors during API communication
            print("Gemini API Error: \(error)") // Log the specific error
            return .failure(.contentGenerationFailed(error))
        }
    }
} 