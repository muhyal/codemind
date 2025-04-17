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

// Sidebar Filter Enum (Moved to top level)
enum SidebarFilter: String, CaseIterable, Identifiable {
    case all = "All Chats"
    case favorites = "Favorites"
    // Add color filters (examples)
    case red = "Red"
    case blue = "Blue"
    case green = "Green"
    // Add more colors as needed

    var id: String { self.rawValue }
}

// MARK: - Main View
struct ModalView: View {
    @StateObject private var dataManager = DataManager()
    @State private var showingSettings: Bool = false
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
                showingSettings: $showingSettings,
                showingEditAlert: $showingEditAlert,
                sessionToEdit: $sessionToEdit,
                newSessionTitle: $newSessionTitle
            )
        } detail: {
             ChatDetailView(
                 searchText: $searchText,
                 statusText: $statusText,
                 showingSettings: $showingSettings,
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
        // Confirmation Dialogs
        .confirmationDialog("Clear all messages...", isPresented: $showingClearConfirm) { 
             Button("Clear Messages", role: .destructive) {
                 if let sessionId = dataManager.activeSessionId {
                     dataManager.clearEntries(sessionId: sessionId)
                 }
             }
             Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this entire chat session...", isPresented: $showingDeleteConfirm) { 
            Button("Delete Session", role: .destructive) {
                if let sessionId = dataManager.activeSessionId {
                    dataManager.deleteSession(withId: sessionId)
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
        let result = await geminiService.generateResponse(history: [], latestPrompt: summarizationPrompt, apiKey: apiKey)
        
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
        let messagesToCopy = dataManager.activeSessionEntries.flatMap { entry -> [DisplayMessage] in
             var messages: [DisplayMessage] = []
             if !entry.question.isEmpty { messages.append(DisplayMessage(
                 id: UUID(),
                 entryId: entry.id,
                 role: .user,
                 content: entry.question,
                 timestamp: entry.timestamp,
                 metadata: nil
             )) }
             if !entry.answer.isEmpty { messages.append(DisplayMessage(
                 id: UUID(),
                 entryId: entry.id,
                 role: .model,
                 content: entry.answer,
                 timestamp: entry.timestamp,
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
        }.filter { message in
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { statusText = "" }
    }
}

// MARK: - Sidebar Component
struct SidebarView: View {
    @Binding var selectedFilter: SidebarFilter
    @Binding var showingSettings: Bool
    // State needed for edit alert interaction
    @Binding var showingEditAlert: Bool
    @Binding var sessionToEdit: ChatSession?
    @Binding var newSessionTitle: String

    @EnvironmentObject var dataManager: DataManager

    // Predefined colors (can be reused for filtering logic)
    private let availableColors: [String?] = [
        nil,
        "#FF3B30", // Red
        "#FF9500", // Orange
        "#FFCC00", // Yellow
        "#34C759", // Green
        "#007AFF", // Blue
        "#AF52DE", // Purple
        "#8E8E93"  // Grey
    ]
    
    // Map filter cases to hex values for easier filtering
    private func hex(for filter: SidebarFilter) -> String? {
        switch filter {
            case .red: return "#FF3B30"
            case .blue: return "#007AFF"
            case .green: return "#34C759"
            // Add mappings for other color filters
            default: return nil // Not a color filter
        }
    }

    // Computed property for filtered sessions (updated logic)
    private var filteredSessions: [ChatSession] {
        let targetColorHex = hex(for: selectedFilter)
        
        return dataManager.chatSessions.filter { session in
            switch selectedFilter {
            case .all:
                return true
            case .favorites:
                return session.isFavorite
            // Handle color cases
            case .red, .blue, .green: // Add other colors here
                return session.colorHex == targetColorHex
            }
        }
    }

    // Helper to get app version
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "N/A"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: Title, New Chat, Settings
            HStack {
                Text("Chats")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button { showingSettings = true } label: { Image(systemName: "gearshape.fill").font(.title3) }
                    .buttonStyle(.plain).help("Settings")
                Button { dataManager.createNewSession(activate: true) } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                    .buttonStyle(.plain).help("New Chat")
             }
            .padding()

            // Filter Picker (now includes colors)
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
                 DispatchQueue.main.async { dataManager.activeSessionId = newId }
            })) {
                 sessionRows
            }
            .listStyle(.sidebar)
            .background(.clear) 
            .scrollContentBackground(.hidden) 
            .padding(.top, 5)
            
            Spacer() // Pushes the version info to the bottom
            
            // Add App Name and Version Info
            Text("CodeMind v\(appVersion)")
                .font(.footnote) // Use footnote size
                .foregroundColor(.secondary)
                .padding(.bottom, 8) // Add some padding at the bottom
                .padding(.horizontal) // Add horizontal padding
                .frame(maxWidth: .infinity, alignment: .center) // Center align
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
    }
    
    /// Builds the rows for the session list.
    private var sessionRows: some View {
        ForEach(filteredSessions) { session in
            SessionRow(session: session, isSelected: dataManager.activeSessionId == session.id)
                .tag(session.id as UUID?)
                .contextMenu { 
                    Button { // Edit Action
                        sessionToEdit = session
                        newSessionTitle = session.title
                        showingEditAlert = true
                    } label: { Label("Edit Title", systemImage: "pencil") }
                    
                    Button { // Copy Title Action
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(session.title, forType: .string)
                    } label: { Label("Copy Title", systemImage: "doc.on.doc") }

                    Button { // Favorite/Unfavorite Action
                        dataManager.toggleFavorite(withId: session.id)
                    } label: { Label(session.isFavorite ? "Unfavorite" : "Favorite", systemImage: session.isFavorite ? "star.slash.fill" : "star.fill") }

                    // Add Set Color Submenu
                    Menu {
                        ForEach(availableColors, id: \.self) { colorHex in
                            Button {
                                dataManager.updateSessionColor(withId: session.id, colorHex: colorHex)
                            } label: {
                                HStack {
                                    if let hex = colorHex {
                                        Circle().fill(colorFromHex(hex)).frame(width: 12, height: 12)
                                        Text(colorName(from: hex)) // Optional: Display color name
                                    } else {
                                        Image(systemName: "circle.slash") // Icon for removing color
                                        Text("None")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Set Color", systemImage: "paintpalette")
                    }

                    Divider()

                    Button(role: .destructive) { // Delete Action
                        dataManager.deleteSession(withId: session.id)
                    } label: { Label("Delete Chat", systemImage: "trash.fill") }
                }
        }
        .onDelete { offsets in
            let idsToDelete = offsets.map { filteredSessions[$0].id }
            idsToDelete.forEach { id in dataManager.deleteSession(withId: id) }
        }
    }
    
    // Helper to convert hex to Color (copied from SessionRow for use in menu)
    // Ideally, this would be in a shared utility file
    private func colorFromHex(_ hex: String?) -> Color {
        guard let hex = hex, hex.hasPrefix("#"), hex.count == 7 else {
            return Color.gray // Default color if hex is invalid or nil
        }
        let scanner = Scanner(string: String(hex.dropFirst()))
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        
        return Color(red: r, green: g, blue: b)
    }
    
    // Optional helper to get a name for a hex color
    private func colorName(from hex: String) -> String {
        switch hex {
            case "#FF3B30": return "Red"
            case "#FF9500": return "Orange"
            case "#FFCC00": return "Yellow"
            case "#34C759": return "Green"
            case "#007AFF": return "Blue"
            case "#AF52DE": return "Purple"
            case "#8E8E93": return "Grey"
            default: return "Color"
        }
    }
}

// MARK: - Chat Detail Component
struct ChatDetailView: View {
    @Binding var searchText: String
    @Binding var statusText: String
    @Binding var showingSettings: Bool
    // Pass colors/gradients
    let userBubbleGradient: LinearGradient
    let aiBubbleGradient: LinearGradient
    let aiRawBackground: Color
    let userGlowColor: Color
    let aiGlowColor: Color
    
    // Add geminiService property
    let geminiService: GeminiService
    
    // Environment
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.colorScheme) var colorScheme
    
    // Local state for this view
    @State private var userInput: String = ""
    @State private var isLoading: Bool = false
    
    /// Computed property for filtered messages (moved from ModalView)
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
    
    /// Active session title (moved from ModalView)
    private var activeSessionTitle: String {
        guard let activeID = dataManager.activeSessionId,
              let session = dataManager.chatSessions.first(where: { $0.id == activeID }) else {
            return "No Chat Selected"
        }
        return session.title
    }

    var body: some View {
        VStack(spacing: 0) {
            // Chat Message List View
            ScrollViewReader { scrollViewProxy in
                List(filteredDisplayMessages) { message in
                     ChatBubble(
                         message: message, 
                         userBubbleGradient: userBubbleGradient, 
                         aiBubbleGradient: aiBubbleGradient, 
                         aiRawBackground: aiRawBackground,
                         userGlowColor: userGlowColor, 
                         aiGlowColor: aiGlowColor
                     )
                         .id(message.id)
                         .listRowInsets(EdgeInsets())
                         .listRowSeparator(.hidden)
                 }
                 .listStyle(.plain)
                 .background(.clear)
                 .onChange(of: filteredDisplayMessages.count) { _ in scrollToBottom(proxy: scrollViewProxy) }
                 .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { scrollToBottom(proxy: scrollViewProxy) } }
                 .onChange(of: dataManager.activeSessionId) { _ in DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { scrollToBottom(proxy: scrollViewProxy) } }
             }
 
             // Status Area (Keep its own thin material)
             if !statusText.isEmpty {
                 Text(statusText)
                     .padding(.horizontal)
                     .padding(.vertical, 6)
                     .frame(maxWidth: .infinity, alignment: .leading)
                     .foregroundColor(statusText.starts(with: "Error") ? .red : .secondary)
                     .font(.caption)
                     .background(.ultraThinMaterial) // Keep this specific background
             }
 
             // Input Area (Already has ultraThinMaterial background)
             HStack(spacing: 12) {
                 TextField("Enter your question...", text: $userInput, axis: .vertical)
                     .textFieldStyle(.plain)
                         .lineLimit(1...5)
                     .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)) // Adjust padding
                     // Updated Background and Border/Glow
                     .background(
                         RoundedRectangle(cornerRadius: 15) // Use slightly larger radius
                            .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color.white.opacity(0.6))
                     )
                         .overlay(
                         RoundedRectangle(cornerRadius: 15)
                             .stroke(userGlowColor.opacity(isLoading ? 0.3 : 0.8), lineWidth: 1.5) // Make border slightly thicker and dynamic
                             .shadow(color: userGlowColor.opacity(isLoading ? 0.2 : 0.6), radius: 4) // Adjust shadow
                     )
                     .clipShape(RoundedRectangle(cornerRadius: 15)) // Clip the shape
                     .onSubmit { if !isLoading { Task { await submitQuery() } } }
                         .disabled(isLoading || dataManager.activeSessionId == nil)

                 // Updated Send Button Style
                 Button { Task { await submitQuery() } } label: { 
                     Image(systemName: isLoading ? "stop.fill" : "arrow.up") // Use arrow.up for send
                         .font(.system(size: 18, weight: .semibold)) // Slightly larger, bolder icon
                         .foregroundColor(.white) // White icon
                         .frame(width: 36, height: 36) // Make button circular and slightly larger
                         .background(userGlowColor.opacity(isLoading ? 0.5 : 1.0)) // Use user color for background
                         .clipShape(Circle()) // Circular shape
                         .shadow(color: userGlowColor.opacity(0.5), radius: 3, y: 1) // Add subtle shadow
                 }
                 .buttonStyle(.plain) // Use plain style for custom background
                     .disabled(userInput.isEmpty || dataManager.activeSessionId == nil)
                 .keyboardShortcut(isLoading ? .cancelAction : .defaultAction)
                 .animation(.easeInOut(duration: 0.2), value: isLoading) // Animate changes
                 .animation(.easeInOut(duration: 0.2), value: userInput.isEmpty) // Animate disabled state
             }
             .padding()
             .background(.ultraThinMaterial) // Keep this specific background
         }
         .ignoresSafeArea(.container, edges: .top)
         .navigationTitle(activeSessionTitle)
         .searchable(text: $searchText, placement: .toolbar)
    }
    
    // MARK: - Helper Functions (Moved from ModalView where appropriate)
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        // Now scroll to the last message in the filteredDisplayMessages array
        guard let lastMessageId = filteredDisplayMessages.last?.id else { return }
        proxy.scrollTo(lastMessageId, anchor: .bottom)
    }
    
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
             var turn: [ModelContent] = []
             if !entry.question.isEmpty { turn.append(ModelContent(role: "user", parts: [.text(entry.question)])) }
             if !entry.answer.isEmpty { turn.append(ModelContent(role: "model", parts: [.text(entry.answer)])) }
             return turn
        }

        // Use the passed geminiService instance
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
            // Restore user input on error
            userInput = currentInput 
        }
    }
}

