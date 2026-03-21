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
                
                // Recover pending jobs and retry failed uploads
                Task {
                    await PendingJobManager.shared.recoverPendingJobs()
                    await BackgroundUploadManager.shared.processPendingUploads()
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
    
    /// Thread-safe set of job IDs that have already been processed by handlePushPayload.
    /// Prevents duplicate event creation when multiple push delegates fire for the same notification.
    private let processedJobsQueue = DispatchQueue(label: "com.capture.processedJobs")
    private var processedJobIDs: Set<String> = []
    
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
        // When user taps a notification, didReceiveRemoteNotification (or willPresent)
        // has already processed the payload. Skip to avoid duplicate event creation.
    }
    
    // MARK: - Push Payload Processing
    
    /// Atomically claims a job ID for processing.
    /// Returns true if this is the first call for this job (caller should process it).
    /// Returns false if the job was already claimed (caller should skip).
    private func claimJob(_ jobID: String) -> Bool {
        return processedJobsQueue.sync {
            let (inserted, _) = processedJobIDs.insert(jobID)
            return inserted
        }
    }
    
    /// Removes a job ID from the processed set (e.g. if processing failed and
    /// we want PendingJobManager to retry later).
    private func unclaimJob(_ jobID: String) {
        processedJobsQueue.sync {
            _ = processedJobIDs.remove(jobID)
        }
    }
    
    private func handlePushPayload(_ userInfo: [AnyHashable: Any]) async {
        guard let action = userInfo["action"] as? String else { return }
        
        // Extract job_id (used by all actions for per-job tracking)
        let jobID = userInfo["job_id"] as? String
        
        switch action {
        case "create_events":
            // Push now only contains job_id (not full event data) to stay within 4KB APNS limit.
            // Fetch full event data from backend via /job-status/{job_id}.
            guard let jobID = jobID else {
                print("⚠️ Push: create_events without job_id")
                return
            }
            
            // Check persistent storage first - handles app restart scenarios where
            // recovery already processed this job but in-memory set was cleared.
            guard !PendingJobManager.shared.isJobCompleted(jobID) else {
                print("⏭️ Push: Job \(jobID.prefix(8)) already completed, skipping")
                return
            }
            
            // Deduplicate: multiple push delegates can fire for the same notification.
            // Only the first caller to claim the job will actually process it.
            guard claimJob(jobID) else {
                print("⏭️ Push: Job \(jobID.prefix(8)) already being processed, skipping duplicate")
                return
            }
            
            print("📬 Push: Fetching events for job \(jobID.prefix(8))...")
            
            guard let jobStatus = await APIService.shared.checkJobStatus(jobID: jobID) else {
                print("❌ Push: Failed to fetch job \(jobID.prefix(8))")
                // Release the claim so PendingJobManager can retry on next app open
                unclaimJob(jobID)
                // Save as pending so it can be recovered when app opens
                PendingJobManager.shared.savePendingJob(jobID: jobID)
                return
            }
            
            guard jobStatus.status == "completed",
                  let events = jobStatus.eventsToCreate, !events.isEmpty else {
                print("⚠️ Push: Job \(jobID.prefix(8)) has no events (status: \(jobStatus.status))")
                CaptureProcessingState.shared.markSuccess(jobID: jobID)
                return
            }
            
            // Mark as completed BEFORE creating events to prevent the recovery
            // system from racing and creating duplicates.
            PendingJobManager.shared.markJobAsProcessing(jobID)
            
            var createdCount = 0
            var eventTitles: [String] = []
            for event in events {
                let calendarEvent = event.toCalendarEvent()
                if let eventID = try? CalendarService.shared.createEvent(calendarEvent) {
                    CaptureHistoryManager.shared.addCapture(event, eventID: eventID)
                    eventTitles.append(event.title)
                    createdCount += 1
                }
            }

            let summary = createdCount == 1
                ? "Created event: \(eventTitles.first ?? "Event")"
                : "Created \(createdCount) events: \(eventTitles.joined(separator: ", "))"
            CaptureHistoryManager.shared.updateCapture(
                id: jobID, status: "completed", aiSummary: summary, destination: "calendar"
            )
            
            print("✅ Push: Created \(createdCount) event(s) from job \(jobID.prefix(8))")
            PostHogSDK.shared.capture("push_events_created", properties: ["count": createdCount])
            
            PendingJobManager.shared.removePendingJob(jobID: jobID)
            CaptureProcessingState.shared.markSuccess(jobID: jobID)
            
        case "no_events":
            PostHogSDK.shared.capture("push_no_events")
            if let jobID = jobID {
                _ = claimJob(jobID)
                PendingJobManager.shared.removePendingJob(jobID: jobID)
                CaptureProcessingState.shared.markSuccess(jobID: jobID)
                CaptureHistoryManager.shared.updateCapture(
                    id: jobID, status: "completed",
                    aiSummary: "No calendar events or actionable content found."
                )
            }
            
        case "notion_saved":
            PostHogSDK.shared.capture("push_notion_saved")
            if let jobID = jobID {
                _ = claimJob(jobID)
                PendingJobManager.shared.removePendingJob(jobID: jobID)
                CaptureProcessingState.shared.markSuccess(jobID: jobID)

                let body = userInfo["aps"] as? [String: Any]
                let alert = body?["alert"] as? [String: Any]
                let notionBody = alert?["body"] as? String ?? "Saved to Notion"

                CaptureHistoryManager.shared.updateCapture(
                    id: jobID, status: "completed",
                    aiSummary: notionBody, destination: "notion"
                )
            }

        case "error":
            let error = userInfo["error"] as? String ?? "Unknown"
            PostHogSDK.shared.capture("push_error", properties: ["error": error])
            if let jobID = jobID {
                _ = claimJob(jobID)
                PendingJobManager.shared.removePendingJob(jobID: jobID)
                CaptureProcessingState.shared.stopProcessing(jobID: jobID)
                CaptureHistoryManager.shared.updateCapture(
                    id: jobID, status: "failed", aiSummary: "Failed: \(error)"
                )
            }
            DispatchQueue.main.async {
                CaptureProcessingState.shared.hasPendingFailure = true
            }
            
        default:
            break
        }
    }
}
