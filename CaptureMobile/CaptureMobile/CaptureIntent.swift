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
            
            if response.success && !response.eventsCreated.isEmpty {
                // Save all events to capture history
                for event in response.eventsCreated {
                    CaptureHistoryManager.shared.addCapture(event)
                }
                
                // Build notification and result based on event count
                let eventCount = response.eventsCreated.count
                if eventCount == 1, let event = response.eventsCreated.first {
                    // Single event
                    sendNotification(
                        title: "Event Created",
                        body: "\(event.title)\n\(formatEventTime(event))"
                    )
                    
                    PostHogSDK.shared.capture("shortcut_completed", properties: [
                        "success": true,
                        "event_title": event.title,
                        "event_count": 1
                    ])
                    PostHogSDK.shared.flush()
                    return .result(value: "✅ Created: \(event.title)")
                } else {
                    // Multiple events
                    let eventTitles = response.eventsCreated.map { $0.title }.joined(separator: ", ")
                    sendNotification(
                        title: "\(eventCount) Events Created",
                        body: eventTitles
                    )
                    
                    PostHogSDK.shared.capture("shortcut_completed", properties: [
                        "success": true,
                        "event_count": eventCount
                    ])
                    PostHogSDK.shared.flush()
                    return .result(value: "✅ Created \(eventCount) events")
                }
            } else {
                // Check if it's "no event found" or "calendar creation failed"
                let isNoEventFound = response.message.lowercased().contains("no event") || 
                                     response.message.lowercased().contains("not found")
                
                if isNoEventFound {
                    sendNotification(
                        title: "No Event Found",
                        body: "Couldn't detect an event in your screenshot"
                    )
                } else {
                    sendNotification(
                        title: "Event Creation Failed",
                        body: response.message
                    )
                }
                
                PostHogSDK.shared.capture("shortcut_completed", properties: [
                    "success": false,
                    "error": response.message
                ])
                PostHogSDK.shared.flush()
                return .result(value: "⚠️ \(response.message)")
            }
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
    
    private func formatEventTime(_ event: APIService.EventDetails) -> String {
        // Parse the ISO date string
        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        
        var date: Date?
        
        // Try date with time first
        date = dateTimeFormatter.date(from: event.startTime)
        
        // Try date only
        if date == nil {
            date = dateOnlyFormatter.date(from: event.startTime)
        }
        
        guard let parsedDate = date else {
            return event.startTime
        }
        
        // Format for display
        let displayFormatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(parsedDate) {
            displayFormatter.dateFormat = "'Today,' HH:mm"
        } else if calendar.isDateInTomorrow(parsedDate) {
            displayFormatter.dateFormat = "'Tomorrow,' HH:mm"
        } else if calendar.isDate(parsedDate, equalTo: Date(), toGranularity: .weekOfYear) {
            displayFormatter.dateFormat = "EEEE, HH:mm"
        } else {
            displayFormatter.dateFormat = "MMM d, HH:mm"
        }
        
        return displayFormatter.string(from: parsedDate)
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
