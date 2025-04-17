import SwiftUI

struct SettingsView: View {
    // Environment variable to dismiss the view
    @Environment(\.dismiss) var dismiss

    // State variable to hold the API key entered by the user
    @State private var apiKeyInput: String = ""
    // State variable to show feedback to the user (e.g., "Saved!")
    @State private var feedbackMessage: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Gemini API Key")
                .font(.headline)

            // Use SecureField for better security, but TextField is easier for debugging
            // If distributing, strongly consider SecureField
            TextField("Enter your API Key", text: $apiKeyInput)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onAppear {
                    // Load the existing key when the view appears
                    apiKeyInput = KeychainHelper.loadAPIKey() ?? ""
                }

            HStack {
                Button("Save & Close") { // Changed button label
                    saveApiKeyAndDismiss()
                }
                .disabled(apiKeyInput.isEmpty) // Disable if input is empty

                Spacer() // Push feedback message to the right

                Text(feedbackMessage)
                    .font(.caption)
                    .foregroundColor(feedbackMessage.starts(with: "Error") ? .red : .green) // Show error in red
            }

            Text("You can get your API key from Google AI Studio.")
                .font(.footnote)
                .foregroundColor(.secondary)

            Spacer() // Pushes content to the top
        }
        .padding()
        .frame(width: 350, height: 150) // Set a fixed size for the settings window
    }

    // Function to save the API key using KeychainHelper and then dismiss the view
    private func saveApiKeyAndDismiss() {
        if KeychainHelper.saveAPIKey(apiKeyInput) {
            feedbackMessage = "API Key Saved!"
            // Dismiss the sheet after a short delay to allow user to see the message
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                dismiss()
            }
        } else {
            feedbackMessage = "Error Saving Key" // Or provide more specific error
            // Consider showing an alert for errors
            // Don't dismiss on error
        }
    }
}

// Preview Provider
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
} 