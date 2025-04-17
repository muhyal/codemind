import SwiftUI

// MARK: - Sidebar Component
struct SidebarView: View {
    @Binding var selectedFilter: SidebarFilter // Use the simplified enum
    @Binding var showingSettings: Bool
    @Binding var showingEditAlert: Bool // For triggering alert in ModalView
    @Binding var sessionToEdit: ChatSession? // For triggering alert in ModalView
    @Binding var newSessionTitle: String // For triggering alert in ModalView
    
    // State for the selected color filter (Internal to Sidebar)
    @State private var selectedColorHexFilter: String? = nil

    // State for New/Rename Folder Alert (Internal to Sidebar)
    @State private var showingFolderAlert: Bool = false
    @State private var folderAlertTitle: String = ""
    @State private var folderAlertMessage: String = ""
    @State private var folderAlertTextFieldLabel: String = ""
    @State private var folderNameInput: String = ""
    @State private var targetFolderIdForAction: UUID? = nil // For rename or new subfolder parent
    @State private var folderActionType: FolderActionType = .newRootFolder // To distinguish alert actions
    
    // State for Delete Folder Confirmation (Internal to Sidebar)
    @State private var showingDeleteFolderConfirm: Bool = false
    @State private var folderToDelete: Folder? = nil
    
    // State for hover effects
    @State private var hoverId: String? = nil

    // Enum for folder actions (Internal to Sidebar)
    enum FolderActionType {
        case newRootFolder, newSubfolder, renameFolder
    }

    @EnvironmentObject var dataManager: DataManager
    @Environment(\.colorScheme) var colorScheme // Get color scheme

    // Predefined colors (Used internally by Sidebar)
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
    
