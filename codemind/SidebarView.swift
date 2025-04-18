import SwiftUI

// MARK: - Sidebar Component
struct SidebarView: View {
    @Binding var selectedFilter: SidebarFilter // Use the simplified enum
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

    // State to store the dynamically read row height
    @State private var currentRowHeight: CGFloat = 44 // Default height

    // State to trigger swipe action reset
    @State private var swipeResetTrigger: Bool = false

    // Enum for folder actions (Internal to Sidebar)
    enum FolderActionType {
        case newRootFolder, newSubfolder, renameFolder
    }

    @EnvironmentObject var dataManager: DataManager
    @Environment(\.colorScheme) var colorScheme // Get color scheme
    // @Environment(\.openSettings) var openSettings // <-- REMOVED: Rely on standard Cmd+,

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

                // REMOVED Settings button
                /*
                // Group buttons for better spacing control if needed
                HStack(spacing: 15) { // Increase spacing
                    Button { openSettings() } label: {
                         Image(systemName: "gearshape.fill")
                             .font(.title3) // Consistent font size
                     }
                    .buttonStyle(.plain)
                    .help("Settings")
                    .contentShape(Rectangle()) // Ensure tappable area
                }
                */
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
                            Text(colorName(from: selectedColor))
                                .font(.caption)
                                .lineLimit(1)
                        } else {
                             Image(systemName: "paintpalette")
                                 .imageScale(.small) // Adjust icon size
                             Text("Color")
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal, 10) // More padding
                    .padding(.vertical, 5)   // More padding
                    .background(colorScheme == .dark ? Color.gray.opacity(0.25) : Color.gray.opacity(0.15), in: Capsule()) // Use gray background
                    .foregroundStyle(.primary) // Ensure text is readable
                }
                .menuStyle(.borderlessButton)
                // REMOVED: .frame(width: 85) // Let it size intrinsically

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
            }
            .padding(.horizontal)
            .padding(.vertical, 8) // Add vertical padding

            // --- Content List --- (Height reading added)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    outlineGroupContent(parentId: nil, level: 0)
                }
                .padding(.horizontal, 5)
            }
            .background(.clear)
            .scrollContentBackground(.hidden)
            .padding(.top, 0)

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
            "Delete Folder '\(folderToDelete?.name ?? "")'",
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
        Button {
            selectedColorHexFilter = nil
            swipeResetTrigger.toggle() // Reset swipes if filter changes
        } label: {
            Label("All Colors", systemImage: selectedColorHexFilter == nil ? "checkmark.circle.fill" : "circle")
        }
        Divider()
        ForEach(availableColors.compactMap { $0 }, id: \.self) { colorHex in
             Button {
                 selectedColorHexFilter = colorHex
                 swipeResetTrigger.toggle() // Reset swipes if filter changes
             } label: {
                 HStack {
                     Circle().fill(colorFromHex(colorHex)).frame(width: 12, height: 12)
                     Text(colorName(from: colorHex))
                     Spacer()
                     if selectedColorHexFilter == colorHex {
                         Image(systemName: "checkmark")
                             .foregroundColor(.accentColor) // Ensure checkmark is visible
                     }
                 }
             }
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
    // NOTE: Ideally, this logic moves to DataManager
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

    // Recursive View Builder (Height reading added)
    // NOTE: Filtering logic ideally moves to DataManager
    @ViewBuilder
    private func outlineGroupContent(parentId: UUID?, level: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            let indent = CGFloat(level * 15)

            // --- Folders ---
            // Call DataManager for filtered folders (Requires implementation in DataManager)
            let foldersToShow = dataManager.filteredFolders(parentId: parentId, currentFilter: selectedFilter, colorHexFilter: selectedColorHexFilter)
            /* // OLD INLINE FILTERING - Moved to DataManager
            let allFoldersAtLevel = parentId == nil ? dataManager.rootFolders : dataManager.subfolders(in: parentId!)
            let foldersToShow = allFoldersAtLevel.filter { folder in
                // Filter by favorite status if needed
                let favoriteCheck = (selectedFilter == .favorites) ? dataManager.folderContainsFavorites(folderId: folder.id) : true
                // Filter by color if needed
                let colorCheck = (selectedColorHexFilter == nil) || (folder.colorHex == selectedColorHexFilter)
                return favoriteCheck && colorCheck
            }
            */
            
            ForEach(foldersToShow) { folder in
                DisclosureGroup {
                    outlineGroupContent(parentId: folder.id, level: level + 1)
                } label: {
                    FolderRow(folder: folder, isHovering: hoverId == "folder-\(folder.id.uuidString)")
                        .padding(.leading, indent)
                        .contentShape(Rectangle())
                        // Read row height using background GeometryReader
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(key: RowHeightPreferenceKey.self, value: proxy.size.height)
                            }
                        )
                }
                .accentColor(.secondary)
                // Capture row height preference
                .onPreferenceChange(RowHeightPreferenceKey.self) { height in
                    // Only update if height is different and positive
                    if height > 0 && self.currentRowHeight != height {
                         self.currentRowHeight = height
                    }
                }
                .contextMenu { folderContextMenu(for: folder) }
                .onHover { isHovering in hoverId = isHovering ? "folder-\(folder.id.uuidString)" : nil }
                // Pass the read height to swipeActions
                .swipeActions(
                    leading: folderLeadingSwipeActions(for: folder),
                    trailing: folderTrailingSwipeActions(for: folder),
                    allowsFullSwipe: true,
                    rowHeight: currentRowHeight,
                    resetTrigger: $swipeResetTrigger
                )
            }

            // --- Sessions ---
            // Call DataManager for filtered sessions (Requires implementation in DataManager)
            let sessionsToShow = dataManager.filteredSessions(parentId: parentId, currentFilter: selectedFilter, colorHexFilter: selectedColorHexFilter)
            /* // OLD INLINE FILTERING - Moved to DataManager
            let currentSessions = parentId == nil ? dataManager.rootSessions : dataManager.sessions(in: parentId!)
            let sessionsToShow = currentSessions.filter { shouldDisplay(session: $0) }
            */
            
            ForEach(sessionsToShow) { session in
                 let sessionIdString = "session-\(session.id.uuidString)"
                 SessionRow(
                     session: session,
                     isSelected: dataManager.activeSessionId == session.id,
                     isHovering: hoverId == sessionIdString
                 )
                     .padding(.leading, indent + 5)
                     .background(
                         RoundedRectangle(cornerRadius: 5)
                             .fill(dataManager.activeSessionId == session.id ? Color.accentColor.opacity(0.2) : (hoverId == sessionIdString ? Color.gray.opacity(0.1) : Color.clear))
                     )
                     .contentShape(Rectangle())
                     // Read row height using background GeometryReader
                     .background(
                         GeometryReader { proxy in
                             Color.clear.preference(key: RowHeightPreferenceKey.self, value: proxy.size.height)
                         }
                     )
                     // Capture row height preference
                    .onPreferenceChange(RowHeightPreferenceKey.self) { height in
                         // Only update if height is different and positive
                        if height > 0 && self.currentRowHeight != height {
                             self.currentRowHeight = height
                        }
                     }
                     .contextMenu { sessionContextMenu(for: session) }
                     .onTapGesture {
                          dataManager.activeSessionId = session.id
                          swipeResetTrigger.toggle() // Reset other swipes when selecting a new row
                     }
                     .onHover { isHovering in hoverId = isHovering ? sessionIdString : nil }
                      // Pass the read height to swipeActions
                     .swipeActions(
                         leading: sessionLeadingSwipeActions(for: session),
                         trailing: sessionTrailingSwipeActions(for: session),
                         allowsFullSwipe: true,
                         rowHeight: currentRowHeight,
                         resetTrigger: $swipeResetTrigger
                     )
            }
        }
    }
    
    // NOTE: shouldDisplay is no longer used directly for filtering the main list,
    // as that logic is now in DataManager.filteredSessions.
    // It might still be useful elsewhere, or can be removed if not needed.
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
        
        Menu { // Move To Folder (Use the extracted menu content)
            sessionMoveToFolderMenuContent(for: session)
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
            Button { // WRAPPED IN TASK
                Task { 
                    await MainActor.run { dataManager.moveFolder(folderId: folder.id, newParentId: nil) } 
                    swipeResetTrigger.toggle() // Reset swipe on completion
                }
            } label: {
                Label("Root Level", systemImage: folder.parentId == nil ? "checkmark.circle.fill" : "circle")
            }
            
            Divider()
            
            // List available folders (excluding self and descendants)
            // NOTE: Assumes `isDescendant` is implemented in DataManager
            ForEach(dataManager.folders.filter { $0.id != folder.id && !dataManager.isDescendant(folderId: $0.id, of: folder.id) }.sorted { $0.name < $1.name }) { potentialParent in
                Button { // WRAPPED IN TASK
                    Task { 
                        await MainActor.run { dataManager.moveFolder(folderId: folder.id, newParentId: potentialParent.id) } 
                        swipeResetTrigger.toggle() // Reset swipe on completion
                    }
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

    // Reusable Color Submenu Content (Ensured Task wrapping)
    @ViewBuilder
    private func colorSubMenuContent(for item: any Identifiable & HasColor) -> some View {
        Button { // Set color to None
             Task { // Wrap in Task
                 await MainActor.run {
                     if let session = item as? ChatSession {
                         dataManager.updateSessionColor(withId: session.id, colorHex: nil)
                     } else if let folder = item as? Folder {
                         dataManager.updateFolderColor(withId: folder.id, colorHex: nil)
                     }
                 }
                 swipeResetTrigger.toggle() // Reset swipe on completion
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
            Button { // Set color to specific value
                 Task { // Wrap in Task
                     await MainActor.run {
                         if let session = item as? ChatSession {
                             dataManager.updateSessionColor(withId: session.id, colorHex: colorHexValue)
                         } else if let folder = item as? Folder {
                             dataManager.updateFolderColor(withId: folder.id, colorHex: colorHexValue)
                         }
                     }
                     swipeResetTrigger.toggle() // Reset swipe on completion
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

    // Extracted Session Move To Folder Menu Content (Ensured Task wrapping)
    @ViewBuilder
    private func sessionMoveToFolderMenuContent(for session: ChatSession) -> some View {
        Button { // Move to Root
            Task { // WRAPPED IN TASK
                 await MainActor.run { dataManager.moveSessionToFolder(sessionId: session.id, newParentId: nil) }
                 swipeResetTrigger.toggle() // Reset swipe on completion
            }
        } label: {
            Label("Root Level", systemImage: session.folderId == nil ? "checkmark.circle.fill" : "circle")
        }
        Divider()
        ForEach(dataManager.folders.sorted { $0.name < $1.name }) { folder in
            Button { // Move to specific folder
                Task { // WRAPPED IN TASK
                     await MainActor.run { dataManager.moveSessionToFolder(sessionId: session.id, newParentId: folder.id) }
                     swipeResetTrigger.toggle() // Reset swipe on completion
                }
            } label: {
                Label {
                    Text(folder.name)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: session.folderId == folder.id ? "checkmark" : "folder")
                }
            }
        }
    }

    // MARK: - Swipe Action Helper Functions

    private func folderLeadingSwipeActions(for folder: Folder) -> [SwipeAction] {
        return [
            // Set Color Action (Using Menu)
            SwipeAction(tint: .purple, icon: "paintpalette.fill", label: "Color") {
                // Content is built by the ViewBuilder, actions inside are already wrapped in Task
                colorSubMenuContent(for: folder)
            },
            // Rename Action
            SwipeAction(tint: .blue, icon: "pencil", label: "Rename") {
                setupFolderAlert(action: .renameFolder, folder: folder)
                swipeResetTrigger.toggle() // Ensure reset after triggering alert
            }
        ]
    }

    private func folderTrailingSwipeActions(for folder: Folder) -> [SwipeAction] {
        return [
            // New Subfolder Action
            SwipeAction(tint: .gray, icon: "folder.badge.plus", label: "New") {
                setupFolderAlert(action: .newSubfolder, folder: folder)
                swipeResetTrigger.toggle() // Ensure reset after triggering alert
            },
            // Delete Action
            SwipeAction(tint: .red, icon: "trash.fill", label: "Delete") {
                folderToDelete = folder
                showingDeleteFolderConfirm = true
                // Confirmation dialog handles its own logic, reset happens if deleted
            }
        ]
    }

    private func sessionLeadingSwipeActions(for session: ChatSession) -> [SwipeAction] {
        return [
            // Set Color Action (Using Menu)
            SwipeAction(tint: .purple, icon: "paintpalette.fill", label: "Color") {
                 // Content is built by the ViewBuilder, actions inside are already wrapped in Task
                colorSubMenuContent(for: session)
            },
            // Move To Folder Action (Using Menu)
            SwipeAction(tint: .gray, icon: "folder.fill", label: "Move") {
                 // Content is built by the ViewBuilder, actions inside are already wrapped in Task
                sessionMoveToFolderMenuContent(for: session)
            }
        ]
    }

    private func sessionTrailingSwipeActions(for session: ChatSession) -> [SwipeAction] {
        return [
            // Toggle Favorite Action
            SwipeAction(tint: session.isFavorite ? .orange : .gray, icon: session.isFavorite ? "star.slash.fill" : "star.fill", label: session.isFavorite ? "Unfav" : "Favorite") { // Adjusted tint based on state
                Task { 
                    await MainActor.run { dataManager.toggleFavorite(withId: session.id) } 
                    swipeResetTrigger.toggle() // Reset swipe on completion
                }
            },
            // Delete Action
            SwipeAction(tint: .red, icon: "trash.fill", label: "Delete") {
                Task { 
                    await MainActor.run { dataManager.deleteSession(withId: session.id) } 
                    // No need to reset swipe here, row will disappear
                }
            }
        ]
    }
}

