import SwiftUI
import MarkdownUI // Needed for Markdown view

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