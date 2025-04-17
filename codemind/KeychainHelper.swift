import Foundation
import Security

// Helper struct for managing secrets in the Keychain
struct KeychainHelper {

    // Define a unique service name for your app's Keychain items
    private static let service = "com.kutbu.codemind.APIKeyService" // Updated service name for CodeMind
    // Define a key to identify the API key within the service
    private static let account = "geminiAPIKey"

    // Saves the API key to the Keychain
    // Returns true if successful, false otherwise
    static func saveAPIKey(_ apiKey: String) -> Bool {
        // Convert the API key string to Data
        guard let data = apiKey.data(using: .utf8) else {
            print("Keychain Error: Could not encode API key to Data.")
            return false
        }

        // Prepare the query dictionary for saving/updating
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // kSecAttrAccessible defines when the item should be readable.
            // .afterFirstUnlock is a common choice, accessible after device is unlocked once.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        // Delete any existing item for this service/account before saving the new one
        SecItemDelete(query as CFDictionary)

        // Add the new item to the Keychain
        let status = SecItemAdd(query as CFDictionary, nil)

        // Check the result
        if status == errSecSuccess {
            print("API Key saved successfully to Keychain.")
            return true
        } else {
            print("Keychain Error: Failed to save API key. Status: \(status) - \(secErrorDescription(status) ?? "Unknown error")")
            return false
        }
    }

    // Loads the API key from the Keychain
    // Returns the API key string if found, nil otherwise
    static func loadAPIKey() -> String? {
        // Prepare the query dictionary for searching
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne // We only expect one match
        ]

        var dataTypeRef: AnyObject? // Variable to hold the retrieved data

        // Search for the item in the Keychain
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess {
            // Item found, try to convert the data back to a String
            guard let retrievedData = dataTypeRef as? Data,
                  let apiKey = String(data: retrievedData, encoding: .utf8) else {
                print("Keychain Error: Could not decode retrieved data to String.")
                return nil
            }
            print("API Key loaded successfully from Keychain.")
            return apiKey
        } else if status == errSecItemNotFound {
            // Item not found is not necessarily an error in this context
            print("Keychain Info: API Key not found in Keychain.")
            return nil
        } else {
            // Another error occurred during retrieval
            print("Keychain Error: Failed to load API key. Status: \(status) - \(secErrorDescription(status) ?? "Unknown error")")
            return nil
        }
    }

    // Helper to get a human-readable description of a SecItem status code
    private static func secErrorDescription(_ status: OSStatus) -> String? {
        return SecCopyErrorMessageString(status, nil) as String?
    }
} 