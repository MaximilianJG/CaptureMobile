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
        
        // Request notification permission (including time-sensitive for Focus Mode bypass)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive]) { granted, _ in
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
        .onChange(of: scenePhase) { newPhase in
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
    
    // MARK: - Background Push Handling
    
    /// Called when a push notification with content-available:1 arrives while app is in background or terminated.
    /// This is CRITICAL for processing event creation pushes without requiring the user to tap.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task {
            await handlePushPayload(userInfo)
            completionHandler(.newData)
        }
    }
    
    // MARK: - Notification Handling (Foreground & Tap)
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await handlePushPayload(notification.request.content.userInfo)
        return [.banner, .sound]
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await handlePushPayload(response.notification.request.content.userInfo)
    }
    
    // MARK: - Push Payload Processing
    
    private func handlePushPayload(_ userInfo: [AnyHashable: Any]) async {
        guard let action = userInfo["action"] as? String else { return }
        
        switch action {
        case "create_events":
            // Push now only contains job_id (not full event data) to stay within 4KB APNS limit.
            // Fetch full event data from backend via /job-status/{job_id}.
            guard let jobID = userInfo["job_id"] as? String else {
                print("⚠️ Push: create_events without job_id")
                return
            }
            
            print("📬 Push: Fetching events for job \(jobID.prefix(8))...")
            
            guard let jobStatus = await APIService.shared.checkJobStatus(jobID: jobID) else {
                print("❌ Push: Failed to fetch job \(jobID.prefix(8))")
                // Save as pending so it can be recovered when app opens
                PendingJobManager.shared.savePendingJob(jobID: jobID)
                return
            }
            
            guard jobStatus.status == "completed",
                  let events = jobStatus.eventsToCreate, !events.isEmpty else {
                print("⚠️ Push: Job \(jobID.prefix(8)) has no events (status: \(jobStatus.status))")
                CaptureProcessingState.shared.markSuccess()
                return
            }
            
            var createdCount = 0
            for event in events {
                let calendarEvent = event.toCalendarEvent()
                if let eventID = try? CalendarService.shared.createEvent(calendarEvent) {
                    CaptureHistoryManager.shared.addCapture(event, eventID: eventID)
                    createdCount += 1
                }
            }
            
            print("✅ Push: Created \(createdCount) event(s) from job \(jobID.prefix(8))")
            PostHogSDK.shared.capture("push_events_created", properties: ["count": createdCount])
            
            // Remove from pending jobs (push succeeded, no recovery needed)
            PendingJobManager.shared.removePendingJob(jobID: jobID)
            
            // Mark processing complete (clears failure state)
            CaptureProcessingState.shared.markSuccess()
            
        case "no_events":
            PostHogSDK.shared.capture("push_no_events")
            // Remove from pending jobs if job_id present
            if let jobID = userInfo["job_id"] as? String {
                PendingJobManager.shared.removePendingJob(jobID: jobID)
            }
            // Clear processing state (completed but no events)
            CaptureProcessingState.shared.markSuccess()
            
        case "error":
            let error = userInfo["error"] as? String ?? "Unknown"
            PostHogSDK.shared.capture("push_error", properties: ["error": error])
            // Remove from pending jobs if job_id present
            if let jobID = userInfo["job_id"] as? String {
                PendingJobManager.shared.removePendingJob(jobID: jobID)
            }
            // Show failure in UI
            CaptureProcessingState.shared.stopProcessing()
            DispatchQueue.main.async {
                CaptureProcessingState.shared.hasPendingFailure = true
            }
            
        default:
            break
        }
    }
}
