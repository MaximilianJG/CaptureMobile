//
//  CaptureIntent.swift
//  CaptureMobile
//

import AppIntents
import UIKit
import SwiftUI
import UniformTypeIdentifiers
import PostHog
import UserNotifications

@available(iOS 16.0, *)
struct CaptureScreenshotIntent: AppIntent {

    static var title: LocalizedStringResource = "Send to Capture"
    static var description = IntentDescription("Analyzes a screenshot and saves it as a capture")

    @Parameter(
        title: "Screenshot",
        description: "The screenshot to analyze",
        supportedTypeIdentifiers: ["public.image", "public.jpeg", "public.png"],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var screenshot: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$screenshot) to Capture")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let config = PostHogConfig(
            apiKey: "phc_YgHsWyMi6uMVf9HcdJp4lBROijKC0vU0JIeRNHIQTdM",
            host: "https://eu.i.posthog.com"
        )
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.capture("shortcut_executed")

        let imageData = screenshot.data
        guard let image = UIImage(data: imageData) else {
            PostHogSDK.shared.flush()
            return .result(value: "Failed to read screenshot")
        }

        guard let userID = AppleAuthManager.shared.getUserID() else {
            PostHogSDK.shared.flush()
            return .result(value: "Not signed in. Please open Capture and sign in first.")
        }

        DeviceTokenManager.shared.registerIfNeeded()

        sendNotification(title: "Analyzing Screenshot...", body: "You'll get a notification when done.")

        if let jobID = await APIService.shared.uploadCaptureAsync(
            image: image, text: nil, userID: userID, source: "screenshot"
        ) {
            CaptureProcessingState.shared.startProcessing(jobID: jobID)
            PendingJobManager.shared.savePendingJob(jobID: jobID)

            PostHogSDK.shared.capture("shortcut_upload_success", properties: ["job_id": jobID])
            PostHogSDK.shared.flush()
            return .result(value: "Analyzing...")
        } else {
            BackgroundUploadManager.shared.enqueue(image: image, userID: userID)
            PostHogSDK.shared.flush()
            return .result(value: "Upload queued. It will retry when you open the app.")
        }
    }

    static var openAppWhenRun: Bool = false

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

@available(iOS 16.0, *)
struct CaptureShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureScreenshotIntent(),
            phrases: [
                "Send to \(.applicationName)",
                "Capture with \(.applicationName)"
            ],
            shortTitle: "Send to Capture",
            systemImageName: "camera.viewfinder"
        )
    }
}
