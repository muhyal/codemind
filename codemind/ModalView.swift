import SwiftUI

struct ModalView: View {
    // Use @StateObject for the DataManager
    @StateObject private var dataManager = DataManager()

    // State for the detail view
    @State private var userInput: String = ""
    @State private var statusText: String = ""
    @State private var isLoading: Bool = false
    @State private var showingSettings: Bool = false

    // Service for API calls
    private let geminiService = GeminiService()

    // Environment value for color scheme (dark/light mode)
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationSplitView {
            // --- Sidebar ---
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

                // List of Sessions
                List(selection: $dataManager.activeSessionId) {
                    ForEach(dataManager.chatSessions) { session in
                        SessionRow(session: session, isSelected: dataManager.activeSessionId == session.id)
                            .tag(session.id as UUID?) // Use Optional UUID for selection
                    }
                    .onDelete(perform: deleteSessions)
                }
                .listStyle(.sidebar)
                 // Add top padding to separate from header
                 .padding(.top, 5)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .background(.ultraThickMaterial) // Give sidebar a distinct background

        } detail: {
            // --- Detail View (Chat Interface) ---
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
        // Use system material background for the main window effect
        .background(.ultraThickMaterial)
        .frame(minWidth: 700, minHeight: 500) // Adjusted default size for split view
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

    // Function to handle deleting sessions from the sidebar list
    private func deleteSessions(at offsets: IndexSet) {
        let idsToDelete = offsets.map { dataManager.chatSessions[$0].id }
        idsToDelete.forEach { id in
            dataManager.deleteSession(withId: id)
        }
    }

    // Function to handle submitting the query to the active session
    @MainActor
    private func submitQuery() async {
        guard dataManager.activeSessionId != nil else {
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

        let result = await geminiService.generateResponse(prompt: currentInput, apiKey: apiKey)

        isLoading = false // Stop loading indicator regardless of outcome

        switch result {
        case .success(let generatedText):
            // Add entry to the *active* session
            dataManager.addEntryToActiveSession(question: currentInput, answer: generatedText)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // User Bubble
            Text(entry.question)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(15)
                .frame(maxWidth: .infinity, alignment: .trailing) // Align user bubble right

            // AI Bubble
            Text(entry.answer)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(colorScheme == .dark ? Color.gray.opacity(0.4) : Color.gray.opacity(0.15))
                .foregroundColor(.primary)
                .cornerRadius(15)
                .frame(maxWidth: .infinity, alignment: .leading) // Align AI bubble left

            // Timestamp (Optional)
            // Text(entry.timestamp, style: .time)
            //     .font(.caption2)
            //     .foregroundColor(.gray)
            //     .frame(maxWidth: .infinity, alignment: .leading)
            //     .padding(.leading, 12)
        }
    }
}

// Preview requires adjustments
struct ModalView_Previews: PreviewProvider {
    static var previews: some View {
        ModalView()
    }
} 