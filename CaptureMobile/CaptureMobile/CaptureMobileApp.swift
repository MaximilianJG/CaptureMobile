//
//  CaptureMobileApp.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 17.01.26.
//

import SwiftUI
import GoogleSignIn
import AppIntents

@main
struct CaptureMobileApp: App {
    
    // Register App Shortcuts with the system
    init() {
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
