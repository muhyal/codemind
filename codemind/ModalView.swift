import SwiftUI
import GoogleGenerativeAI
import MarkdownUI

// Define roles for messages
enum ChatRole {
    case user
    case model
}

// Structure to represent a single message in the display list
struct DisplayMessage: Identifiable {
    let id: UUID // Unique ID for the list row itself (can combine entryId + role)
    let entryId: UUID // Original ChatEntry ID
    let role: ChatRole
    let content: String
    let timestamp: Date
    // Include metadata only for model messages
    let metadata: ChatEntryMetadata?
}

// Separate struct for metadata to avoid passing too many optionals
struct ChatEntryMetadata {
    let wordCount: Int?
    let promptTokenCount: Int?
    let candidatesTokenCount: Int?
    let totalTokenCount: Int?
    let responseTimeMs: Int?
    let modelName: String?
}

struct ModalView: View {
    // Use @StateObject for the DataManager
    @StateObject private var dataManager = DataManager()

    // State for the detail view
    @State private var userInput: String = ""
    @State private var statusText: String = ""
    @State private var isLoading: Bool = false
    @State private var showingSettings: Bool = false
    
    // State for editing session title
    @State private var showingEditAlert: Bool = false
    @State private var sessionToEdit: ChatSession? = nil
    @State private var newSessionTitle: String = ""
    
    // State for sidebar filter
    enum SidebarFilter: String, CaseIterable, Identifiable {
        case all = "All Chats"
        case favorites = "Favorites"
        var id: String { self.rawValue }
    }
    @State private var selectedFilter: SidebarFilter = .all
    
    // State for chat search
    @State private var searchText: String = ""
    
    // State for confirmation dialogs
    @State private var showingClearConfirm: Bool = false
    @State private var showingDeleteConfirm: Bool = false

    // Service for API calls
    private let geminiService = GeminiService()

