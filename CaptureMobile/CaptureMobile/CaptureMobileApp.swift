//
//  CaptureMobileApp.swift
//  CaptureMobile
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
        let config = PostHogConfig(
            apiKey: "phc_YgHsWyMi6uMVf9HcdJp4lBROijKC0vU0JIeRNHIQTdM",
            host: "https://eu.i.posthog.com"
        )
        PostHogSDK.shared.setup(config)

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive]) { granted, _ in
            if granted {
                DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
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
                DeviceTokenManager.shared.registerIfNeeded()
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

    var storedToken: String? { UserDefaults.standard.string(forKey: tokenKey) }

    func store(_ token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
        registerIfNeeded()
    }

    func registerIfNeeded() {
        guard let token = storedToken,
              let userID = AppleAuthManager.shared.getUserID() else { return }
        Task { await APIService.shared.registerDeviceToken(token, userID: userID) }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    private let processedJobsQueue = DispatchQueue(label: "com.capture.processedJobs")
    private var processedJobIDs: Set<String> = []

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized {
                DispatchQueue.main.async { application.registerForRemoteNotifications() }
            }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        DeviceTokenManager.shared.store(token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Push registration failed: \(error.localizedDescription)")
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task {
            await handlePushPayload(userInfo)
            completionHandler(.newData)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await handlePushPayload(notification.request.content.userInfo)
        return [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        // Already handled by willPresent or didReceiveRemoteNotification
    }

    private func claimJob(_ jobID: String) -> Bool {
        processedJobsQueue.sync { processedJobIDs.insert(jobID).inserted }
    }

    private func handlePushPayload(_ userInfo: [AnyHashable: Any]) async {
        guard let action = userInfo["action"] as? String,
              let jobID = userInfo["job_id"] as? String else { return }

        guard claimJob(jobID) else { return }

        switch action {
        case "capture_saved":
            PendingJobManager.shared.removePendingJob(jobID: jobID)
            CaptureProcessingState.shared.markSuccess(jobID: jobID)
            PostHogSDK.shared.capture("push_capture_saved", properties: [
                "category": userInfo["category"] as? String ?? "unknown"
            ])

            // Refresh captures list
            Task { @MainActor in
                await CaptureHistoryManager.shared.loadCaptures()
            }

        case "error":
            let error = userInfo["error"] as? String ?? "Unknown"
            PostHogSDK.shared.capture("push_error", properties: ["error": error])
            PendingJobManager.shared.removePendingJob(jobID: jobID)
            CaptureProcessingState.shared.stopProcessing(jobID: jobID)
            CaptureHistoryManager.shared.removeCapture(id: jobID)
            DispatchQueue.main.async {
                CaptureProcessingState.shared.hasPendingFailure = true
            }

        default:
            break
        }
    }
}
