//
//  CaptureMobileApp.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 17.01.26.
//

import SwiftUI
import GoogleSignIn
import AppIntents
import PostHog
import UserNotifications

@main
struct CaptureMobileApp: App {
    
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
            // This makes the "Send to Capture" action available in Shortcuts
            CaptureShortcuts.updateAppShortcutParameters()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // Handle Google Sign-In callback URL
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
