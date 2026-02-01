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
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // Initialize PostHog Analytics
        let config = PostHogConfig(
            apiKey: "phc_YgHsWyMi6uMVf9HcdJp4lBROijKC0vU0JIeRNHIQTdM",
            host: "https://eu.i.posthog.com"
        )
        PostHogSDK.shared.setup(config)
        
        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
        
        if #available(iOS 16.0, *) {
            CaptureShortcuts.updateAppShortcutParameters()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Register device token when app becomes active (handles server restarts)
                DeviceTokenManager.shared.registerIfNeeded()
                
                // Check for pending jobs
                Task {
                    await PendingJobManager.shared.recoverPendingJobs()
                }
            }
        }
    }
}

// MARK: - Device Token Manager

class DeviceTokenManager {
    static let shared = DeviceTokenManager()
    private init() {}
    
    private let tokenKey = "apns_device_token"
    
    var storedToken: String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }
    
    /// Called when APNs gives us a new token
    func store(_ token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
        print("📱 Device token stored")
        registerIfNeeded()
    }
    
    /// Register with backend if we have token and user ID
    func registerIfNeeded() {
        guard let token = storedToken,
              let userID = AppleAuthManager.shared.getUserID() else {
            return
        }
        
        Task {
            await APIService.shared.registerDeviceToken(token, userID: userID)
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        
        // Register for push notifications if authorized
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }
        
        return true
    }
    
    // MARK: - Push Token
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        DeviceTokenManager.shared.store(token)
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Push registration failed: \(error.localizedDescription)")
    }
    
    // MARK: - Notification Handling
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        handlePushPayload(notification.request.content.userInfo)
        return [.banner, .sound]
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        handlePushPayload(response.notification.request.content.userInfo)
    }
    
    private func handlePushPayload(_ userInfo: [AnyHashable: Any]) {
        guard let action = userInfo["action"] as? String else { return }
        
        switch action {
        case "create_events":
            guard let eventsArray = userInfo["events"] as? [[String: Any]] else { return }
            
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
            
            print("✅ Push: Created \(createdCount) event(s)")
            PostHogSDK.shared.capture("push_events_created", properties: ["count": createdCount])
            
        case "no_events":
            PostHogSDK.shared.capture("push_no_events")
            
        case "error":
            let error = userInfo["error"] as? String ?? "Unknown"
            PostHogSDK.shared.capture("push_error", properties: ["error": error])
            
        default:
            break
        }
    }
    
    private func parseEventInfo(from dict: [String: Any]) -> APIService.ExtractedEventInfo? {
        guard let title = dict["title"] as? String,
              let date = dict["date"] as? String else { return nil }
        
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
