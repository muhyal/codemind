import SwiftUI
import GoogleGenerativeAI
import MarkdownUI

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
    }

    // MARK: - Computed Views
    
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
            // Chat Entries List
            ScrollViewReader { scrollViewProxy in
                List(dataManager.activeSessionEntries) { entry in
                     ChatBubble(entry: entry)
                         .id(entry.id) // ID for scrolling
                         // Remove default list padding/margins for tighter bubbles
                         .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                         .listRowSeparator(.hidden)
                 }
                .listStyle(.plain)
                .background(colorScheme == .dark ? Color(.controlBackgroundColor) : Color(.textBackgroundColor)) // Match window background
                .onChange(of: dataManager.activeSessionEntries.count) { _ in // Scroll on new entry
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
        guard let lastEntryId = dataManager.activeSessionEntries.last?.id else { return }
        proxy.scrollTo(lastEntryId, anchor: .bottom)
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

// Helper View for Chat Bubbles
struct ChatBubble: View {
    let entry: ChatEntry
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var dataManager: DataManager // Access DataManager
    
    @State private var showRawMarkdown: Bool = false // State to toggle raw view

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) { // Use HStack for avatar + bubble
            // User Avatar and Bubble
            if entry.question.isEmpty == false { // Assuming user question is always present
                 Spacer() // <-- Add Spacer BEFORE to push right
                
                 Text(entry.question)
                     .padding(.horizontal, 12)
                     .padding(.vertical, 8)
                     .background(Color.blue)
                     .foregroundColor(.white)
                     .cornerRadius(15)
                     // Ensure the frame allows bubble to grow but aligns content right
                     .frame(maxWidth: .infinity, alignment: .trailing) 
                 
                 Image(systemName: "person.crop.circle.fill")
                     .font(.title2)
                     .foregroundColor(.secondary)
                 // Remove Spacer from the end
            }
            
            // AI Avatar, Bubble, and Actions
            if entry.answer.isEmpty == false { // Check if there is an AI answer
                 Image(systemName: "sparkle") // AI Avatar First
                     .font(.title2)
                     .foregroundColor(.purple)
                 
                 VStack(alignment: .leading) { // Changed to leading for inner content alignment
                     // HStack containing the AI Bubble and Vertical Buttons
                     HStack(alignment: .top, spacing: 4) {
                         // Conditionally display Markdown or Raw Text
                         if showRawMarkdown {
                             ScrollView {
                                 Text(entry.answer)
                                     .font(.system(.body, design: .monospaced))
                                     .padding(.all, 10) // Uniform padding
                                     .background(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
                                     .foregroundColor(.primary)
                                     .cornerRadius(15)
                                     .frame(maxWidth: .infinity, alignment: .leading)
                                     .textSelection(.enabled)
                             }
                         } else {
                             Markdown(entry.answer)
                                 // .markdownTheme(.gitHub)
                                 .textSelection(.enabled)
                                 .markdownStyle(
                                      MarkdownStyle(
                                          padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
                                      )
                                  )
                                 .background(colorScheme == .dark ? Color.gray.opacity(0.4) : Color.gray.opacity(0.15))
                                 .cornerRadius(15)
                                 // Let the Markdown view determine its width based on content
                                 .fixedSize(horizontal: false, vertical: true)
                         }
                         
                         // Vertical Buttons VStack
                         actionButtons // Use helper for buttons
                            .frame(width: 20) // Give buttons a fixed width
                     }
                      // Ensure this HStack itself doesn't expand infinitely
                     .frame(maxWidth: .infinity, alignment: .leading)
                     
                     // Metadata Display (aligned left under AI bubble)
                     ViewThatFits(in: .horizontal) {
                         // Wide layout
                         HStack(spacing: 8) {
                             if let wc = entry.wordCount { Text("WC: \(wc)") }
                             if let tc = entry.candidatesTokenCount { Text("TC: \(tc)") }
                             if let tt = entry.totalTokenCount { Text("Used: \(tt)") }
                             if let rt = entry.responseTimeMs { Text("Latency: \(rt)ms") }
                             Text(entry.timestamp, style: .time)
                             // Buttons removed from here
                         }
                         
                         // Narrow layout
                         HStack(spacing: 8) {
                             Text(entry.timestamp, style: .time)
                             // Buttons removed from here
                         }
                     }
                     .font(.caption2)
                     .foregroundColor(.secondary)
                     .padding(.leading, 12) // Indent metadata slightly
                     .padding(.top, 2)
                 }
                 
                 Spacer() // <-- Add Spacer AFTER to push left
             }
        }
        .padding(.vertical, 5)
    }
    
    // Helper computed property for action buttons to avoid repetition
    private var actionButtons: some View {
        VStack(spacing: 8) { // Keep buttons vertical
             // Toggle Raw/Rendered Button
             Button {
                 showRawMarkdown.toggle()
             } label: {
                 Image(systemName: showRawMarkdown ? "doc.richtext.fill" : "doc.plaintext")
             }
             .buttonStyle(.plain)
             .help(showRawMarkdown ? "Rendered - Show Rendered" : "Raw - Show Raw Markdown")
             
            // Copy Button
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(entry.answer, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .help("Copy - Copy Answer")
            
            // Delete Button
            Button {
                dataManager.deleteEntry(entryId: entry.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
            .help("Delete - Delete Entry")
        }
    }
}

// Preview requires adjustments
struct ModalView_Previews: PreviewProvider {
    static var previews: some View {
        ModalView()
    }
} 