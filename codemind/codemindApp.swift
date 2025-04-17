//
//  codemindApp.swift
//  codemind
//
//  Created by Muhammed Yalçınkaya on 17.04.2025.
//

import SwiftUI
import SwiftData
import AppKit
// Import ApplicationServices for Accessibility check
import ApplicationServices

// Define AppDelegate to handle global events and window management
class AppDelegate: NSObject, NSApplicationDelegate {
    var modalWindow: NSWindow?
    var modalHostingController: NSHostingController<ModalView>? // Controller for the SwiftUI view
    var statusItem: NSStatusItem? // <-- ADDED Status Item variable

    // State to track modal visibility
    private var isModalVisible = false
    
    // Variables to track Option key presses
    private var optionKeyPressCount = 0
    private var lastOptionKeyPressTime: TimeInterval = 0
    private let keyIntervalThreshold: TimeInterval = 0.5 // Seconds between presses (reduced for quicker double press)
    private var previousModifierFlags: NSEvent.ModifierFlags? // To track changes

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("AppDelegate: applicationDidFinishLaunching")

        // 1. Check and request Accessibility permissions
        if checkAndRequestAccessibilityPermissions() {
            print("AppDelegate: Accessibility permissions granted.")
            // 2. Setup global monitor ONLY if permissions are granted
            setupGlobalMonitor()
        } else {
            print("AppDelegate: Accessibility permissions NOT granted. Global shortcut will not work until permission is granted manually in System Settings > Privacy & Security > Accessibility and the app is restarted.")
            // Optional: Show an alert to the user if there was a UI context to do so.
        }

