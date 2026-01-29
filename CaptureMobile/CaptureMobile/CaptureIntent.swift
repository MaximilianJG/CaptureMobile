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
        
        // Check if user is signed in
        guard AppleAuthManager.shared.getUserID() != nil else {
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
        
        // Send to backend and create events locally
        do {
            let result = try await APIService.shared.analyzeAndCreateEvents(image)
            
            if result.eventsCreated > 0 {
                // Build notification and result based on event count
                if result.eventsCreated == 1 {
                    // Single event
                    sendNotification(
                        title: "Event Created",
                        body: result.firstEventTitle ?? "Event"
                    )
                    
                    PostHogSDK.shared.capture("shortcut_completed", properties: [
                        "success": true,
                        "event_title": result.firstEventTitle ?? "Event",
                        "event_count": 1
                    ])
                    PostHogSDK.shared.flush()
                    return .result(value: "✅ Created: \(result.firstEventTitle ?? "Event")")
                } else {
                    // Multiple events
                    sendNotification(
                        title: "\(result.eventsCreated) Events Created",
                        body: result.message
                    )
                    
                    PostHogSDK.shared.capture("shortcut_completed", properties: [
                        "success": true,
                        "event_count": result.eventsCreated
                    ])
                    PostHogSDK.shared.flush()
                    return .result(value: "✅ Created \(result.eventsCreated) events")
                }
            } else {
                sendNotification(
                    title: "Event Creation Failed",
                    body: result.message
                )
                
                PostHogSDK.shared.capture("shortcut_completed", properties: [
                    "success": false,
                    "error": result.message
                ])
                PostHogSDK.shared.flush()
                return .result(value: "⚠️ \(result.message)")
            }
        } catch let error as APIService.APIError {
            // Handle specific API errors
            let errorMessage: String
            let notificationTitle: String
            
            switch error {
            case .noEventFound:
                notificationTitle = "No Event Found"
                errorMessage = "Couldn't detect an event in your screenshot"
            case .rateLimited(let message):
                notificationTitle = "Rate Limited"
                errorMessage = message
            case .calendarError(let message):
                notificationTitle = "Calendar Error"
                errorMessage = message
            default:
                notificationTitle = "Capture Failed"
                errorMessage = error.localizedDescription
            }
            
            sendNotification(title: notificationTitle, body: errorMessage)
            
            PostHogSDK.shared.capture("shortcut_completed", properties: [
                "success": false,
                "error": errorMessage
            ])
            PostHogSDK.shared.flush()
            return .result(value: "❌ \(errorMessage)")
        } catch {
            // Send error notification
            sendNotification(
                title: "Capture Failed",
                body: error.localizedDescription
            )
            
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