    // Environment value for color scheme (dark/light mode)
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
        // Use system material background for the main window effect
        .background(.ultraThickMaterial)
        .frame(minWidth: 700, minHeight: 500) // Adjusted default size for split view
        // Alert for editing the session title
        .alert("Edit Chat Title", isPresented: $showingEditAlert, presenting: sessionToEdit) { session in
            TextField("Enter new title", text: $newSessionTitle)
            Button("Save") {
                if let id = sessionToEdit?.id, !newSessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    dataManager.updateTitle(withId: id, newTitle: newSessionTitle)
                    // Reset state after saving
                    sessionToEdit = nil 
                    newSessionTitle = ""
                    // showingEditAlert will be set to false automatically by isPresented binding
                }
            }
            Button("Cancel", role: .cancel) { 
                 // Reset state on cancel
                 sessionToEdit = nil 
                 newSessionTitle = ""
            }
        } message: { session in
             Text("Enter a new title for the chat session.")
        }
        // Pass DataManager to the environment
        .environmentObject(dataManager)
        // Add Toolbar for Search and Menu
        .toolbar {
            ToolbarItemGroup(placement: .navigation) { // Use .navigation or .primaryAction based on desired look
                // Search Bar (integrated via searchable modifier)
                Spacer() // Pushes items to the right
                
                // Action Menu
                Menu {
                    Button {
                        copyChatToPasteboard()
                    } label: {
                        Label("Export Chat (Copy)", systemImage: "doc.text")
                    }
                    
                    Button(role: .destructive) {
                       showingClearConfirm = true
                    } label: {
                       Label("Clear All Messages", systemImage: "clear")
                    }
                    
                    Button(role: .destructive) {
                         showingDeleteConfirm = true
                     } label: {
                         Label("Delete Current Session", systemImage: "trash")
                     }
                    
                } label: {
                    Label("More Actions", systemImage: "ellipsis.circle")
                }
                .menuIndicator(.hidden) // Optional: Hide the default down arrow
            }
        }
        .searchable(text: $searchText, placement: .toolbar) // Add searchable modifier
         // Confirmation Dialogs
        .confirmationDialog(
             "Clear all messages in this chat? This cannot be undone.",
             isPresented: $showingClearConfirm,
             titleVisibility: .visible
        ) {
             Button("Clear Messages", role: .destructive) {
                 if let sessionId = dataManager.activeSessionId {
                     dataManager.clearEntries(sessionId: sessionId)
                 }
             }
             Button("Cancel", role: .cancel) {}
        }
         .confirmationDialog(
              "Delete this entire chat session? This cannot be undone.",
              isPresented: $showingDeleteConfirm,
              titleVisibility: .visible
         ) {
              Button("Delete Session", role: .destructive) {
                  if let sessionId = dataManager.activeSessionId {
                      dataManager.deleteSession(withId: sessionId)
                  }
              }
              Button("Cancel", role: .cancel) {}
         }
    }

    // MARK: - Computed Properties
    
    /// Transforms ChatEntries into a list of individual messages for display, applying search filter.
    private var filteredDisplayMessages: [DisplayMessage] {
        dataManager.activeSessionEntries.flatMap { entry -> [DisplayMessage] in
            var messages: [DisplayMessage] = []
            // Add user message
            if !entry.question.isEmpty {
                messages.append(DisplayMessage(
                    id: UUID(), // Generate unique ID for this row
                    entryId: entry.id,
                    role: .user,
                    content: entry.question,
                    timestamp: entry.timestamp, // Use entry timestamp for ordering
                    metadata: nil
                ))
            }
            // Add model message
            if !entry.answer.isEmpty {
                let metadata = ChatEntryMetadata(
                    wordCount: entry.wordCount,
                    promptTokenCount: entry.promptTokenCount,
                    candidatesTokenCount: entry.candidatesTokenCount,
                    totalTokenCount: entry.totalTokenCount,
                    responseTimeMs: entry.responseTimeMs,
                    modelName: entry.modelName
                )
                messages.append(DisplayMessage(
                    id: UUID(), // Generate unique ID for this row
                    entryId: entry.id,
                    role: .model,
                    content: entry.answer,
                    timestamp: entry.timestamp, // Use entry timestamp for ordering
                    metadata: metadata
                ))
            }
            return messages
        }
        // Filter messages based on search text
        .filter { message in
            searchText.isEmpty || message.content.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    /// The content view for the sidebar.
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Header: Title, New Chat, Settings
            HStack {
                Text("Chats")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Settings")

                Button {
                    dataManager.createNewSession(activate: true)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("New Chat")
            }
            .padding()
            .background(.ultraThinMaterial) // Add a subtle background to header

            // Filter Picker
            Picker("Filter", selection: $selectedFilter) {
                ForEach(SidebarFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 5)

            // List of Sessions
            List(selection: Binding(get: { dataManager.activeSessionId }, set: { newId in
                // Değişikliği bir sonraki çalıştırma döngüsüne ertele
                DispatchQueue.main.async {
                    dataManager.activeSessionId = newId
                }
            })) {
                 sessionRows // <-- Use the computed property for rows
            }
            .listStyle(.sidebar)
             // Add top padding to separate from header
             .padding(.top, 5)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        .background(.ultraThickMaterial) // Give sidebar a distinct background
    }

    /// Builds the rows for the session list, including context menu and delete action.
    private var sessionRows: some View {
        ForEach(filteredSessions) { session in
            SessionRow(session: session, isSelected: dataManager.activeSessionId == session.id)
                .tag(session.id as UUID?) // Use Optional UUID for selection
                .contextMenu { // <-- Add context menu here
                    Button { // Edit Action
                        sessionToEdit = session
                        newSessionTitle = session.title // Pre-fill current title
                        showingEditAlert = true
                    } label: {
                        Label("Edit Title", systemImage: "pencil")
                    }
                    
                    Button { // Copy Title Action
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(session.title, forType: .string)
                    } label: {
                        Label("Copy Title", systemImage: "doc.on.doc")
                    }

                    Button { // Favorite/Unfavorite Action
                        dataManager.toggleFavorite(withId: session.id)
                    } label: {
                        Label(session.isFavorite ? "Unfavorite" : "Favorite", systemImage: session.isFavorite ? "star.slash.fill" : "star.fill")
                    }

                    Divider()

                    Button(role: .destructive) { // Delete Action
                        dataManager.deleteSession(withId: session.id)
                    } label: {
                        Label("Delete Chat", systemImage: "trash.fill")
                    }
                }
        }
        // Attach onDelete directly to ForEach
        .onDelete { (offsets: IndexSet) in // <-- Explicitly type the argument
            // Restore original delete logic here
            let idsToDelete = offsets.map { filteredSessions[$0].id }
            idsToDelete.forEach { id in
                dataManager.deleteSession(withId: id)
            }
        }
    }

    /// The content view for the detail area (chat interface).
    private var detailContent: some View {
        VStack(spacing: 0) {
            // Chat Entries List - Now iterates over filteredDisplayMessages
            ScrollViewReader { scrollViewProxy in
                List(filteredDisplayMessages) { message in // <-- Iterate over Filtered DisplayMessage
                     ChatBubble(message: message)
                         .id(message.id) // ID for scrolling
                         .listRowInsets(EdgeInsets()) // Remove insets for full width bubbles
                         .listRowSeparator(.hidden)
                 }
                .listStyle(.plain)
                .background(colorScheme == .dark ? Color(.controlBackgroundColor) : Color(.textBackgroundColor))
                // Adjust scrolling logic if needed based on the new structure
                .onChange(of: filteredDisplayMessages.count) { _ in 
                    scrollToBottom(proxy: scrollViewProxy)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                       scrollToBottom(proxy: scrollViewProxy)
                    }
                }
                .onChange(of: dataManager.activeSessionId) { _ in
                     DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                         scrollToBottom(proxy: scrollViewProxy)
                     }
                }
            }

            // Status/Error Area
            if !statusText.isEmpty {
                Text(statusText)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(statusText.starts(with: "Error") ? .red : .secondary)
                    .font(.caption)
                    .background(.ultraThinMaterial) // Subtle background for status
            }

            // Input Area
            HStack(spacing: 10) {
                TextField("Enter your question...", text: $userInput, axis: .vertical)
                     .textFieldStyle(.plain) // Use plain style for custom background
                     .lineLimit(1...5)
                     .padding(8)
                     .background(Color(.controlBackgroundColor))
                     .cornerRadius(8)
                     .overlay(
                         RoundedRectangle(cornerRadius: 8)
                             .stroke(colorScheme == .dark ? Color.gray.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 1)
                     )
                     .onSubmit {
                        if !isLoading {
                            Task { await submitQuery() }
                        }
                     }
                     .disabled(isLoading || dataManager.activeSessionId == nil)

                 Button {
                     Task { await submitQuery() }
                 } label: {
                     Image(systemName: isLoading ? "stop.fill" : "paperplane.fill") // Change icon when loading
                         .font(.title3)
                         .frame(width: 24, height: 24) // Ensure consistent size
                 }
                 .buttonStyle(.borderedProminent)
                 .tint(isLoading ? .red : .blue) // Change color when loading
                 .disabled(userInput.isEmpty || dataManager.activeSessionId == nil)
                 .keyboardShortcut(isLoading ? .cancelAction : .defaultAction) // Allow Esc to stop?

            }
            .padding()
            .background(.ultraThinMaterial) // Background for input area
        }
        .navigationTitle(activeSessionTitle) // Show title in the detail view's navigation area
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
         .overlay {
              if dataManager.activeSessionId == nil && !dataManager.chatSessions.isEmpty {
                   Text("Select a chat from the sidebar")
                        .foregroundColor(.secondary)
              }
         }
    }

    // Computed property for filtered sessions
    private var filteredSessions: [ChatSession] {
        switch selectedFilter {
        case .all:
            return dataManager.chatSessions
        case .favorites:
            return dataManager.chatSessions.filter { $0.isFavorite }
        }
    }

    // Helper computed property for the title in the toolbar
    private var activeSessionTitle: String {
        guard let activeID = dataManager.activeSessionId,
              let session = dataManager.chatSessions.first(where: { $0.id == activeID }) else {
            return "No Chat Selected"
        }
        return session.title
    }

    // Helper function to scroll to the bottom of the chat list
    private func scrollToBottom(proxy: ScrollViewProxy) {
        // Now scroll to the last message in the filteredDisplayMessages array
        guard let lastMessageId = filteredDisplayMessages.last?.id else { return }
        proxy.scrollTo(lastMessageId, anchor: .bottom)
    }

    // Function to handle submitting the query to the active session
    @MainActor
    private func submitQuery() async {
        guard let activeSessionID = dataManager.activeSessionId else {
            statusText = "Error: No active chat session."
            return
        }
        guard !userInput.isEmpty else { return }
        guard let apiKey = KeychainHelper.loadAPIKey(), !apiKey.isEmpty else {
            statusText = "Error: API Key is missing. Please add it via Settings (⚙️)."
            return
        }

        isLoading = true
        let currentInput = userInput
        userInput = "" // Clear input immediately
        statusText = "Generating response..."
        
        // Build chat history for the API
        let history: [ModelContent] = dataManager.activeSessionEntries.flatMap { entry -> [ModelContent] in
            // Assume non-empty question/answer means valid turn
             var turn: [ModelContent] = []
             if !entry.question.isEmpty {
                 turn.append(ModelContent(role: "user", parts: [.text(entry.question)]))
             }
             if !entry.answer.isEmpty {
                 turn.append(ModelContent(role: "model", parts: [.text(entry.answer)]))
             }
             return turn
        }

        // Call the updated service function
        let result = await geminiService.generateResponse(history: history, latestPrompt: currentInput, apiKey: apiKey)

        isLoading = false // Stop loading indicator regardless of outcome

        switch result {
        case .success(let generationResult):
            // Pass the full generationResult to the DataManager
            dataManager.addEntryToActiveSession(question: currentInput, generationResult: generationResult)
            statusText = "" // Clear status on success
        case .failure(let error):
            // Show error in status text area
            statusText = "Error: \(error.localizedDescription)"
            // Optionally, re-add user input to the text field on error?
            // userInput = currentInput
        }
    }

    // Helper function to copy formatted chat to pasteboard
    private func copyChatToPasteboard() {
        guard dataManager.activeSessionId != nil else { return }
        
        // Use filteredDisplayMessages for copying
        let formattedText = filteredDisplayMessages.map { message -> String in
            let prefix = message.role == .user ? "User:" : "AI:"
            return "\(prefix)\n\(message.content)\n"
        }.joined(separator: "\n---\n")
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(formattedText, forType: .string)
        statusText = "Chat copied to clipboard."
        // Clear status after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            statusText = ""
        }
    }
}

