import SwiftUI

// Preference Key for Row Height
struct RowHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue()) // Use the maximum height reported
    }
}

// A ViewModifier that manages swipe gestures and action buttons on a list item.
struct SwipeActionsModifier: ViewModifier {
    // MARK: - Constants
    private static let minSwipeDistance: CGFloat = 30
    private static let dragConfirmationThreshold: CGFloat = 10
    private static let fullSwipeActivationExtraOffset: CGFloat = 50 // Extra distance to pull to activate full swipe
    private static let actionTapDelay: Double = 0.25 // Delay before executing action after tap
    private static let resetAnimationDelay: Double = 0.1 // Delay before resetting offset after full swipe action
    private static let defaultRowHeight: CGFloat = 44 // Default height if invalid provided

    // MARK: - Properties
    let leadingActions: [SwipeAction]
    let trailingActions: [SwipeAction]
    let allowsFullSwipe: Bool
    let rowHeight: CGFloat
    @Binding var resetTrigger: Bool

    private let maxLeadingOffset: CGFloat
    private let maxTrailingOffset: CGFloat

    // MARK: - State
    @State private var hOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var activeActionType: ActionType? = nil
    @State private var dragDirectionConfirmed: Bool = false
    @State private var triggeredActionClosure: (() -> Void)? = nil // Action closure triggered by full swipe

    private enum ActionType { case leading, trailing }

    init(leading: [SwipeAction] = [], trailing: [SwipeAction] = [], allowsFullSwipe: Bool = false, rowHeight: CGFloat, resetTrigger: Binding<Bool>) {
        self.leadingActions = leading
        self.trailingActions = trailing
        self.maxLeadingOffset = CGFloat(leading.reduce(0) { $0 + $1.width })
        self.maxTrailingOffset = CGFloat(trailing.reduce(0) { $0 + $1.width })
        self.allowsFullSwipe = allowsFullSwipe
        self.rowHeight = rowHeight > 0 ? rowHeight : SwipeActionsModifier.defaultRowHeight
        self._resetTrigger = resetTrigger
    }

    // MARK: - Body
    func body(content: Content) -> some View {
        ZStack(alignment: .leading) {
            // Background Actions
            backgroundActionsView()

            // Main Content
            content
                .offset(x: hOffset)
                .contentShape(Rectangle()) // Ensure the whole area is draggable
                .gesture(dragGesture())
                .clipped() // Clip the content itself if it exceeds bounds during offset
                .allowsHitTesting(hOffset == 0) // Allow interaction only when not swiped
        }
        .clipped() // Clip the entire container
        .onChange(of: isDragging) { newValue in
             handleDragEnd(isDraggingEnded: !newValue)
        }
        .onChange(of: resetTrigger) { _ in
             handleResetTrigger()
        }
    }