        // Ensure the app can become active and appear in the Dock
        NSApp.setActivationPolicy(.regular) // <-- CHANGED to .regular

        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "CodeMind") // Set icon
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            print("AppDelegate: Status item created and configured.")
        } else {
            print("AppDelegate Error: Unable to create status bar button.")
        }
    }

    // Function to check accessibility permissions and prompt user if needed
    func checkAndRequestAccessibilityPermissions() -> Bool {
        print("AppDelegate: Checking Accessibility Permissions...")
        // Options dictionary with kAXTrustedCheckOptionPrompt set to true.
        // This tells the system to prompt the user if the app is not already trusted.
        let options: [String: Bool] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)

        if accessEnabled {
            print("AppDelegate: Accessibility Access is already enabled.")
            return true
        } else {
            print("AppDelegate: Accessibility Access is not enabled. System prompt may be shown.")
            // The AXIsProcessTrustedWithOptions function with the prompt option
            // should have already triggered the system dialog directing the user
            // to System Settings if access wasn't granted.
            // We return false here. The shortcut won't work immediately,
            // the user needs to grant permission and likely restart the app.
            return false
        }
    }

    // Function to setup the global keyboard shortcut monitor
    func setupGlobalMonitor() {
        print("AppDelegate: Setting up global monitor for double Option key press...")
        // Register the global keyboard monitor for modifier key changes
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }
            
            let currentFlags = event.modifierFlags
            let previousFlags = self.previousModifierFlags ?? NSEvent.ModifierFlags() // Handle initial nil case

            // Check if Option key was just pressed (was not pressed before, but is now)
            if !previousFlags.contains(.option) && currentFlags.contains(.option) {
                 // print("Option key pressed down.") // Debugging
                 let currentTime = Date().timeIntervalSince1970
                
                // Check if the time interval since the last press is within the threshold
                if (currentTime - self.lastOptionKeyPressTime) < self.keyIntervalThreshold {
                    self.optionKeyPressCount += 1
                } else {
                    // Reset count if interval is too long
                    self.optionKeyPressCount = 1
                }
                
                // Update the last press time
                self.lastOptionKeyPressTime = currentTime
                
                // Check if the count reached 2
                if self.optionKeyPressCount == 2 {
                    print("AppDelegate: Double Option Key DETECTED!")
                    // Reset the count
                    self.optionKeyPressCount = 0
                    self.lastOptionKeyPressTime = 0 
                    
                    // Ensure UI updates happen on the main thread
                    DispatchQueue.main.async {
                        print("AppDelegate: Calling toggleModal() on main thread.")
                        self.toggleModal()
                    }
                 }
                 // print("Option press detected. Count: \(self.optionKeyPressCount)") // Debugging
            } else if previousFlags.contains(.option) && !currentFlags.contains(.option) {
                // print("Option key released.") // Debugging - Option key was released, do nothing for count
            } else if !currentFlags.contains(.option) {
                 // If Option is not pressed and wasn't just released, reset count after a delay?
                 // Or maybe reset immediately if another non-modifier key is pressed?
                 // For simplicity, we'll just rely on the time threshold.
                 // If too much time passes, the count resets anyway on the next press.
            }
            
            // Store current flags for the next event
            self.previousModifierFlags = currentFlags
        }
        print("AppDelegate: Global monitor setup complete for flagsChanged.")
    }

    // Action called when the status item is clicked
    @objc func statusItemClicked(_ sender: Any?) {
        print("AppDelegate: Status item clicked.")
        // Toggle the main modal window
        toggleModal()
    }

    // Function to toggle the modal window's visibility
    func toggleModal() {
        isModalVisible.toggle()
        print("AppDelegate: toggleModal called. isModalVisible is now \(isModalVisible)")

        if isModalVisible {
            // Create and show the modal window if it doesn't exist or wasn't retained
            if modalWindow == nil {
                print("AppDelegate: Creating new modal window.")
                let modalView = ModalView() // Ensure ModalView exists
                modalHostingController = NSHostingController(rootView: modalView)

                modalWindow = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                    styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                    backing: .buffered, defer: false)
                modalWindow?.center()
                modalWindow?.title = "CodeMind"
                modalWindow?.isReleasedWhenClosed = false
                modalWindow?.contentView = modalHostingController?.view
                modalWindow?.level = .floating
                modalWindow?.delegate = self
            } else {
                 print("AppDelegate: Reusing existing modal window.")
            }
            // Bring the window to the front and activate the app
            print("AppDelegate: Ordering modal window front.")
            modalWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // Hide (order out) the modal window
            print("AppDelegate: Ordering modal window out.")
            modalWindow?.orderOut(nil)
        }
    }

    // Delegate method called when the app is reactivated (e.g., clicking Dock icon)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        print("AppDelegate: applicationShouldHandleReopen called. Has visible windows: \(flag)")
        if !flag {
            // If there are no visible windows, show the main modal window
            DispatchQueue.main.async {
                // Ensure toggleModal is called on the main thread
                // Only toggle if it's not already visible (to avoid hiding it)
                if !self.isModalVisible {
                    self.toggleModal()
                }
                // If it IS visible, just bring it to front (toggleModal already does this)
                else {
                    self.modalWindow?.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
        // Return true to indicate we've handled it
        return true 
    }
}

// Extend AppDelegate to handle window closing
extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // When the window is closed manually by clicking the close button
        print("AppDelegate: Window close button clicked.")
        isModalVisible = false
        // We keep the window instance (isReleasedWhenClosed = false)
        // so it can be reshown quickly via the shortcut.
    }
}

@main
struct codemindApp: App {
    // Inject the App Delegate
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Use Settings scene to manage the settings window
    var body: some Scene {
        Settings {
            // Link the Settings menu item to SettingsView
            // Add a frame to suggest a reasonable initial size for the settings window
            SettingsView()
                .frame(minWidth: 450, minHeight: 300) // Adjust size as needed
        }
        // Add standard AppKit menu commands
        .commands {
            CommandGroup(replacing: .appInfo) {
                // Explicitly add the About button action
                Button("About CodeMind") {
                    NSApplication.shared.orderFrontStandardAboutPanel(nil)
                }
            }
            // Keep other default command groups if needed
            // CommandGroup(replacing: .newItem) { }
        }
    }
}

// Placeholder for ModalView - Create ModalView.swift next
// struct ModalView: View { ... }
