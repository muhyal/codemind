import Foundation
import Combine // Needed for ObservableObject
import SwiftUI // Needed for Binding
import GoogleGenerativeAI

// MARK: - Data Structures

// Folder Structure
struct Folder: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var parentId: UUID? // nil for root level folders
    var createdAt: Date
    var colorHex: String? // Folders can also have colors
    
    // Basic initializer
    init(id: UUID = UUID(), name: String, parentId: UUID? = nil, createdAt: Date = Date(), colorHex: String? = nil) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.createdAt = createdAt
        self.colorHex = colorHex
    }
}

// Remove duplicate struct definition from here
/*
struct ChatSession: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var createdAt: Date
    var entries: [ChatEntry] = []
    var isFavorite: Bool = false
    var colorHex: String?

    init(...) { ... }
}
*/

// MARK: - Data Manager Class

// Manages multiple chat sessions and folders
class DataManager: ObservableObject {
    private let sessionsKey = "chatSessions_v1" // Use a new key if format changes
    private let foldersKey = "chatFolders_v1" // Key for saving folders

    // Array of all chat sessions, sorted by creation date (newest first)
    @Published var chatSessions: [ChatSession] = []
    @Published var folders: [Folder] = [] // Add published array for folders
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
        loadFolders() // Load folders first
        loadSessions()
        // Ensure active session is valid on init
        if let lastActiveId = UserDefaults.standard.string(forKey: "activeSessionId"),
           let uuid = UUID(uuidString: lastActiveId),
           chatSessions.contains(where: { $0.id == uuid }) {
            activeSessionId = uuid
        } else {
            // If no valid last active session, create a new one or select the first
            if chatSessions.isEmpty {
                createNewSession(activate: true)
            } else {
                activeSessionId = chatSessions.first?.id
            }
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
        
        // Create a mutable copy, modify it, and replace the original
        // This ensures SwiftUI detects the change for the struct array
        var sessionToUpdate = chatSessions[index]
        sessionToUpdate.isFavorite.toggle()
        chatSessions[index] = sessionToUpdate
        
        // Optional: Re-sort?
        // For now, just save the change.
        print("DataManager: Toggled favorite for session: \(id). New status: \(chatSessions[index].isFavorite)")
        saveSessions()
    }
    
    // Updates the title of a session
    func updateTitle(withId id: UUID, newTitle: String) {
        guard let index = chatSessions.firstIndex(where: { $0.id == id }) else { return }
        guard !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return } // Don't allow empty titles
        
        // Update using the copy-modify-replace pattern for structs
        var sessionToUpdate = chatSessions[index]
        sessionToUpdate.title = newTitle
        chatSessions[index] = sessionToUpdate

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
        
        // Update using the copy-modify-replace pattern for the session struct
        var sessionToUpdate = chatSessions[sessionIndex]
        let deletedEntry = sessionToUpdate.entries.remove(at: entryIndex) // Modify the copy
        chatSessions[sessionIndex] = sessionToUpdate // Replace the original

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
        
        // Update using the copy-modify-replace pattern
        var sessionToUpdate = chatSessions[index]
        sessionToUpdate.entries.removeAll() // Modify the copy
        chatSessions[index] = sessionToUpdate // Replace the original

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

    /// Updates the color hex string for a specific session.
    func updateSessionColor(withId id: UUID, colorHex: String?) {
        guard let index = chatSessions.firstIndex(where: { $0.id == id }) else { return }
        // Create a mutable copy of the struct
        var sessionToUpdate = chatSessions[index]
        // Update the property on the copy
        sessionToUpdate.colorHex = colorHex
        // Replace the item in the array with the updated copy
        chatSessions[index] = sessionToUpdate
        // No need for objectWillChange.send() as the array itself is modified
        saveSessions()
        print("DataManager: Updated color for session \(id) to \(colorHex ?? "None")")
    }

    // MARK: - Folder Management
    func createFolder(name: String, parentId: UUID? = nil, colorHex: String? = nil) {
        print("DataManager.createFolder called with name: '\(name)', parentId: \(parentId?.uuidString ?? "nil")") // Log entry
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { 
            print("DataManager.createFolder: Error - Folder name cannot be empty.")
            return 
        }
        
        let newFolder = Folder(name: trimmedName, parentId: parentId, colorHex: colorHex)
        print("DataManager.createFolder: Created Folder object: \(newFolder.id)")
        folders.append(newFolder)
        print("DataManager.createFolder: Appended to folders array. New count: \(folders.count)")
        saveFolders() // saveFolders already has a print statement
    }