    // MARK: - Subviews
    @ViewBuilder
    private func backgroundActionsView() -> some View {
        // Leading Actions Container
        HStack(spacing: 0) {
            ForEach(leadingActions) { action in
                actionView(action: action, alignment: .leading)
            }
            Spacer() // Pushes actions to the leading edge
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(hOffset > 0 ? 1 : 0) // Show only when swiping right

        // Trailing Actions Container
        HStack(spacing: 0) {
            Spacer() // Pushes actions to the trailing edge
            ForEach(trailingActions) { action in
                actionView(action: action, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .opacity(hOffset < 0 ? 1 : 0) // Show only when swiping left
    }

    @ViewBuilder
    private func actionView(action: SwipeAction, alignment: HorizontalAlignment) -> some View {
        // Base visual representation (icon, label)
        let label = VStack(spacing: 4) {
            Image(systemName: action.icon)
                .font(action.label == nil ? .title2 : .body) // Adjust icon size if no label
            if let labelText = action.label {
                Text(labelText)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal)
        .frame(width: action.width, height: rowHeight)
        .background(action.tint)
        .foregroundColor(.white)
        .contentShape(Rectangle()) // Make the action area tappable/hoverable
        .overlay(fullSwipeIndicator(action: action, alignment: alignment)) // Add full swipe indicator
        // .onHover { isHovering in // Optional: Add hover effect for macOS
        //     // Apply visual changes based on isHovering
        // }

        // Wrap in Menu if menu content exists, otherwise provide tap gesture
        if let menuBuilder = action.menuContent {
            Menu {
                menuBuilder()
            } label: {
                label
            }
            .menuStyle(.borderlessButton) // Use borderless style for seamless background
            .frame(width: action.width, height: rowHeight)
            .contentShape(Rectangle()) // Ensure menu label area is interactive
        } else {
            label
                .onTapGesture {
                    if let tapAct = action.action {
                         handleActionTap(actionClosure: tapAct)
                    }
                }
        }
    }

    // Visual indicator for full swipe possibility
    @ViewBuilder
    private func fullSwipeIndicator(action: SwipeAction, alignment: HorizontalAlignment) -> some View {
        // Show indicator only for the first action if full swipe is allowed
        let isFirstAction = (alignment == .leading && action.id == leadingActions.first?.id) ||
                            (alignment == .trailing && action.id == trailingActions.first?.id)

        if allowsFullSwipe && isFirstAction {
            let requiredOffset = (alignment == .leading ? maxLeadingOffset : maxTrailingOffset) + SwipeActionsModifier.fullSwipeActivationExtraOffset / 2 // Show indicator slightly before full activation

            Image(systemName: "arrowshape.left.fill")
                 .rotationEffect(.degrees(alignment == .leading ? 180 : 0))
                 .font(.caption)
                 .foregroundColor(.white.opacity(0.7))
                 .padding(alignment == .leading ? .trailing : .leading, 10)
                 // Show when dragged beyond the normal max offset
                 .opacity(abs(hOffset) > requiredOffset ? 1 : 0)
                 .animation(.easeInOut, value: hOffset) // Animate the indicator appearance
                 .frame(maxWidth: .infinity, alignment: alignment == .leading ? .trailing : .leading) // Position indicator correctly
        }
    }


    // MARK: - Gesture Handling
    private func dragGesture() -> some Gesture {
        DragGesture(minimumDistance: 0) // Start immediately
            .onChanged { value in
                if !isDragging { // First change event
                    isDragging = true
                    // Reset state for the new drag
                    triggeredActionClosure = nil
                    dragDirectionConfirmed = false
                }

                let dragWidth = value.translation.width
                // let velocityX = value.predictedEndTranslation.width / 2 // Consider using velocity for advanced responsiveness

                // 1. Confirm Drag Direction (and check if actions exist for that direction)
                if !dragDirectionConfirmed {
                    if abs(dragWidth) > SwipeActionsModifier.dragConfirmationThreshold {
                        let potentialDirection: ActionType = dragWidth > 0 ? .leading : .trailing
                        // Only confirm if actions exist for this direction
                        if (potentialDirection == .leading && !leadingActions.isEmpty) ||
                           (potentialDirection == .trailing && !trailingActions.isEmpty) {
                            activeActionType = potentialDirection
                            dragDirectionConfirmed = true
                        } else {
                            // No actions in this direction, cancel drag
                            cancelDrag()
                            return
                        }
                    } else {
                        // Not dragged far enough to confirm direction
                        return
                    }
                }

                // 2. Calculate Offset based on confirmed direction
                guard let currentActionType = activeActionType else { return } // Should be set if dragDirectionConfirmed

                var currentOffset = dragWidth

                // Add resistance when dragging past the max offset
                let maxOffset = (currentActionType == .leading) ? maxLeadingOffset : maxTrailingOffset
                let isExceeding = (currentActionType == .leading && currentOffset > maxOffset) ||
                                  (currentActionType == .trailing && currentOffset < -maxOffset)

                if isExceeding {
                    let excess = abs(currentOffset) - maxOffset
                    // Apply diminishing returns to the offset calculation (resistance)
                    let resistanceFactor: CGFloat = 0.4
                    currentOffset = (currentOffset > 0 ? 1 : -1) * (maxOffset + (excess * resistanceFactor)) // Dampen the drag past max offset
                }


                // Calculate the potential full swipe activation offset
                let fullSwipeThreshold = maxOffset + SwipeActionsModifier.fullSwipeActivationExtraOffset


                switch currentActionType {
                case .leading:
                    // Clamp offset: 0 up to the calculated offset (which includes resistance)
                    let clampedOffset = max(0, currentOffset)
                    hOffset = clampedOffset

                    // Check for full swipe trigger activation based on the *unresisted* potential offset
                    // We use dragWidth here to check if the raw intention was beyond the threshold
                    if allowsFullSwipe, let firstAction = leadingActions.first, dragWidth > fullSwipeThreshold {
                        triggeredActionClosure = firstAction.action // Store the action closure
                    } else {
                        triggeredActionClosure = nil // Reset if not dragged far enough
                    }

                case .trailing:
                     // Clamp offset: Calculated offset (including resistance) down to 0
                    let clampedOffset = min(0, currentOffset)
                    hOffset = clampedOffset

                    // Check for full swipe trigger activation based on the *unresisted* potential offset
                     // We use dragWidth here to check if the raw intention was beyond the threshold
                    if allowsFullSwipe, let firstAction = trailingActions.first, abs(dragWidth) > fullSwipeThreshold {
                        triggeredActionClosure = firstAction.action // Store the action closure
                    } else {
                        triggeredActionClosure = nil // Reset if not dragged far enough
                    }
                }
            }
            .onEnded { value in
                isDragging = false // onChange will handle the rest
            }
    }

    // MARK: - State Change Handlers
    private func handleDragEnd(isDraggingEnded: Bool) {
         guard isDraggingEnded else { return } // Only act when dragging stops

         if let actionToTrigger = triggeredActionClosure {
             // Execute the triggered full swipe action
             actionToTrigger()
             // Reset offset smoothly after a short delay to allow visual feedback
             DispatchQueue.main.asyncAfter(deadline: .now() + SwipeActionsModifier.resetAnimationDelay) {
                  resetOffsetWithAnimation()
             }
         } else {
             // Snap to the resting position (either fully open or closed)
             snapToRestingPosition()
         }

         // Clean up state after drag ends and action/snap is decided
         triggeredActionClosure = nil
         dragDirectionConfirmed = false
         // activeActionType is reset inside snapToRestingPosition or resetOffsetWithAnimation
    }

    private func handleResetTrigger() {
        // Only reset if the swipe actions are currently open or animating
        if hOffset != 0 {
            resetOffsetWithAnimation()
        }
    }

    private func handleActionTap(actionClosure: @escaping () -> Void) {
        resetOffsetWithAnimation() // Close the swipe actions first
        // Execute the action after the closing animation has likely started/finished
        DispatchQueue.main.asyncAfter(deadline: .now() + SwipeActionsModifier.actionTapDelay) {
            actionClosure()
        }
    }

    // MARK: - Animation Logic
    // Snaps the view to the nearest resting state (open or closed)
    private func snapToRestingPosition() {
         guard let currentActionType = activeActionType else {
              resetOffsetWithAnimation() // Should not happen if drag ended normally, but reset just in case
              return
         }

         let snapThresholdRatio: CGFloat = 0.4 // Percentage of max offset needed to snap open
         let didExceedMinDistance: Bool = abs(hOffset) > SwipeActionsModifier.minSwipeDistance

         withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { // Slightly adjusted spring
             switch currentActionType {
             case .leading:
                 let threshold = maxLeadingOffset * snapThresholdRatio
                 // Snap open if dragged beyond threshold AND minimum distance
                 if hOffset > threshold && didExceedMinDistance {
                     hOffset = maxLeadingOffset
                 } else {
                     hOffset = 0 // Snap closed
                 }
             case .trailing:
                 let threshold = maxTrailingOffset * snapThresholdRatio
                 // Snap open if dragged beyond threshold AND minimum distance
                 if abs(hOffset) > threshold && didExceedMinDistance {
                     hOffset = -maxTrailingOffset
                 } else {
                     hOffset = 0 // Snap closed
                 }
             }
         }
         // Reset active action type after decision is made
         // Use DispatchQueue to ensure state update doesn't interfere with animation calculation
          DispatchQueue.main.async {
              self.activeActionType = nil
          }
    }

    // Resets the offset back to zero with animation
    private func resetOffsetWithAnimation() {
         withAnimation(.spring()) { // Use a default spring for reset
             hOffset = 0
         }
          // Use DispatchQueue to ensure state update doesn't interfere with animation calculation
          DispatchQueue.main.async {
               self.activeActionType = nil // Also clear type on reset
               self.dragDirectionConfirmed = false
               self.triggeredActionClosure = nil // Ensure triggered action is cleared on reset
          }
    }

    // Cancels the current drag operation immediately
    private func cancelDrag() {
        // Check isDragging to prevent cancelling already finished/reset drags
        if isDragging {
            isDragging = false
            resetOffsetWithAnimation() // Go back to closed state smoothly
        }
    }
}

// MARK: - SwipeAction Struct
struct SwipeAction: Identifiable {
    let id = UUID()
    let tint: Color
    let icon: String
    let label: String?
    let width: CGFloat
    let action: (() -> Void)?
    let menuContent: (() -> AnyView)?

    // Initializer for regular tap actions
    init(tint: Color, icon: String, label: String? = nil, width: CGFloat = 80, action: @escaping () -> Void) {
        self.tint = tint
        self.icon = icon
        self.label = label
        self.width = width
        self.action = action
        self.menuContent = nil
    }

    // Initializer for menu actions (type-erased using AnyView)
    init<MenuView: View>(tint: Color, icon: String, label: String? = nil, width: CGFloat = 80, @ViewBuilder menuContent: @escaping () -> MenuView) {
        self.tint = tint
        self.icon = icon
        self.label = label
        self.width = width
        self.action = nil
        self.menuContent = { AnyView(menuContent()) } // Wrap the menu content in AnyView
    }
}

// MARK: - View Extension for Convenience
extension View {
    // Main modifier function
    func swipeActions(
        leading: [SwipeAction] = [], // Provide default empty arrays
        trailing: [SwipeAction] = [],
        allowsFullSwipe: Bool = false,
        rowHeight: CGFloat,
        resetTrigger: Binding<Bool>
    ) -> some View {
        self.modifier(
            SwipeActionsModifier(
                leading: leading,
                trailing: trailing,
                allowsFullSwipe: allowsFullSwipe,
                rowHeight: rowHeight,
                resetTrigger: resetTrigger
            )
        )
    }

    // Convenience overload for only trailing actions
    func swipeActions(
         trailing: [SwipeAction],
         allowsFullSwipe: Bool = false,
         rowHeight: CGFloat,
         resetTrigger: Binding<Bool>
    ) -> some View {
         self.swipeActions( // Call the main function with empty leading actions
             leading: [],
             trailing: trailing,
             allowsFullSwipe: allowsFullSwipe,
             rowHeight: rowHeight,
             resetTrigger: resetTrigger
         )
    }

    // Convenience overload for only leading actions
    func swipeActions(
         leading: [SwipeAction],
         allowsFullSwipe: Bool = false,
         rowHeight: CGFloat,
         resetTrigger: Binding<Bool>
    ) -> some View {
         self.swipeActions( // Call the main function with empty trailing actions
             leading: leading,
             trailing: [],
             allowsFullSwipe: allowsFullSwipe,
             rowHeight: rowHeight,
             resetTrigger: resetTrigger
         )
    }
}

// MARK: - Preview Provider
struct ChatListGestureHandler_Previews: PreviewProvider {
    // Use a struct for preview state management
    struct PreviewWrapper: View {
        @State private var resetTrigger1 = false
        @State private var resetTrigger2 = false
        private let previewRowHeight: CGFloat = 60

        var body: some View {
            List {
                Section("Swipe Examples") {
                    Text("Chat 1 (Leading & Trailing)")
                        .listRowInsets(EdgeInsets()) // Remove default insets for full-width swipe
                        .swipeActions(
                            leading: [
                                SwipeAction(tint: .green, icon: "pin.fill") { print("Pin 1 Tapped") },
                                SwipeAction(tint: .gray, icon: "bell.slash.fill") { print("Mute 1 Tapped") }
                            ],
                            trailing: [
                                SwipeAction(tint: .red, icon: "trash.fill", label: "Delete") { print("Delete 1 Tapped") },
                                // Example Menu Action
                                SwipeAction(tint: .blue, icon: "archivebox.fill", label: "More") {
                                    Button("Archive") { print("Archive 1 via Menu") }
                                    Button("Mark Unread") { print("Mark Unread 1 via Menu") }
                                }
                            ],
                            rowHeight: previewRowHeight,
                            resetTrigger: $resetTrigger1
                        )
                        .frame(height: previewRowHeight) // Set frame height for consistent layout

                    Text("Chat 2 (Trailing Only, Full Swipe)")
                        .listRowInsets(EdgeInsets())
                        .swipeActions(
                            trailing: [
                                SwipeAction(tint: .orange, icon: "trash.fill", label: "Delete") {
                                     print("Delete 2 Triggered (Full Swipe or Tap)")
                                }
                            ],
                            allowsFullSwipe: true,
                            rowHeight: previewRowHeight,
                            resetTrigger: $resetTrigger2
                        )
                        .frame(height: previewRowHeight)

                     VStack(alignment: .leading) {
                          Text("Chat 3 (No Swipe Actions)")
                          Text("Subtitle here").font(.caption).foregroundColor(.gray)
                     }
                      .frame(height: previewRowHeight) // Maintain height consistency

                }

                 Section("Controls") {
                      Button("Reset Row 1") { resetTrigger1.toggle() }
                      Button("Reset Row 2") { resetTrigger2.toggle() }
                 }
            }
            .listStyle(.plain) // Use plain style for edge-to-edge rows
            .navigationTitle("Swipe Previews") // Add a title for context
        }
    }

    static var previews: some View {
        NavigationView { // Wrap in NavigationView for title and better preview structure
             PreviewWrapper()
        }
        // Add different preview variations if needed (e.g., dark mode)
        .preferredColorScheme(.dark)
        .previewDisplayName("Dark Mode")

         NavigationView {
              PreviewWrapper()
         }
         .preferredColorScheme(.light)
         .previewDisplayName("Light Mode")
    }
} 