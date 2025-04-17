import SwiftUI

// Helper View for Folder Rows
struct FolderRow: View {
    let folder: Folder
    let isHovering: Bool // Add hover state
    // Remove EnvironmentObject if not directly needed

    var body: some View {
        HStack(spacing: 6) { // Adjust spacing
            // Use filled folder icon
            Image(systemName: "folder.fill")
                .foregroundStyle(colorFromHex(folder.colorHex) ?? .secondary) // Use folder color or secondary
                .font(.body) // Ensure consistent icon size
                .frame(width: 20, alignment: .center) // Give icon fixed width

            Text(folder.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
            
            Spacer()
            // Optional: Show count of items inside?
        }
        .padding(.vertical, 6) // Add more vertical padding
        .padding(.horizontal, 5) // Add horizontal padding
        .background(isHovering ? Color.gray.opacity(0.1) : Color.clear) // Add hover background
        .cornerRadius(4) // Add slight corner radius for hover background
        .animation(.easeInOut(duration: 0.1), value: isHovering) // Animate hover
    }
} 