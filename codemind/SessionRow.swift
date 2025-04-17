import SwiftUI

// Helper View for Sidebar Rows
struct SessionRow: View {
    let session: ChatSession
    let isSelected: Bool
    let isHovering: Bool // Add hover state

    // Date Formatter for short date and time
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        HStack(spacing: 8) {
            // Use message icon, color based on selection/hover
            Image(systemName: "message.fill") // Use filled icon
                .foregroundStyle(isSelected ? .primary : (colorFromHex(session.colorHex) ?? .secondary))
                .font(.body) // Consistent icon size
                .frame(width: 20, alignment: .center) // Give icon fixed width

            VStack(alignment: .leading, spacing: 2) { // Reduce spacing
                Text(session.title)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                
                // Optionally show timestamp or a snippet of last message?
                // Keeping timestamp for now
                Text(session.createdAt, formatter: dateFormatter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if session.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .font(.caption) // Keep star small
            }
        }
        .padding(.vertical, 6) // Consistent vertical padding
        .padding(.horizontal, 5) // Add horizontal padding
        // Background is handled in SidebarView for selection/hover
        // Remove direct background modifier here
        // .background(...) 
        .animation(.easeInOut(duration: 0.1), value: isHovering) // Animate hover (indirectly via parent bg)
        .animation(.easeInOut(duration: 0.15), value: isSelected) // Animate selection (indirectly via parent bg)
    }
    
    // Helper to convert hex to Color - REMOVED (use global)
} 