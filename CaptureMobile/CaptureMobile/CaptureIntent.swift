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
        
        // Get the access token
        guard let accessToken = await GoogleAuthManager.shared.getAccessToken() else {
            PostHogSDK.shared.capture("shortcut_completed", properties: [
                "success": false,
                "error": "not_signed_in"
            ])
            PostHogSDK.shared.flush()
            return .result(value: "❌ Not signed in. Please open Capture app and sign in first.")
        }
        
        // Send to backend
        do {
            let response = try await APIService.shared.analyzeScreenshot(image)
            
            if response.success, let event = response.eventCreated {
                PostHogSDK.shared.capture("shortcut_completed", properties: [
                    "success": true,
                    "event_title": event.title
                ])
                PostHogSDK.shared.flush()
                return .result(value: "✅ Created: \(event.title)")
            } else {
                PostHogSDK.shared.capture("shortcut_completed", properties: [
                    "success": false,
                    "error": response.message
                ])
                PostHogSDK.shared.flush()
                return .result(value: "⚠️ \(response.message)")
            }
        } catch {
            PostHogSDK.shared.capture("shortcut_completed", properties: [
                "success": false,
                "error": error.localizedDescription
            ])
            PostHogSDK.shared.flush()
            return .result(value: "❌ Error: \(error.localizedDescription)")
        }
    }
    
    // Open the app when there's an error (optional)
    static var openAppWhenRun: Bool = false
}

/// Shortcuts App Provider - registers all intents with the system
@available(iOS 16.0, *)
struct CaptureShortcuts: AppShortcutsProvider {
    
    /// Pre-built shortcuts that appear in the Shortcuts app gallery
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureScreenshotIntent(),
            phrases: [
                "Send to \(.applicationName)",
                "Send screenshot to \(.applicationName)",
                "Create event from screenshot with \(.applicationName)"
            ],
            shortTitle: "Send to Capture",
            systemImageName: "camera.viewfinder"
        )
    }
}
