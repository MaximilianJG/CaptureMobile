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
    
    // Use AppDelegate for push notifications and background handling
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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                // Register for remote push notifications if authorized
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
        
        if #available(iOS 16.0, *) {
            // Update system about app shortcuts (currently empty - we use iCloud shortcut instead)
            CaptureShortcuts.updateAppShortcutParameters()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Check for pending jobs when app opens
                    Task {
                        await PendingJobManager.shared.recoverPendingJobs()
                    }
                }
        }
    }
}

// MARK: - AppDelegate for Push Notifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Set notification delegate for handling pushes
        UNUserNotificationCenter.current().delegate = self
        
        // Check if notifications are authorized and register for push
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }
        
        return true
    }
    
    // MARK: - Push Notification Registration
    
    /// Called when APNs successfully registers the device
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Convert token to hex string
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("📱 Device token: \(token)")
        
        // Register with backend
        Task {
            if let userID = AppleAuthManager.shared.getUserID() {
                await APIService.shared.registerDeviceToken(token, userID: userID)
            }
        }
    }
    
    /// Called if push notification registration fails
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for push notifications: \(error)")
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    /// Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        
        // Process push payload if it contains event data
        handlePushPayload(userInfo)
        
        // Show the notification banner
        return [.banner, .sound]
    }
    
    /// Handle notification when user taps it
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        handlePushPayload(userInfo)
    }
    
    // MARK: - Push Payload Handling
    
    /// Process push notification payload and create calendar events
    private func handlePushPayload(_ userInfo: [AnyHashable: Any]) {
        guard let action = userInfo["action"] as? String else {
            return  // Not our push notification format
        }
        
        switch action {
        case "create_events":
            // Parse events from push payload
            guard let eventsArray = userInfo["events"] as? [[String: Any]] else {
                print("No events in push payload")
                return
            }
            
            // Convert to ExtractedEventInfo and create calendar events
            var createdCount = 0
            for eventDict in eventsArray {
                if let eventInfo = parseEventInfo(from: eventDict) {
                    let calendarEvent = eventInfo.toCalendarEvent()
                    if let eventID = try? CalendarService.shared.createEvent(calendarEvent) {
                        CaptureHistoryManager.shared.addCapture(eventInfo, eventID: eventID)
                        createdCount += 1
                    }
                }
            }
            
            print("✅ Push: Created \(createdCount) event(s) from notification")
            PostHogSDK.shared.capture("push_events_created", properties: [
                "count": createdCount
            ])
            
        case "no_events":
            print("Push: No events found in screenshot")
            PostHogSDK.shared.capture("push_no_events")
            
        case "error":
            let errorMessage = userInfo["error"] as? String ?? "Unknown error"
            print("Push: Error - \(errorMessage)")
            PostHogSDK.shared.capture("push_error", properties: [
                "error": errorMessage
            ])
            
        default:
            print("Push: Unknown action - \(action)")
        }
    }
    
    /// Parse event info from dictionary (from push payload)
    private func parseEventInfo(from dict: [String: Any]) -> APIService.ExtractedEventInfo? {
        guard let title = dict["title"] as? String,
              let date = dict["date"] as? String else {
            return nil
        }
        
        return APIService.ExtractedEventInfo(
            title: title,
            date: date,
            startTime: dict["start_time"] as? String,
            endTime: dict["end_time"] as? String,
            location: dict["location"] as? String,
            description: dict["description"] as? String,
            timezone: dict["timezone"] as? String,
            isAllDay: dict["is_all_day"] as? Bool ?? false,
            isDeadline: dict["is_deadline"] as? Bool ?? false,
            confidence: dict["confidence"] as? Double ?? 0.5,
            attendeeName: dict["attendee_name"] as? String,
            sourceApp: dict["source_app"] as? String
        )
    }
}