    var body: some View {
        VStack(spacing: 0) {
            // --- Header ---
            HStack {
                Text("🧠 CodeMind Chats")
                    .font(.title2.bold()) // Bolder title

                Spacer()

                // Group buttons for better spacing control if needed
                HStack(spacing: 15) { // Increase spacing
                    Button { showingSettings = true } label: {
                         Image(systemName: "gearshape.fill")
                             .font(.title3) // Consistent font size
                     }
                    .buttonStyle(.plain)
                    .help("Settings")
                    .contentShape(Rectangle()) // Ensure tappable area
                }
            }
            .padding(.horizontal)
            .padding(.top, 10) // Add top padding
            .padding(.bottom, 8) // Adjust bottom padding

            Divider() // Add a divider below header

            // --- Filter Area ---
            HStack(spacing: 15) { // Increase spacing
                Picker("", selection: $selectedFilter) {
                    ForEach(SidebarFilter.allCases) { filter in
                        switch filter {
                        case .all:
                            Image(systemName: "list.bullet").tag(filter).help("All Chats")
                        case .favorites:
                            Image(systemName: "star.fill").tag(filter).help("Favorites")
                        }
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 150) // Adjust width for icons

                // Color Filter Menu Button - Improved Look
                Menu {
                    colorFilterMenuContent() // Extracted content
                } label: {
                    HStack(spacing: 4) {
                        if let selectedColor = selectedColorHexFilter {
                            Circle().fill(colorFromHex(selectedColor)).frame(width: 12, height: 12) // Slightly larger dot
                            Text(colorName(from: selectedColor)) // <-- Re-added color name
                                .font(.caption)
                                .lineLimit(1)
                        } else {
                             Image(systemName: "paintpalette")
                                 .imageScale(.small) // Adjust icon size
                             Text("Color") // <-- Re-added "Color" text for non-selected state
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal, 10) // More padding
                    .padding(.vertical, 5)   // More padding
                    .background(colorScheme == .dark ? Color.gray.opacity(0.25) : Color.gray.opacity(0.15), in: Capsule()) // Use gray background
                    .foregroundStyle(.primary) // Ensure text is readable
                }
                .menuStyle(.borderlessButton)
                .frame(width: 85) // Adjust width slightly

                Spacer() // Pushes filters and color button left
                
                // MOVED New Folder and New Chat buttons here
                Button { setupFolderAlert(action: .newRootFolder) } label: {
                     Image(systemName: "folder.badge.plus")
                          .font(.title3)
                 }
                .buttonStyle(.plain)
                .help("New Folder")
                .contentShape(Rectangle())

                Button { dataManager.createNewSession(activate: true) } label: {
                     Image(systemName: "plus.circle.fill")
                          .font(.title3)
                 }
                .buttonStyle(.plain)
                .help("New Chat")
                .contentShape(Rectangle())

                // Removed Spacer() from here as buttons are now at the end
            }
            .padding(.horizontal)
            .padding(.vertical, 8) // Add vertical padding

            // --- Content List ---
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) { // Add small spacing between items
                    outlineGroupContent(parentId: nil, level: 0) // Start with root level, pass indentation level
                }
                .padding(.horizontal, 5) // Add some horizontal padding to the stack
            }
            .background(.clear)
            .scrollContentBackground(.hidden)
            .padding(.top, 0) // Remove top padding from ScrollView

            // --- Footer ---
            Divider() // Add divider above footer
            HStack {
                 Spacer()
                 Text("CodeMind v\(appVersion())")
                     .font(.footnote)
                     .foregroundColor(.secondary)
                 Spacer()
             }
             .padding(.vertical, 8) // Add padding to footer
        }
        // --- Alerts and Dialogs (Keep existing functionality) ---
        .alert(folderAlertTitle, isPresented: $showingFolderAlert) {
             TextField(folderAlertTextFieldLabel, text: $folderNameInput)
             Button("Save") {
                 Task { await handleFolderAction() }
             }
             Button("Cancel", role: .cancel) { }
        } message: { Text(folderAlertMessage) }
        .confirmationDialog(
            "Delete Folder '\(folderToDelete?.name ?? "")'?",
            isPresented: $showingDeleteFolderConfirm,
            presenting: folderToDelete
        ) { folder in folderDeleteConfirmationActions(folder: folder) }
        message: { _ in Text("Deleting the folder cannot be undone. Choose how to handle its contents.") }
        .navigationSplitViewColumnWidth(min: 220, ideal: 250) // Adjusted width
    }
    
    // --- Helper Functions ---

    // Extracted Color Filter Menu Content
    @ViewBuilder
    private func colorFilterMenuContent() -> some View {
        Button { selectedColorHexFilter = nil } label: {
             Label("All Colors", systemImage: selectedColorHexFilter == nil ? "checkmark.circle.fill" : "circle")
        }
        Divider()
        ForEach(availableColors.compactMap { $0 }, id: \.self) { colorHex in
             Button { selectedColorHexFilter = colorHex } label: {
                 // Use Label to combine Circle and Text
                 Label {
                     Text(colorName(from: colorHex))
                 } icon: {
                     Circle().fill(colorFromHex(colorHex)).frame(width: 12, height: 12)
                 }
                 // Add Checkmark separately if needed, ensuring Spacer pushes it right
                 HStack {
                     Spacer()
                     if selectedColorHexFilter == colorHex {
                         Image(systemName: "checkmark")
                     }
                 }
             }
             // Removed the explicit HStack wrapper as Label handles layout, but need to ensure checkmark is positioned
             // This might require further adjustment if checkmark isn't right-aligned
        }
    }
    
