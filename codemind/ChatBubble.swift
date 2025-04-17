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
    @State private var showingMetadataPopover: Bool = false // State for popover visibility

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
                // Wrap the existing HStack in a VStack to place buttons above
                VStack(alignment: .leading, spacing: 2) { // Added VStack
                    
                    // --- Action Buttons Moved Here ---
                    actionButtons 
                        // No background needed now, adjust padding
                        .padding(.leading, 35) // Align roughly with avatar start + spacing
                        .padding(.bottom, 2) // Small space below buttons
                    
                    // --- Original HStack (Avatar + Content) ---
                    HStack(alignment: .bottom, spacing: 5) { 
                        // Updated AI Avatar with Gradient and Glow
                        Image(systemName: "sparkle")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30) // Slightly larger
                            .background(aiBubbleGradient)
                            .clipShape(Circle())
                            .shadow(color: aiGlowColor.opacity(0.5), radius: 3, x: 0, y: 1)
                            
                        VStack(alignment: .leading, spacing: 4) { // VStack for Bubble/Buttons ZStack and Metadata
                            // AI Bubble Content (Markdown or Raw) with Gradient and Glow
                            VStack(alignment: .leading) {
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
                            
                            // Metadata Display (Below the Bubble, inside the VStack)
                            if let metadata = message.metadata {
                                metadataView(metadata: metadata)
                            }
                        } // End VStack for Bubble + Metadata
                         // Ensure content VStack doesn't stretch unnecessarily if bubble is small
                        .layoutPriority(1)
                        
                    } // End HStack for Avatar and Content VStack
                    
                } // End ADDED VStack wrapping buttons and HStack
                .padding(.trailing, 40) // Ensure bubble doesn't touch right edge
                .padding(.leading, 10) // Padding on the left
                
                Spacer() // Push AI message group left
            }
        }
        .padding(.vertical, 8) // INCREASED vertical padding
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
        HStack(spacing: 4) { 
            // --- Info Button with custom popover on click --- 
            Button {
                showingMetadataPopover.toggle()
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain) 
            // .overlay(alignment: .bottomLeading) { ... } // REMOVED Manual Overlay
            // Use standard popover modifier attached to the button
            .popover(isPresented: $showingMetadataPopover, 
                     attachmentAnchor: .point(.bottomLeading), // Attach to bottom-left of button
                     arrowEdge: .leading) { // Show arrow on the left edge
                metadataPopover(metadata: metadata)
            }
            
            // --- Timestamp remains text ---
             Text(message.timestamp, style: .time)
        }
        .font(.caption) 
        .foregroundColor(.secondary)
        .padding(.leading, 35) 
        .padding(.top, 2)
        // .animation(.easeInOut(duration: 0.15), value: showingMetadataPopover) // REMOVED Manual animation
    }
    
    // --- Custom Popover View --- 
    @ViewBuilder
    private func metadataPopover(metadata: ChatEntryMetadata) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let wc = metadata.wordCount { Text("Words: \(wc)") }
            if let tc = metadata.candidatesTokenCount { Text("Tokens (Cand.): \(tc)") } // More descriptive
            if let tt = metadata.totalTokenCount { Text("Tokens (Total): \(tt)") } // More descriptive
            if let rt = metadata.responseTimeMs { Text("Latency: \(rt)ms") }
            if let model = metadata.modelName { Text("Model: \(model.replacingOccurrences(of: "gemini-", with: ""))") }
        }
        .font(.caption) // Keep caption font for consistency
        .padding(8) // Inner padding
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 3)
        .fixedSize() // Prevent it from taking full width
    }
    
    // Helper function to create formatted multi-line help text for metadata - KEPT for potential future use or copy
    private func formattedMetadataHelpText(metadata: ChatEntryMetadata) -> String {
        var components: [String] = []
        if let wc = metadata.wordCount { components.append("WC: \(wc)") }
        if let tc = metadata.candidatesTokenCount { components.append("TC: \(tc)") }
        if let tt = metadata.totalTokenCount { components.append("Used: \(tt)") }
        if let rt = metadata.responseTimeMs { components.append("Latency: \(rt)ms") }
        if let model = metadata.modelName { components.append("Model: \(model.replacingOccurrences(of: "gemini-", with: ""))") }
        
        return components.joined(separator: "\n") // Join with newlines for multi-line tooltip
    }
    
    // Helper computed property for action buttons (Horizontal layout)
    private var actionButtons: some View {
        HStack(spacing: 8) { // INCREASED spacing
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
        // Adjust padding and background for minimality - REMOVED Background, simplified padding
        // .padding(.horizontal, 5) // REMOVED
        // .padding(.vertical, 3)   // REMOVED
        // .background(colorScheme == .dark ? Color.black.opacity(0.3) : Color.white.opacity(0.4), in: Capsule()) // REMOVED
    }
} 