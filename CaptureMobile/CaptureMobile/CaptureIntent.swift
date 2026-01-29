//
//  CaptureIntent.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 17.01.26.
//

import AppIntents
import UIKit
import SwiftUI
import UniformTypeIdentifiers
import PostHog
import UserNotifications

/// App Intent that allows Shortcuts to send images directly to Capture
/// This appears as "Send to Capture" in the Shortcuts app
@available(iOS 16.0, *)
struct CaptureScreenshotIntent: AppIntent {
    
    static var title: LocalizedStringResource = "Send to Capture"
    static var description = IntentDescription("Analyzes a screenshot and creates a calendar event")
    
    // The image parameter that Shortcuts will provide
    // Using supportedTypeIdentifiers to accept images from other actions
    @Parameter(
        title: "Screenshot",
        description: "The screenshot to analyze",
        supportedTypeIdentifiers: ["public.image", "public.jpeg", "public.png"],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var screenshot: IntentFile
    
    // Configure how this appears in Shortcuts
    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$screenshot) to Capture")
    }
    
    // This runs when the shortcut executes
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Initialize PostHog (needed because intents run separately from main app)
        let config = PostHogConfig(
            apiKey: "phc_YgHsWyMi6uMVf9HcdJp4lBROijKC0vU0JIeRNHIQTdM",
            host: "https://eu.i.posthog.com"
        )
        PostHogSDK.shared.setup(config)
        
        // Track shortcut execution
        PostHogSDK.shared.capture("shortcut_executed")
        
        // Get the image data from the intent file
        let imageData = screenshot.data
        guard let image = UIImage(data: imageData) else {
            PostHogSDK.shared.capture("shortcut_completed", properties: [
                "success": false,
                "error": "failed_to_read_screenshot"
            ])
            PostHogSDK.shared.flush()
            return .result(value: "❌ Failed to read screenshot")
        }
        
        // Check if user is signed in and get user ID
        guard let userID = AppleAuthManager.shared.getUserID() else {
            PostHogSDK.shared.capture("shortcut_completed", properties: [
                "success": false,
                "error": "not_signed_in"
            ])
            PostHogSDK.shared.flush()
            return .result(value: "❌ Not signed in. Please open Capture app and sign in first.")
        }
        
        // Check calendar access
        guard CalendarService.shared.hasAccess else {
            PostHogSDK.shared.capture("shortcut_completed", properties: [
                "success": false,
                "error": "no_calendar_access"
            ])
            PostHogSDK.shared.flush()
            return .result(value: "❌ No calendar access. Please open Capture app and grant calendar permission.")
        }
        
        // Send immediate notification
        sendNotification(
            title: "Analyzing Screenshot...",
            body: "You'll get a notification when done"
        )
        
        // Start background upload - this survives even after the shortcut terminates!
        // iOS Background URLSession handles the network request independently
        let success = BackgroundUploadManager.shared.uploadScreenshot(image, userID: userID)
        
        if !success {
            PostHogSDK.shared.capture("shortcut_completed", properties: [
                "success": false,
                "error": "upload_start_failed"
            ])
            PostHogSDK.shared.flush()
            return .result(value: "❌ Failed to start upload")
        }
        
        PostHogSDK.shared.capture("shortcut_background_upload_initiated")
        PostHogSDK.shared.flush()
        
        // Return immediately - the background upload continues independently!
        // User will get a notification when processing is complete
        return .result(value: "📸 Processing in background...")
    }
    
    // Open the app when there's an error (optional)
    static var openAppWhenRun: Bool = false
    
    // MARK: - Notification Helpers
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // nil = send immediately
        )
        UNUserNotificationCenter.current().add(request)
    }
}

/// Shortcuts App Provider - registers all intents with the system
/// Note: We intentionally return an empty array so "Send to Capture" doesn't appear
/// in the App Shortcuts gallery. Users should use our pre-made iCloud shortcut instead,
/// which provides the complete workflow (Take Screenshot → Send to Capture).
@available(iOS 16.0, *)
struct CaptureShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        return [AppShortcut]()
    }
}