    // Helper to setup folder alert state
    private func setupFolderAlert(action: FolderActionType, folder: Folder? = nil) {
        folderActionType = action
        targetFolderIdForAction = nil // Reset target ID initially
        switch action {
        case .newRootFolder:
            folderAlertTitle = "New Folder"
            folderAlertMessage = "Enter a name for the new root folder."
            folderAlertTextFieldLabel = "Folder Name"
            folderNameInput = ""
        case .newSubfolder:
            guard let parentFolder = folder else { return }
            folderAlertTitle = "New Subfolder"
            folderAlertMessage = "Enter a name for the new subfolder inside '\(parentFolder.name)'."
            folderAlertTextFieldLabel = "Subfolder Name"
            folderNameInput = ""
            targetFolderIdForAction = parentFolder.id // Set parent
        case .renameFolder:
            guard let folderToRename = folder else { return }
            folderAlertTitle = "Rename Folder"
            folderAlertMessage = "Enter a new name for the folder '\(folderToRename.name)'."
            folderAlertTextFieldLabel = "New Name"
            folderNameInput = folderToRename.name // Pre-fill
            targetFolderIdForAction = folderToRename.id // Set target
        }
        showingFolderAlert = true
    }

    // Helper to handle folder alert save action
    private func handleFolderAction() async {
         switch folderActionType {
         case .newRootFolder:
             await MainActor.run { dataManager.createFolder(name: folderNameInput, parentId: nil) }
         case .newSubfolder:
             await MainActor.run { dataManager.createFolder(name: folderNameInput, parentId: targetFolderIdForAction) }
         case .renameFolder:
             if let folderId = targetFolderIdForAction {
                 await MainActor.run { dataManager.renameFolder(withId: folderId, newName: folderNameInput) }
             }
         }
    }

    // Extracted Folder Delete Confirmation Actions
    @ViewBuilder
    private func folderDeleteConfirmationActions(folder: Folder) -> some View {
        Button("Delete Folder and All Contents", role: .destructive) {
             Task { await MainActor.run { dataManager.deleteFolder(withId: folder.id, recursive: true) } }
        }
        Button("Delete Folder Only (Move Contents to Root)") {
             Task { await MainActor.run { dataManager.deleteFolder(withId: folder.id, recursive: false) } }
        }
        Button("Cancel", role: .cancel) { }
    }

    // Recursive View Builder with Indentation Level
    @ViewBuilder
    private func outlineGroupContent(parentId: UUID?, level: Int) -> some View {
        let indent = CGFloat(level * 15) // Indentation amount per level

        // Wrap the return type in AnyView to help with type inference
        AnyView(
            VStack(alignment: .leading, spacing: 0) {
                // --- Folders ---
                let allFoldersAtLevel = parentId == nil ? dataManager.rootFolders : dataManager.subfolders(in: parentId!)
                let foldersToShow = allFoldersAtLevel.filter { folder in
                    (selectedFilter == .favorites) ? dataManager.folderContainsFavorites(folderId: folder.id) : true
                }
                
                ForEach(foldersToShow) { folder in
                    DisclosureGroup {
                        outlineGroupContent(parentId: folder.id, level: level + 1) // Increase level for children
                    } label: {
                        FolderRow(folder: folder, isHovering: hoverId == "folder-\(folder.id.uuidString)")
                            .padding(.leading, indent) // Apply indentation
                            .contentShape(Rectangle()) // Make whole row tappable for hover/context menu
                    }
                    .accentColor(.secondary) // Change disclosure indicator color
                    .contextMenu { folderContextMenu(for: folder) }
                    .onHover { isHovering in hoverId = isHovering ? "folder-\(folder.id.uuidString)" : nil }
                }

                // --- Sessions ---
                let currentSessions = parentId == nil ? dataManager.rootSessions : dataManager.sessions(in: parentId!)
                let sessionsToShow = currentSessions.filter { shouldDisplay(session: $0) }

                ForEach(sessionsToShow) { session in
                     let sessionIdString = "session-\(session.id.uuidString)"
                     SessionRow(
                         session: session,
                         isSelected: dataManager.activeSessionId == session.id,
                         isHovering: hoverId == sessionIdString
                     )
                         .padding(.leading, indent + 5) // Apply indentation + slight extra for session
                         .background( // Add background for selection/hover
                             RoundedRectangle(cornerRadius: 5)
                                 .fill(dataManager.activeSessionId == session.id ? Color.accentColor.opacity(0.2) : (hoverId == sessionIdString ? Color.gray.opacity(0.1) : Color.clear))
                         )
                         .contentShape(Rectangle()) // Make whole row tappable
                         .contextMenu { sessionContextMenu(for: session) }
                         .onTapGesture { dataManager.activeSessionId = session.id }
                         .onHover { isHovering in hoverId = isHovering ? sessionIdString : nil }
                }
            }
        )
    }
    
