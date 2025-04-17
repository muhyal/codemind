import Foundation
import Combine // Needed for ObservableObject
import SwiftUI // Needed for Binding

// Manages multiple chat sessions
class DataManager: ObservableObject {
    private let sessionsKey = "chatSessions_v1" // Use a new key if format changes

    // Array of all chat sessions, sorted by creation date (newest first)
    @Published var chatSessions: [ChatSession] = []
    // ID of the currently selected/active session
    @Published var activeSessionId: UUID? = nil

    // Computed property to get the index of the active session
    private var activeSessionIndex: Int? {
        chatSessions.firstIndex { $0.id == activeSessionId }
    }

    // Computed property to get the entries of the currently active session
    var activeSessionEntries: [ChatEntry] {
        guard let index = activeSessionIndex else { return [] }
        return chatSessions[index].entries
    }

    init() {
        loadSessions()
        // If no sessions were loaded, create an initial one
        if chatSessions.isEmpty {
            print("DataManager: No sessions found, creating initial session.")
            createNewSession(activate: true)
        } else {
            // If sessions exist but no active ID is set (e.g., first load after update),
            // activate the most recent one.
            if activeSessionId == nil {
                print("DataManager: Activating the most recent session.")
                activeSessionId = chatSessions.first?.id
            }
            print("DataManager: Initialized with \(chatSessions.count) sessions. Active ID: \(activeSessionId?.uuidString ?? "None")")
        }
    }

    // Creates a new, empty chat session
    func createNewSession(activate: Bool = true) {
        let newSession = ChatSession()
        chatSessions.insert(newSession, at: 0) // Add to the beginning (newest)
        if activate {
            activeSessionId = newSession.id
            print("DataManager: Created and activated new session: \(newSession.id)")
        }
        saveSessions() // Save after creating
    }

    // Adds a new entry (question/answer/metadata) to the currently active session
    func addEntryToActiveSession(question: String, generationResult: GenerationResult) {
        guard let index = activeSessionIndex else {
            print("DataManager Error: Cannot add entry, no active session selected.")
            return
        }

        let newEntry = ChatEntry(
            question: question, 
            answer: generationResult.text, 
            wordCount: generationResult.wordCount,
            promptTokenCount: generationResult.promptTokenCount,
            candidatesTokenCount: generationResult.candidatesTokenCount,
            totalTokenCount: generationResult.totalTokenCount,
            responseTimeMs: generationResult.responseTimeMs,
            modelName: generationResult.modelName
            // timestamp will default to Date()
        )
        
        chatSessions[index].entries.append(newEntry)

        // Update session title if it's the first entry and using default title
        if chatSessions[index].entries.count == 1 && chatSessions[index].title.starts(with: "New Chat") {
            chatSessions[index].title = ChatSession.generateTitle(from: question)
            print("DataManager: Updated title for session \(chatSessions[index].id) to: \(chatSessions[index].title)")
        }

        saveSessions() // Save after adding entry
        print("DataManager: Added entry to session: \(activeSessionId?.uuidString ?? "None")")
    }

    // Deletes a session by its ID
    func deleteSession(withId id: UUID) {
        guard let index = chatSessions.firstIndex(where: { $0.id == id }) else { return }
        let deletedSession = chatSessions.remove(at: index)
        print("DataManager: Deleted session: \(deletedSession.id) - \(deletedSession.title)")

        // If the deleted session was the active one, select another one (e.g., the new first one)
        if activeSessionId == id {
            activeSessionId = chatSessions.first?.id
            print("DataManager: Active session deleted. New active session: \(activeSessionId?.uuidString ?? "None")")
        }
        saveSessions()
    }