// Helper View for Sidebar Rows
struct SessionRow: View {
    let session: ChatSession
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: "message") // Add an icon
                .foregroundColor(isSelected ? .primary : .secondary)
            VStack(alignment: .leading) {
                Text(session.title)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                Text(session.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        // Subtle background highlight for selection
        // .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        // .cornerRadius(5) // Optional: rounded corners for background
    }
}

// REFACTORED Helper View for Chat Bubbles
struct ChatBubble: View {
    let message: DisplayMessage // <-- Takes DisplayMessage now
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var dataManager: DataManager
    @State private var showRawMarkdown: Bool = false

    var body: some View {
        HStack(spacing: 0) { // Use 0 spacing, control with padding
            if message.role == .user {
                Spacer() // Push user message right
                
                HStack(alignment: .bottom, spacing: 5) {
                    Text(message.content)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(15)
                        .textSelection(.enabled)
                    
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.blue)
                        .clipShape(Circle())
                }
                .padding(.leading, 40) // Ensure bubble doesn't touch left edge
                .padding(.trailing, 10) // Padding on the right
                
            } else { // message.role == .model
                HStack(alignment: .bottom, spacing: 5) { // HStack for Avatar and Content VStack
                    Image(systemName: "sparkle")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.purple)
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 4) { // VStack for Bubble/Buttons ZStack and Metadata
                        // ZStack for Bubble and Top-Left Buttons
                        ZStack(alignment: .topLeading) {
                            // AI Bubble Content (Markdown or Raw)
                            Group {
                                if showRawMarkdown {
                                    ScrollView {
                                        Text(message.content)
                                            .font(.system(.body, design: .monospaced))
                                            .padding(.all, 10)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                    }
                                    .background(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
                                    .cornerRadius(15)
                                } else {
                                    Markdown(message.content)
                                        .textSelection(.enabled)
                                        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                        .background(colorScheme == .dark ? Color.gray.opacity(0.4) : Color.gray.opacity(0.15))
                                        .cornerRadius(15)
                                }
                            }
                             // Add padding to the bubble content for buttons
                            .padding(.top, 25)
                            .padding(.leading, 5)

                            // Action buttons in Top-Left
                            actionButtons
                                .padding(4)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding([.leading, .top], 6)
                        }
                        
                        // Metadata Display (Below the ZStack, inside the VStack)
                        if let metadata = message.metadata {
                            metadataView(metadata: metadata)
                        }
                    } // End VStack for Bubble/Buttons + Metadata
                     // Ensure content VStack doesn't stretch unnecessarily if bubble is small
                    .layoutPriority(1)
                    
                } // End HStack for Avatar and Content VStack
                .padding(.trailing, 40) // Ensure bubble doesn't touch right edge
                .padding(.leading, 10) // Padding on the left
                
                Spacer() // Push AI message group left
            }
        }
        .padding(.vertical, 5)
        // Add context menu to the entire row
        .contextMenu {
            if message.role == .user {
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(message.content, forType: .string)
                } label: {
                    Label("Copy Question", systemImage: "doc.on.doc")
                }
                
                Button(role: .destructive) {
                     dataManager.deleteEntry(entryId: message.entryId)
                 } label: {
                     Label("Delete Entry", systemImage: "trash")
                 }
            } else { // .model
                 Button {
                     let pasteboard = NSPasteboard.general
                     pasteboard.clearContents()
                     pasteboard.setString(message.content, forType: .string)
                 } label: {
                     Label("Copy Answer", systemImage: "doc.on.doc")
                 }
                 
                 Button(role: .destructive) {
                      dataManager.deleteEntry(entryId: message.entryId)
                  } label: {
                      Label("Delete Entry", systemImage: "trash")
                  }
            }
        }
    }

    // Helper for Metadata View (Restored details)
    @ViewBuilder
    private func metadataView(metadata: ChatEntryMetadata) -> some View {
        // Show relevant metadata + timestamp
        HStack(spacing: 8) {
            if let wc = metadata.wordCount { Text("WC: \(wc)") }
            if let tc = metadata.candidatesTokenCount { Text("TC: \(tc)") } // Show candidate tokens
            if let tt = metadata.totalTokenCount { Text("Used: \(tt)") }
            if let rt = metadata.responseTimeMs { Text("Latency: \(rt)ms") }
            if let model = metadata.modelName { Text("Model: \(model.replacingOccurrences(of: "gemini-", with: ""))") } // Shorten model name
             Text(message.timestamp, style: .time)
        }
        .font(.caption2)
        .foregroundColor(.secondary)
        .padding(.leading, 0) // Align with bubble start
        .padding(.top, 2)
    }
    
    // Helper computed property for action buttons (Horizontal layout)
    private var actionButtons: some View {
        HStack(spacing: 6) { // Reduce spacing
             // Toggle Raw/Rendered Button
             Button { showRawMarkdown.toggle() } label: { Image(systemName: showRawMarkdown ? "doc.richtext.fill" : "doc.plaintext").font(.footnote) } // Smaller icon
                .buttonStyle(.plain)
                .help(showRawMarkdown ? "Rendered - Show Rendered" : "Raw - Show Raw Markdown")
            
            Button { // Copy
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(message.content, forType: .string)
            } label: { Image(systemName: "doc.on.doc").font(.footnote) } // Smaller icon
                .buttonStyle(.plain)
                .help("Copy - Copy Answer")
            
            Button { // Delete
                dataManager.deleteEntry(entryId: message.entryId) // Use entryId
            } label: { Image(systemName: "trash").font(.footnote) } // Smaller icon
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .help("Delete - Delete Entry")
        }
        // Adjust padding and background for minimality
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(colorScheme == .dark ? Color.black.opacity(0.3) : Color.white.opacity(0.4), in: Capsule()) // More subtle background
    }
}

// Preview requires adjustments
struct ModalView_Previews: PreviewProvider {
    static var previews: some View {
        ModalView()
    }
} 