    // Keep shouldDisplay helper
    private func shouldDisplay(session: ChatSession) -> Bool {
        if selectedFilter == .favorites && !session.isFavorite { return false }
        if let colorFilter = selectedColorHexFilter, session.colorHex != colorFilter { return false }
        return true
    }
    
    // MARK: - Context Menus (Re-adding Folder Context Menu)

    // Reusable Context Menu for Sessions
    @ViewBuilder
    private func sessionContextMenu(for session: ChatSession) -> some View {
        Button { /* Edit Title */
            sessionToEdit = session
            newSessionTitle = session.title
            showingEditAlert = true
        } label: { Label("Edit Title", systemImage: "pencil") }
        
        Menu { // Move To Folder
            Button {
                Task { await MainActor.run { dataManager.moveSessionToFolder(sessionId: session.id, newParentId: nil as UUID?) } }
            } label: {
                Label("Root Level", systemImage: session.folderId == nil ? "checkmark.circle.fill" : "circle")
            }
            Divider()
            ForEach(dataManager.folders.sorted { $0.name < $1.name }) { folder in
                Button {
                    Task { await MainActor.run { dataManager.moveSessionToFolder(sessionId: session.id, newParentId: folder.id) } }
                } label: {
                    Label { Text(folder.name) } icon: { Image(systemName: session.folderId == folder.id ? "checkmark" : "folder") }
                }
            }
        } label: { Label("Move To...", systemImage: "folder") }
        
        Menu { colorSubMenuContent(for: session) } label: { Label("Set Color", systemImage: "paintpalette") }
        
        Button { Task { await MainActor.run { dataManager.toggleFavorite(withId: session.id) } } } label: { Label(session.isFavorite ? "Unfavorite" : "Favorite", systemImage: session.isFavorite ? "star.slash.fill" : "star.fill") }
        Button { /* Copy Title */
             let pasteboard = NSPasteboard.general
             pasteboard.clearContents()
             pasteboard.setString(session.title, forType: .string)
        } label: { Label("Copy Title", systemImage: "doc.on.doc") }
        Divider()
        Button(role: .destructive) { Task { await MainActor.run { dataManager.deleteSession(withId: session.id) } } } label: { Label("Delete Chat", systemImage: "trash.fill") }
    }
    
    // Reusable Context Menu for Folders (Re-added)
    @ViewBuilder
    private func folderContextMenu(for folder: Folder) -> some View {
        Button { 
            // Setup alert for renaming this folder
            setupFolderAlert(action: .renameFolder, folder: folder)
        } label: { Label("Rename", systemImage: "pencil") }
        
        Button { 
            // Setup alert for creating a subfolder inside this folder
            setupFolderAlert(action: .newSubfolder, folder: folder)
        } label: { Label("New Subfolder", systemImage: "folder.badge.plus") }
        
        // Move Folder Menu
        Menu {
            // Option to move to Root
            Button {
                Task { await MainActor.run { dataManager.moveFolder(folderId: folder.id, newParentId: nil as UUID?) } }
            } label: {
                Label("Root Level", systemImage: folder.parentId == nil ? "checkmark.circle.fill" : "circle")
            }
            
            Divider()
            
            // List available folders (excluding self and descendants - simplified filter)
            ForEach(dataManager.folders.filter { $0.id != folder.id && $0.parentId != folder.id }.sorted { $0.name < $1.name }) { potentialParent in
                Button {
                    Task { await MainActor.run { dataManager.moveFolder(folderId: folder.id, newParentId: potentialParent.id) } }
                } label: {
                    Label { Text(potentialParent.name) } icon: { Image(systemName: folder.parentId == potentialParent.id ? "checkmark" : "folder") }
                }
            }
        } label: { Label("Move To...", systemImage: "folder") }
        
        // Use the reusable color submenu for folders
        Menu { colorSubMenuContent(for: folder) } label: { Label("Set Color", systemImage: "paintpalette") }
        
        Divider()
        Button(role: .destructive) { 
            // Trigger the confirmation dialog
            folderToDelete = folder
            showingDeleteFolderConfirm = true
        } label: { Label("Delete Folder...", systemImage: "trash.fill") }
    }

