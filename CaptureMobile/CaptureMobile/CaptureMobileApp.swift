//
//  CaptureMobileApp.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 17.01.26.
//

import SwiftUI
import AppIntents
import PostHog
import UserNotifications

@main
struct CaptureMobileApp: App {
    
    // Use AppDelegate for background URL session handling
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Register App Shortcuts with the system
    init() {
        // Initialize PostHog Analytics
        let config = PostHogConfig(
            apiKey: "phc_YgHsWyMi6uMVf9HcdJp4lBROijKC0vU0JIeRNHIQTdM",
            host: "https://eu.i.posthog.com"
        )
        PostHogSDK.shared.setup(config)
        
        // Request notification permission for capture results
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        
        if #available(iOS 16.0, *) {
            // Update system about app shortcuts (currently empty - we use iCloud shortcut instead)
            CaptureShortcuts.updateAppShortcutParameters()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - AppDelegate for Background URL Session

class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Reconnect to any existing background sessions
        BackgroundUploadManager.shared.reconnectBackgroundSession()
        return true
    }
    
    /// Called by iOS when a background URL session has events waiting
    /// This is how iOS wakes up our app when the upload completes
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        if identifier == BackgroundUploadManager.sessionIdentifier {
            // Store the completion handler - must be called when we're done processing
            BackgroundUploadManager.shared.backgroundCompletionHandler = completionHandler
            // Reconnect to the session to receive the pending events
            BackgroundUploadManager.shared.reconnectBackgroundSession()
        }
    }
}
