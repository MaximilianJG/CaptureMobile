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
        
        // Ensure device token is registered (handles server restarts)
        DeviceTokenManager.shared.registerIfNeeded()
        
        // Check calendar access
        guard CalendarService.shared.hasAccess else {
            PostHogSDK.shared.capture("shortcut_completed", properties: [
                "success": false,
                "error": "no_calendar_access"
            ])
            PostHogSDK.shared.flush()
            return .result(value: "❌ No calendar access. Please open Capture app and grant calendar permission.")
        }
        
        // Check notification authorization to decide which flow to use
        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        let pushEnabled = notificationSettings.authorizationStatus == .authorized
        
        PostHogSDK.shared.capture("shortcut_flow_selected", properties: [
            "flow": pushEnabled ? "async_push" : "sync_fallback"
        ])
        
        if pushEnabled {
            // =====================================================
            // FLOW A: Push notifications enabled - use async flow
            // =====================================================
            sendNotification(
                title: "Analyzing Screenshot...",
                body: "You'll get a notification when done."
            )
            
            if let jobID = await APIService.shared.uploadScreenshotAsync(image, userID: userID) {
                PostHogSDK.shared.capture("shortcut_async_upload_success", properties: [
                    "job_id": jobID
                ])
                PostHogSDK.shared.flush()
                
                return .result(value: "📸 Analyzing...")
            } else {
                PostHogSDK.shared.capture("shortcut_async_upload_failed")
                PostHogSDK.shared.flush()
                
                return .result(value: "❌ Upload failed. Check your connection.")
            }
        } else {
            // =====================================================
            // FLOW B: No push - try synchronous with timeout
            // =====================================================
            sendNotification(
                title: "Analyzing Screenshot...",
                body: "This may take a moment."
            )
            
            do {
                // Try to complete synchronously
                let result = try await APIService.shared.analyzeAndCreateEvents(image)
                
                PostHogSDK.shared.capture("shortcut_sync_success", properties: [
                    "events_created": result.eventsCreated
                ])
                PostHogSDK.shared.flush()
                
                // Send success notification
                if result.eventsCreated == 1 {
                    sendNotification(
                        title: "Event Created",
                        body: result.firstEventTitle ?? "New event"
                    )
                    return .result(value: "✅ \(result.firstEventTitle ?? "Event") created!")
                } else {
                    sendNotification(
                        title: "\(result.eventsCreated) Events Created",
                        body: result.message
                    )
                    return .result(value: "✅ \(result.eventsCreated) events created!")
                }
                
            } catch let error as URLError where error.code == .timedOut {
                // Timeout - start an async job and save as pending
                PostHogSDK.shared.capture("shortcut_sync_timeout")
                
                if let jobID = await APIService.shared.uploadScreenshotAsync(image, userID: userID) {
                    PendingJobManager.shared.savePendingJob(jobID: jobID)
                    PostHogSDK.shared.flush()
                    return .result(value: "⏳ Still processing... Open the Capture app to see results.")
                } else {
                    PostHogSDK.shared.flush()
                    return .result(value: "⏳ Processing took too long. Open the Capture app to try again.")
                }
                
            } catch let error as APIService.APIError {
                PostHogSDK.shared.capture("shortcut_sync_failed", properties: [
                    "error": error.localizedDescription
                ])
                PostHogSDK.shared.flush()
                
                sendNotification(
                    title: "Capture Failed",
                    body: error.localizedDescription
                )
                
                return .result(value: "❌ \(error.localizedDescription)")
                
            } catch {
                PostHogSDK.shared.capture("shortcut_sync_failed", properties: [
                    "error": error.localizedDescription
                ])
                PostHogSDK.shared.flush()
                
                return .result(value: "❌ \(error.localizedDescription)")
            }
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