    // Reusable Color Submenu Content
    @ViewBuilder
    private func colorSubMenuContent(for item: any Identifiable & HasColor) -> some View {
        Button {
             Task { // Wrap in Task
                 if let session = item as? ChatSession {
                     await MainActor.run { dataManager.updateSessionColor(withId: session.id, colorHex: nil) }
                 } else if let folder = item as? Folder {
                     await MainActor.run { dataManager.updateFolderColor(withId: folder.id, colorHex: nil) }
                 }
             }
        } label: {
            HStack {
                Image(systemName: "circle.slash")
                Text("None")
                Spacer()
                if item.colorHex == nil { Image(systemName: "checkmark") }
            }
        }
        
        Divider()
        
        ForEach(availableColors.compactMap { $0 }, id: \.self) { colorHexValue in
            Button {
                 Task { // Wrap in Task
                     if let session = item as? ChatSession {
                         await MainActor.run { dataManager.updateSessionColor(withId: session.id, colorHex: colorHexValue) }
                     } else if let folder = item as? Folder {
                         await MainActor.run { dataManager.updateFolderColor(withId: folder.id, colorHex: colorHexValue) }
                     }
                 }
            } label: {
                HStack {
                    Circle().fill(colorFromHex(colorHexValue)).frame(width: 12, height: 12)
                    Text(colorName(from: colorHexValue))
                    Spacer()
                    if item.colorHex == colorHexValue { Image(systemName: "checkmark") }
                }
            }
        }
    }
}

// MARK: - Row Views - REMOVE DUPLICATES

// // View for displaying a single Session row
// struct SessionRow: View {
//     let session: ChatSession
//     let isSelected: Bool
//     
//     var body: some View {
//         HStack {
//             // Color indicator (optional)
//             if let hex = session.colorHex, let color = Color(hex: hex) {
//                 Circle().fill(color).frame(width: 8, height: 8)
//             }
//             Text(session.title)
//                 .lineLimit(1)
//                 .truncationMode(.tail)
//             Spacer()
//             if session.isFavorite {
//                 Image(systemName: "star.fill")
//                     .foregroundColor(.yellow)
//                     .font(.caption) // Make star smaller
//             }
//         }
//         .padding(.vertical, 4) // Adjust padding for better spacing
//     }
// }
//
// // View for displaying a Folder row (used in DisclosureGroup label)
// struct FolderRow: View {
//     let folder: Folder
//
//     var body: some View {
//         HStack {
//             // Color indicator (optional)
//             if let hex = folder.colorHex, let color = Color(hex: hex) {
//                 Circle().fill(color).frame(width: 8, height: 8)
//             }
//             Image(systemName: "folder.fill") // Use filled folder icon
//                 .foregroundColor(.secondary) // Slightly dimmer color
//             Text(folder.name)
//                 .lineLimit(1)
//                 .truncationMode(.tail)
//             Spacer()
//         }
//         .padding(.vertical, 4) // Consistent padding with SessionRow
//     }
// }

// MARK: - Preview
// ... existing code ... 