    // ... deleteFolder, renameFolder, moveFolder, updateFolderColor ...

    // MARK: - Persistence
    private func saveFolders() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(folders)
            UserDefaults.standard.set(data, forKey: foldersKey)
            print("DataManager: Folders saved successfully.")
        } catch {
            print("DataManager Error: Failed to save folders: \(error.localizedDescription)")
        }
    }

    private func loadFolders() {
        guard let data = UserDefaults.standard.data(forKey: foldersKey) else {
            print("DataManager: No folder data found in UserDefaults.")
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            folders = try decoder.decode([Folder].self, from: data)
            // Optional: Sort folders?
            print("DataManager: Folders loaded successfully (\(folders.count) folders).")
        } catch {
            print("DataManager Error: Failed to load folders: \(error.localizedDescription)")
        }
    }

    // MARK: - Computed Properties & Helpers for UI
    
    /// Returns folders that are at the root level (no parent).
    var rootFolders: [Folder] {
        folders.filter { $0.parentId == nil }.sorted { $0.name < $1.name } // Sort alphabetically
    }
    
    /// Returns sessions that are at the root level (not in any folder).
    var rootSessions: [ChatSession] {
        chatSessions.filter { $0.folderId == nil }.sorted { $0.createdAt > $1.createdAt } // Sort by date
    }
    
    /// Returns sessions belonging to a specific folder ID.
    func sessions(in folderId: UUID) -> [ChatSession] {
        chatSessions.filter { $0.folderId == folderId }.sorted { $0.createdAt > $1.createdAt } // Keep sorted by date
    }
    
    // Add the subfolders function back
    /// Returns subfolders belonging to a specific folder ID.
    func subfolders(in parentFolderId: UUID) -> [Folder] {
        folders.filter { $0.parentId == parentFolderId }.sorted { $0.name < $1.name } // Sort alphabetically
    }
    
    /// Checks if a folder or any of its descendants contain at least one favorite session.
    func folderContainsFavorites(folderId: UUID) -> Bool {
        // Check direct sessions in the folder
        if sessions(in: folderId).contains(where: { $0.isFavorite }) {
            return true
        }
        
        // Recursively check subfolders
        for subfolder in subfolders(in: folderId) {
            if folderContainsFavorites(folderId: subfolder.id) { // Recursive call
                return true
            }
        }
        
        // No favorites found in this branch
        return false
    }

    // MARK: - Filtered Data for UI (Performance Optimization)

    @MainActor // Ensure filtering runs on the main thread for UI updates
    func filteredFolders(parentId: UUID?, currentFilter: SidebarFilter, colorHexFilter: String?) -> [Folder] {
        // Start with the correct base list of folders
        let baseFolders = parentId == nil ? rootFolders : subfolders(in: parentId!)
        
        // Apply filters sequentially
        return baseFolders.filter { folder in
            // 1. Color Filter (Apply first if present)
            if let colorFilter = colorHexFilter, folder.colorHex != colorFilter {
                return false // Exclude if color doesn't match the filter
            }
            
            // 2. Favorites Filter (Apply if .favorites is selected)
            if currentFilter == .favorites && !folderContainsFavorites(folderId: folder.id) {
                return false // Exclude if filter is .favorites and folder doesn't contain any
            }
            
            // If all checks pass, include the folder
            return true
        }
        // Note: Sorting is already handled by rootFolders/subfolders properties
    }

    @MainActor // Ensure filtering runs on the main thread for UI updates
    func filteredSessions(parentId: UUID?, currentFilter: SidebarFilter, colorHexFilter: String?) -> [ChatSession] {
        // Start with the correct base list of sessions
        let baseSessions = parentId == nil ? rootSessions : sessions(in: parentId!)
        
        // Apply filters sequentially
        return baseSessions.filter { session in
            // 1. Color Filter (Apply first if present)
            if let colorFilter = colorHexFilter, session.colorHex != colorFilter {
                return false // Exclude if color doesn't match the filter
            }
            
            // 2. Favorites Filter (Apply if .favorites is selected)
            if currentFilter == .favorites && !session.isFavorite {
                return false // Exclude if filter is .favorites and session is not a favorite
            }
            
            // If all checks pass, include the session
            return true
        }
        // Note: Sorting is already handled by rootSessions/sessions(in:) methods
    }

    /// Checks if a folder (`folderId`) is a descendant of another folder (`ancestorId`).
    func isDescendant(folderId: UUID, of ancestorId: UUID) -> Bool {
        guard let folder = folders.first(where: { $0.id == folderId }), let parentId = folder.parentId else {
            // If the folder doesn't exist or has no parent, it cannot be a descendant
            return false
        }
        
        // If the direct parent is the ancestor, it's a descendant
        if parentId == ancestorId {
            return true
        }
        
        // Recursively check the parent
        return isDescendant(folderId: parentId, of: ancestorId)
    }

    // MARK: - Folder Management - NEW METHODS ADDED

    /// Renames an existing folder.
    func renameFolder(withId id: UUID, newName: String) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        folders[index].name = newName
        saveFolders()
        print("DataManager: Renamed folder \(id) to '\(newName)'")
    }

    /// Deletes a folder and optionally its contents.
    func deleteFolder(withId id: UUID, recursive: Bool) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        
        let deletedFolder = folders.remove(at: index)
        print("DataManager: Deleted folder '\(deletedFolder.name)' (ID: \(id))")
        
        // Find all direct child sessions and folders
        let childSessionIds = chatSessions.filter { $0.folderId == id }.map { $0.id }
        let childFolderIds = folders.filter { $0.parentId == id }.map { $0.id } // Re-check folders after removal? No, use the original list.

        if recursive {
            print("DataManager: Recursively deleting contents of folder \(id)")
            // Recursively delete child folders
            for childFolderId in childFolderIds {
                deleteFolder(withId: childFolderId, recursive: true) // Call recursively
            }
            // Delete child sessions
            for childSessionId in childSessionIds {
                deleteSession(withId: childSessionId) // Assume deleteSession saves itself
            }
        } else {
            print("DataManager: Moving contents of folder \(id) to root")
            // Move child folders to root
            for childFolderId in childFolderIds {
                moveFolder(folderId: childFolderId, newParentId: nil) // Assume moveFolder saves itself
            }
            // Move child sessions to root
            for childSessionId in childSessionIds {
                moveSessionToFolder(sessionId: childSessionId, newParentId: nil) // Assume moveSessionToFolder saves itself
            }
        }
        
        saveFolders() // Save folder list changes
        // Note: Child operations should handle their own saves
    }

    /// Moves a session to a different folder (or root if newParentId is nil).
    func moveSessionToFolder(sessionId: UUID, newParentId: UUID?) {
        guard let sessionIndex = chatSessions.firstIndex(where: { $0.id == sessionId }) else { return }
        // Allow moving to root (nil) or an existing folder
        if newParentId != nil && !folders.contains(where: { $0.id == newParentId }) {
            print("DataManager Error: Target folder ID \(newParentId!) not found.")
            return
        }
        chatSessions[sessionIndex].folderId = newParentId
        saveSessions()
        print("DataManager: Moved session \(sessionId) to folder \(newParentId?.uuidString ?? "Root")")
    }
    
    /// Moves a folder (and its contents implicitly) to a different parent folder (or root).
    func moveFolder(folderId: UUID, newParentId: UUID?) {
        guard let folderIndex = folders.firstIndex(where: { $0.id == folderId }) else { return }
        // Prevent moving a folder into itself or one of its own descendants (basic check)
        if folderId == newParentId { return } 
        // TODO: Add check for descendant move?
        
        // Allow moving to root (nil) or an existing folder
        if newParentId != nil && !folders.contains(where: { $0.id == newParentId }) {
            print("DataManager Error: Target parent folder ID \(newParentId!) not found.")
            return
        }
        folders[folderIndex].parentId = newParentId
        saveFolders()
        print("DataManager: Moved folder \(folderId) to parent \(newParentId?.uuidString ?? "Root")")
    }

    /// Updates the color hex string for a specific folder.
    func updateFolderColor(withId id: UUID, colorHex: String?) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        // Create a mutable copy of the struct
        var folderToUpdate = folders[index]
        // Update the property on the copy
        folderToUpdate.colorHex = colorHex
        // Replace the item in the array with the updated copy
        folders[index] = folderToUpdate
        // No need for objectWillChange.send() as the array itself is modified
        saveFolders()
        print("DataManager: Updated color for folder \(id) to \(colorHex ?? "None")")
    }
}

// Remove duplicate struct definitions from here
/*
struct ChatEntry: Identifiable, Codable, Equatable {
    // ... ChatEntry definition ...
}

struct GenerationResult { 
    // ... GenerationResult definition ...
}
*/ 