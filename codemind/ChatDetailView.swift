import SwiftUI
import GoogleGenerativeAI // Needed for ModelContent

// MARK: - Chat Detail Component
struct ChatDetailView: View {
    @Binding var searchText: String
    @Binding var statusText: String
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
        // 1. Flatten Chat Entries into DisplayMessages with stable IDs
        let allMessages = dataManager.activeSessionEntries.flatMap { entry -> [DisplayMessage] in
            var messages: [DisplayMessage] = []
            // Add user message
            if !entry.question.isEmpty {
                messages.append(DisplayMessage(
                    id: entry.id.uuidString + "-user", // Stable ID
                    entryId: entry.id,
                    role: .user,
                    content: entry.question,
                    timestamp: entry.timestamp,
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
                    id: entry.id.uuidString + "-model", // Stable ID
                    entryId: entry.id,
                    role: .model,
                    content: entry.answer,
                    // Use a slightly later timestamp for model to ensure order within the same entry
                    timestamp: entry.timestamp.addingTimeInterval(0.001),
                    metadata: metadata
                ))
            }
            return messages
        }
        // 2. Sort all messages by timestamp
        .sorted { $0.timestamp < $1.timestamp }

        // 3. Filter based on search text
        if searchText.isEmpty {
            return allMessages // Return sorted messages if no search
        } else {
            return allMessages.filter { message in
                message.content.localizedCaseInsensitiveContains(searchText)
            }
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
                 .onChange(of: filteredDisplayMessages.last?.id) { newLastId in
                     if let id = newLastId {
                         scrollToBottom(proxy: scrollViewProxy, id: id)
                     }
                 }
                 .onChange(of: dataManager.activeSessionId) { _ in
                     DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { 
                          if let lastId = filteredDisplayMessages.last?.id {
                              scrollToBottom(proxy: scrollViewProxy, id: lastId)
                          }
                     }
                 }
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
    
    // Helper function to scroll to the bottom of the chat list
    // Update to accept String ID
    private func scrollToBottom(proxy: ScrollViewProxy, id: String, anchor: UnitPoint? = .bottom) {
        print("ScrollToBottom: Attempting to scroll to ID \(id)")
        // Use withAnimation for smoother scrolling
        withAnimation(.easeOut(duration: 0.2)) { // Adjust duration if needed
             proxy.scrollTo(id, anchor: anchor)
        }
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