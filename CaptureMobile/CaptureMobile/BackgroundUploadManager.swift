//
//  BackgroundUploadManager.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 29.01.26.
//

import Foundation
import UIKit
import UserNotifications
import PostHog

/// Manages background uploads that survive App Intent/extension termination.
/// Uses iOS background URLSession which continues even after the app is killed.
final class BackgroundUploadManager: NSObject {
    static let shared = BackgroundUploadManager()
    
    // Unique identifier for our background session
    static let sessionIdentifier = "com.capture.backgroundUpload"
    
    // Shared container for App Groups (if needed in future)
    private let apiKey = "bad3515c210e9b769dcb3276cb18553ebff1f0b3935c84f4f1d3aedc064c30e4"
    private let baseURL = "https://capturemobile-production.up.railway.app"
    
    // The background session - lazily created
    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.isDiscretionary = false  // Don't wait for optimal conditions
        config.sessionSendsLaunchEvents = true  // Wake app when done
        config.shouldUseExtendedBackgroundIdleMode = true
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300  // 5 minutes max
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    // Completion handler provided by iOS when waking us up
    var backgroundCompletionHandler: (() -> Void)?
    
    // Store pending task info (keyed by task identifier)
    private var pendingTasks: [Int: PendingTask] = [:]
    
    struct PendingTask {
        let userID: String
        let startTime: Date
    }
    
    private override init() {
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Reconnect to existing background session (call from AppDelegate)
    func reconnectBackgroundSession() {
        // Just accessing the session reconnects it
        _ = backgroundSession
    }
    
    /// Start a background upload for a screenshot
    /// Returns immediately - iOS handles the upload in background
    func uploadScreenshot(_ image: UIImage, userID: String) -> Bool {
        // Encode image
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            sendNotification(title: "Upload Failed", body: "Failed to encode image")
            return false
        }
        
        let base64Image = imageData.base64EncodedString()
        
        // Create request body
        let body: [String: Any] = [
            "image": base64Image,
            "user_id": userID
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            sendNotification(title: "Upload Failed", body: "Failed to create request")
            return false
        }
        
        // Save request body to temp file (background upload requires file)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        
        do {
            try jsonData.write(to: tempURL)
        } catch {
            sendNotification(title: "Upload Failed", body: "Failed to save request data")
            return false
        }
        
        // Create upload request
        guard let url = URL(string: "\(baseURL)/analyze-screenshot") else {
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        
        // Create background upload task
        let task = backgroundSession.uploadTask(with: request, fromFile: tempURL)
        
        // Store task info for when response comes back
        pendingTasks[task.taskIdentifier] = PendingTask(userID: userID, startTime: Date())
        
        // Save pending task info to UserDefaults (persists across app termination)
        savePendingTaskInfo(taskID: task.taskIdentifier, userID: userID)
        
        // Set processing state
        CaptureProcessingState.shared.startProcessing()
        
        // Start the upload
        task.resume()
        
        PostHogSDK.shared.capture("background_upload_started")
        
        return true
    }
    
    // MARK: - Persistence (survives app termination)
    
    private func savePendingTaskInfo(taskID: Int, userID: String) {
        var pending = UserDefaults.standard.dictionary(forKey: "pendingBackgroundTasks") as? [String: String] ?? [:]
        pending["\(taskID)"] = userID
        UserDefaults.standard.set(pending, forKey: "pendingBackgroundTasks")
    }
    
    private func loadPendingTaskInfo(taskID: Int) -> String? {
        let pending = UserDefaults.standard.dictionary(forKey: "pendingBackgroundTasks") as? [String: String] ?? [:]
        return pending["\(taskID)"]
    }
    
    private func removePendingTaskInfo(taskID: Int) {
        var pending = UserDefaults.standard.dictionary(forKey: "pendingBackgroundTasks") as? [String: String] ?? [:]
        pending.removeValue(forKey: "\(taskID)")
        UserDefaults.standard.set(pending, forKey: "pendingBackgroundTasks")
    }
    
    // MARK: - Notifications
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - URLSessionDelegate

extension BackgroundUploadManager: URLSessionDelegate {
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        // Called when all background tasks are done
        // Must call the completion handler on main thread
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}

// MARK: - URLSessionTaskDelegate

extension BackgroundUploadManager: URLSessionTaskDelegate {
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let taskID = task.taskIdentifier
        
        defer {
            removePendingTaskInfo(taskID: taskID)
            pendingTasks.removeValue(forKey: taskID)
            
            DispatchQueue.main.async {
                CaptureProcessingState.shared.stopProcessing()
            }
        }
        
        if let error = error {
            PostHogSDK.shared.capture("background_upload_failed", properties: [
                "error": error.localizedDescription
            ])
            sendNotification(title: "Capture Failed", body: error.localizedDescription)
            return
        }
        
        // Success is handled in urlSession(_:dataTask:didReceive:)
    }
}

// MARK: - URLSessionDataDelegate

extension BackgroundUploadManager: URLSessionDataDelegate {
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Parse the response
        guard let httpResponse = dataTask.response as? HTTPURLResponse else {
            sendNotification(title: "Capture Failed", body: "Invalid response")
            return
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Server error"
            PostHogSDK.shared.capture("background_upload_failed", properties: [
                "status_code": httpResponse.statusCode
            ])
            
            if httpResponse.statusCode == 429 {
                sendNotification(title: "Rate Limited", body: "You've reached your daily limit")
            } else {
                sendNotification(title: "Capture Failed", body: "Server error: \(httpResponse.statusCode)")
            }
            return
        }
        
        // Decode response
        let decoder = JSONDecoder()
        guard let response = try? decoder.decode(APIService.AnalyzeResponse.self, from: data) else {
            sendNotification(title: "Capture Failed", body: "Failed to parse response")
            return
        }
        
        if !response.success || response.eventsToCreate.isEmpty {
            sendNotification(title: "No Events Found", body: "Couldn't detect events in the screenshot")
            return
        }
        
        // Create events locally via EventKit
        let calendarEvents = response.eventsToCreate.map { $0.toCalendarEvent() }
        let (createdIDs, _) = CalendarService.shared.createEvents(calendarEvents)
        
        if createdIDs.isEmpty {
            sendNotification(title: "Calendar Error", body: "Failed to create events in calendar")
            return
        }
        
        // Add to capture history
        for (index, event) in response.eventsToCreate.enumerated() where index < createdIDs.count {
            PostHogSDK.shared.capture("event_created_success", properties: [
                "event_title": event.title,
                "event_count": createdIDs.count,
                "source_app": event.sourceApp ?? "unknown"
            ])
            CaptureHistoryManager.shared.addCapture(event, eventID: createdIDs[index])
        }
        
        // Send success notification
        if createdIDs.count == 1 {
            let title = response.eventsToCreate.first?.title ?? "Event"
            sendNotification(title: "Event Created", body: title)
        } else {
            sendNotification(title: "\(createdIDs.count) Events Created", body: response.message)
        }
        
        PostHogSDK.shared.capture("background_upload_completed", properties: [
            "events_created": createdIDs.count
        ])
        PostHogSDK.shared.flush()
    }
}