// Helper View for Sidebar Rows
struct SessionRow: View {
    let session: ChatSession
    let isSelected: Bool

    // Helper to convert hex to Color (basic implementation)
    private func colorFromHex(_ hex: String?) -> Color {
        guard let hex = hex, hex.hasPrefix("#"), hex.count == 7 else {
            return Color.gray // Default color if hex is invalid or nil
        }
        let scanner = Scanner(string: String(hex.dropFirst()))
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        
        return Color(red: r, green: g, blue: b)
    }

    var body: some View {
        HStack(spacing: 8) { // Add spacing for the color dot
            // Add Color Dot
            Circle()
                .fill(colorFromHex(session.colorHex).opacity(session.colorHex == nil ? 0.3 : 1.0)) // Use helper, make default grey semi-transparent
                .frame(width: 8, height: 8)
            
            Image(systemName: "message")
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
    }
}

// REFACTORED Helper View for Chat Bubbles
struct ChatBubble: View {
    let message: DisplayMessage // <-- Takes DisplayMessage now
    // Add properties to receive colors/gradients
    let userBubbleGradient: LinearGradient
    let aiBubbleGradient: LinearGradient
    let aiRawBackground: Color
    let userGlowColor: Color
    let aiGlowColor: Color
    
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var dataManager: DataManager
    @State private var showRawMarkdown: Bool = false