    // Toggles the favorite status of a session
    func toggleFavorite(withId id: UUID) {
        guard let index = chatSessions.firstIndex(where: { $0.id == id }) else { return }
        
        // Manually signal that the object is about to change
        objectWillChange.send()
        
        chatSessions[index].isFavorite.toggle()
        // Optional: Re-sort sessions to keep favorites grouped or at the top?
        // For now, just save the change.
        print("DataManager: Toggled favorite for session: \(id). New status: \(chatSessions[index].isFavorite)")
        saveSessions()
    }
    
    // Updates the title of a session
    func updateTitle(withId id: UUID, newTitle: String) {
        guard let index = chatSessions.firstIndex(where: { $0.id == id }) else { return }
        guard !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return } // Don't allow empty titles
        
        // Manually signal that the object is about to change
        objectWillChange.send()
        
        chatSessions[index].title = newTitle
        print("DataManager: Updated title for session: \(id) to '\(newTitle)'")
        saveSessions()
    }

    // Deletes a specific entry from the active session
    func deleteEntry(entryId: UUID) {
        guard let sessionIndex = activeSessionIndex else {
            print("DataManager Error: Cannot delete entry, no active session selected.")
            return
        }
        
        guard let entryIndex = chatSessions[sessionIndex].entries.firstIndex(where: { $0.id == entryId }) else {
             print("DataManager Error: Cannot find entry with ID \(entryId) in session \(activeSessionId?.uuidString ?? "None")")
             return
        }
        
        // Manually signal that the object is about to change
        objectWillChange.send()
        
        let deletedEntry = chatSessions[sessionIndex].entries.remove(at: entryIndex)
        print("DataManager: Deleted entry \(deletedEntry.id) from session \(activeSessionId?.uuidString ?? "None")")
        
        // Save changes
        saveSessions()
    }

    // Clears all entries from a specific session
    func clearEntries(sessionId: UUID) {
        guard let index = chatSessions.firstIndex(where: { $0.id == sessionId }) else {
            print("DataManager Error: Cannot clear entries, session ID \(sessionId) not found.")
            return
        }
        
        // Check if there are actually entries to clear
        guard !chatSessions[index].entries.isEmpty else {
            print("DataManager: No entries to clear in session \(sessionId).")
            return
        }
        
        // Manually signal change before modifying the struct's array
        objectWillChange.send()
        
        chatSessions[index].entries.removeAll()
        print("DataManager: Cleared all entries for session \(sessionId).")
        
        // Save changes
        saveSessions()
    }

    // Saves the current sessions array to UserDefaults
    private func saveSessions() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(chatSessions)
            UserDefaults.standard.set(data, forKey: sessionsKey)
            print("DataManager: Sessions saved successfully.")
        } catch {
            print("DataManager Error: Failed to save sessions: \(error.localizedDescription)")
        }
    }

    // Loads sessions from UserDefaults
    private func loadSessions() {
        guard let data = UserDefaults.standard.data(forKey: sessionsKey) else {
            print("DataManager: No session data found in UserDefaults.")
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            chatSessions = try decoder.decode([ChatSession].self, from: data)
            // Ensure sessions are sorted by date, newest first, upon loading
            chatSessions.sort { $0.createdAt > $1.createdAt }
            print("DataManager: Sessions loaded successfully (\(chatSessions.count) sessions).")
        } catch {
            print("DataManager Error: Failed to load sessions: \(error.localizedDescription)")
            // Consider clearing invalid data
            // UserDefaults.standard.removeObject(forKey: sessionsKey)
            // chatSessions = []
        }
    }

    // Optional: Provides a binding to the active session's entries
    // This might be useful in the View, though accessing activeSessionEntries might be enough
    //    func activeSessionEntriesBinding() -> Binding<[ChatEntry]> {
    //        Binding<[ChatEntry]>(\n
    //            get: { self.activeSessionEntries },\n
    //            set: { newEntries in\n
    //                guard let index = self.activeSessionIndex else { return }\n
    //                self.chatSessions[index].entries = newEntries\n
    //                // Optionally trigger save here if needed, though addEntryToActiveSession handles it\n
    //            }\n
    //        )\n
    //    }
} 