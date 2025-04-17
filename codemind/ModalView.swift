import SwiftUI
import GoogleGenerativeAI
import MarkdownUI

// MARK: - Main View
struct ModalView: View {
    @StateObject private var dataManager = DataManager()
    @State private var showingEditAlert: Bool = false
    @State private var sessionToEdit: ChatSession? = nil
    @State private var newSessionTitle: String = ""
    @State private var selectedFilter: SidebarFilter = .all
    @State private var searchText: String = ""
    @State private var showingClearConfirm: Bool = false
    @State private var showingDeleteConfirm: Bool = false
    @State private var showingSummarySheet: Bool = false
    @State private var chatSummary: String = ""
    @State private var statusText: String = ""
    
    // Centralized definitions
    var userBubbleGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.4)]),
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
    var aiBubbleGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [Color.purple.opacity(0.2), Color.teal.opacity(0.3)]),
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
    var aiRawBackground: Color {
         colorScheme == .dark ? Color.gray.opacity(0.1) : Color.gray.opacity(0.05)
    }
    var userGlowColor: Color = .blue.opacity(0.5)
    var aiGlowColor: Color = .purple.opacity(0.5)
    
    // Move geminiService back to ModalView
    private let geminiService = GeminiService()

    // Environment
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedFilter: $selectedFilter,
                showingEditAlert: $showingEditAlert,
                sessionToEdit: $sessionToEdit,
                newSessionTitle: $newSessionTitle
            )
        } detail: {
             ChatDetailView(
                 searchText: $searchText,
                 statusText: $statusText,
                 userBubbleGradient: userBubbleGradient,
                 aiBubbleGradient: aiBubbleGradient,
                 aiRawBackground: aiRawBackground,
                 userGlowColor: userGlowColor,
                 aiGlowColor: aiGlowColor,
                 geminiService: self.geminiService
             )
        }
        .environmentObject(dataManager)
        .background(.ultraThinMaterial)
        .frame(minWidth: 700, minHeight: 500)
        .alert("Edit Chat Title", isPresented: $showingEditAlert, presenting: sessionToEdit) { session in
             TextField("Enter new title", text: $newSessionTitle)
             Button("Save") {
                 if let id = sessionToEdit?.id, !newSessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                     Task { // Wrap in Task
                         await MainActor.run { dataManager.updateTitle(withId: id, newTitle: newSessionTitle) }
                         // Reset state after saving (needs to be on MainActor if updating UI-bound state)
                         await MainActor.run {
                             sessionToEdit = nil
                             newSessionTitle = ""
                         }
                         // showingEditAlert will be set to false automatically by isPresented binding
                     }
                 }
             }
             Button("Cancel", role: .cancel) { 
                  // Reset state on cancel (can likely stay synchronous)
                  sessionToEdit = nil 
                  newSessionTitle = ""
             }
        } message: { session in 
             Text("Enter a new title for the chat session.")
        }
        // Confirmation Dialogs
        .confirmationDialog("Clear all messages...", isPresented: $showingClearConfirm) { 
             Button("Clear Messages", role: .destructive) {
                 if let sessionId = dataManager.activeSessionId {
                     Task { // Wrap in Task
                         await MainActor.run { dataManager.clearEntries(sessionId: sessionId) }
                     }
                 }
             }
             Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this entire chat session...", isPresented: $showingDeleteConfirm) { 
            Button("Delete Session", role: .destructive) {
                if let sessionId = dataManager.activeSessionId {
                    Task { // Wrap in Task
                         await MainActor.run { dataManager.deleteSession(withId: sessionId) }
                    }
                }
            }
            Button("Cancel", role: .cancel) {} 
        }
        // Summary Sheet
        .sheet(isPresented: $showingSummarySheet) {
            SummaryView(summary: chatSummary)
        }
        // Move Toolbar back to ModalView
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Spacer()
                Menu {
                    Button { copyChatToPasteboard() } label: { Label("Export Chat (Copy)", systemImage: "doc.text") }
                    Button(role: .destructive) { showingClearConfirm = true } label: { Label("Clear All Messages", systemImage: "clear") }
                    Button(role: .destructive) { showingDeleteConfirm = true } label: { Label("Delete Current Session", systemImage: "trash") }
                    Button { Task { await generateSummary() } } label: { Label("Summarize Chat", systemImage: "doc.text.magnifyingglass") }
                } label: { Label("More Actions", systemImage: "ellipsis.circle") }
                .menuIndicator(.hidden)
            }
        }
    }
    
    // MARK: - Helper Functions
    @MainActor private func generateSummary() async {
        guard dataManager.activeSessionId != nil else {
            chatSummary = "Error: No active chat session to summarize."
            return
        }
        guard let apiKey = KeychainHelper.loadAPIKey(), !apiKey.isEmpty else {
            chatSummary = "Error: API Key is missing."
            return
        }
        
        chatSummary = "Generating summary..." // Reset summary state
        showingSummarySheet = true // Show sheet immediately with loading text
        
        // Format the entire chat history for the summarization prompt
        let historyToSummarize = dataManager.activeSessionEntries.map { entry -> String in
            let userTurn = entry.question.isEmpty ? "" : "User: \(entry.question)"
            let modelTurn = entry.answer.isEmpty ? "" : "AI: \(entry.answer)"
            return "\(userTurn)\n\(modelTurn)".trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        
        let summarizationPrompt = "Please provide a concise summary of the key points from the following conversation:\n\n---\n\(historyToSummarize)\n---"

        // Call the service with an empty history for a single-turn request
        let result = await geminiService.generateResponse(history: [], latestPromptParts: [.text(summarizationPrompt)], apiKey: apiKey)
        
        statusText = ""
        
        switch result {
        case .success(let generationResult):
            chatSummary = generationResult.text // Update summary with the result
        case .failure(let error):
            chatSummary = "Error generating summary: \n\(error.localizedDescription)"
            // Keep the sheet open to show the error
        }
    }
    private func copyChatToPasteboard() {
        guard let activeSessionID = dataManager.activeSessionId else { return }
        
        // Recreate filtering logic based on DataManager and searchText
        // Use the same stable ID generation and sorting as ChatDetailView
        let messagesToCopy = dataManager.activeSessionEntries.flatMap { entry -> [DisplayMessage] in
             var messages: [DisplayMessage] = []
             if !entry.question.isEmpty { messages.append(DisplayMessage(
                 id: "\\(entry.id.uuidString)-user", // Stable String ID
                 entryId: entry.id,
                 role: .user,
                 content: entry.question,
                 timestamp: entry.timestamp,
                 metadata: nil
             )) }
             if !entry.answer.isEmpty { messages.append(DisplayMessage(
                 id: "\\(entry.id.uuidString)-model", // Stable String ID
                 entryId: entry.id,
                 role: .model,
                 content: entry.answer,
                 // Use the same timestamp logic if needed for strict ordering within entry
                 timestamp: entry.timestamp.addingTimeInterval(0.001), 
                 metadata: ChatEntryMetadata(
                     wordCount: entry.wordCount,
                     promptTokenCount: entry.promptTokenCount,
                     candidatesTokenCount: entry.candidatesTokenCount,
                     totalTokenCount: entry.totalTokenCount,
                     responseTimeMs: entry.responseTimeMs,
                     modelName: entry.modelName
                 )
             )) }
             return messages
        }
        .sorted { $0.timestamp < $1.timestamp } // Ensure sorted by time
        .filter { message in // Apply filter after sorting
            searchText.isEmpty || message.content.localizedCaseInsensitiveContains(searchText)
        }
        
        let formattedText = messagesToCopy.map { message -> String in
            let prefix = message.role == .user ? "User:" : "AI:"
            return "\(prefix)\n\(message.content)\n"
        }.joined(separator: "\n---\n")
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(formattedText, forType: .string)
        statusText = "Chat copied to clipboard."
        // Use Task.sleep for timed dismissal
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            await MainActor.run { // Ensure UI update is on main thread
                 statusText = ""
            }
        }
    }
}

// MARK: - Sidebar Component - MOVED to SidebarView.swift
// struct SidebarView: View { ... }

// MARK: - Chat Detail Component - MOVED to ChatDetailView.swift
// ... existing code ...

// Preview requires adjustments
struct ModalView_Previews: PreviewProvider {
    static var previews: some View {
        ModalView()
    }
} 