    var body: some View {
        HStack(spacing: 0) { // Use 0 spacing, control with padding
            if message.role == .user {
                Spacer() // Push user message right
                
                HStack(alignment: .bottom, spacing: 5) {
                    // User Bubble Content with Gradient and Glow
                    Text(message.content)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(userBubbleGradient)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(color: userGlowColor.opacity(0.4), radius: 5, x: 0, y: 2) // Glow effect
                        .textSelection(.enabled)
                    
                    // Updated User Avatar with Gradient and Glow
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30) // Slightly larger
                        .background(userBubbleGradient)
                        .clipShape(Circle())
                        .shadow(color: userGlowColor.opacity(0.5), radius: 3, x: 0, y: 1)
                }
                .padding(.leading, 40) // Ensure bubble doesn't touch left edge
                .padding(.trailing, 10) // Padding on the right
                
            } else { // message.role == .model
                HStack(alignment: .bottom, spacing: 5) { // HStack for Avatar and Content VStack
                    // Updated AI Avatar with Gradient and Glow
                    Image(systemName: "sparkle")
                        .font(.title3)
                .foregroundColor(.white)
                        .frame(width: 30, height: 30) // Slightly larger
                        .background(aiBubbleGradient)
                        .clipShape(Circle())
                        .shadow(color: aiGlowColor.opacity(0.5), radius: 3, x: 0, y: 1)
                        
                    VStack(alignment: .leading, spacing: 4) { // VStack for Bubble/Buttons ZStack and Metadata
                        // ZStack for Bubble and Top-Left Buttons
                        ZStack(alignment: .topLeading) {
                            // AI Bubble Content (Markdown or Raw) with Gradient and Glow
                            Group {
                                if showRawMarkdown {
                                    ScrollView {
                                        Text(message.content)
                                            .font(.system(.body, design: .monospaced))
                                            .padding(.all, 10)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                    }
                                    .background(aiRawBackground) // Use defined raw background
                                    .cornerRadius(16)
                                    .shadow(color: aiGlowColor.opacity(0.4), radius: 5, x: 0, y: 2) // Glow effect
                                    
                                } else {
                                    Markdown(message.content)
                                        .textSelection(.enabled)
                                        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                        .background(aiBubbleGradient)
                                        .foregroundColor(.primary) // Use primary for better contrast on gradient
                                        .cornerRadius(16)
                                        .shadow(color: aiGlowColor.opacity(0.4), radius: 5, x: 0, y: 2) // Glow effect
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

// Simple view to display the summary in a sheet
struct SummaryView: View {
    let summary: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Chat Summary")
                    .font(.title2)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(.bottom)
            
            ScrollView {
                Text(summary)
                    .textSelection(.enabled)
            }
            Spacer() // Push content to top
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300) // Give sheet a reasonable size
    }
}

// Preview requires adjustments
struct ModalView_Previews: PreviewProvider {
    static var previews: some View {
        ModalView()
    }
} 