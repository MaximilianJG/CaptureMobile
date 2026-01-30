//
//  PendingJobManager.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 30.01.26.
//

import Foundation

/// Manages pending capture jobs that need to be recovered when the app opens.
/// Used as a fallback when push notifications aren't available.
final class PendingJobManager: ObservableObject {
    static let shared = PendingJobManager()
    
    private let pendingJobsKey = "pending_capture_jobs"
    
    @Published var hasPendingJobs: Bool = false
    
    private init() {
        hasPendingJobs = !getPendingJobs().isEmpty
    }
    
    // MARK: - Job Management
    
    /// Save a job ID as pending
    func savePendingJob(jobID: String) {
        var jobs = getPendingJobs()
        if !jobs.contains(jobID) {
            jobs.append(jobID)
            UserDefaults.standard.set(jobs, forKey: pendingJobsKey)
            DispatchQueue.main.async {
                self.hasPendingJobs = true
            }
        }
    }
    
    /// Get all pending job IDs
    func getPendingJobs() -> [String] {
        return UserDefaults.standard.stringArray(forKey: pendingJobsKey) ?? []
    }
    
    /// Remove a job ID from pending
    func removePendingJob(jobID: String) {
        var jobs = getPendingJobs()
        jobs.removeAll { $0 == jobID }
        UserDefaults.standard.set(jobs, forKey: pendingJobsKey)
        DispatchQueue.main.async {
            self.hasPendingJobs = !jobs.isEmpty
        }
    }
    
    /// Clear all pending jobs
    func clearAllPendingJobs() {
        UserDefaults.standard.removeObject(forKey: pendingJobsKey)
        DispatchQueue.main.async {
            self.hasPendingJobs = false
        }
    }
    
    // MARK: - Recovery
    
    /// Check and recover all pending jobs
    /// Called when the app opens to fetch results for any jobs that completed while app was closed
    func recoverPendingJobs() async {
        let pendingJobs = getPendingJobs()
        
        guard !pendingJobs.isEmpty else { return }
        
        print("Recovering \(pendingJobs.count) pending job(s)...")
        
        for jobID in pendingJobs {
            await recoverJob(jobID: jobID)
        }
    }
    
    /// Recover a single job
    private func recoverJob(jobID: String) async {
        guard let jobStatus = await APIService.shared.checkJobStatus(jobID: jobID) else {
            print("Job \(jobID) not found - removing from pending")
            removePendingJob(jobID: jobID)
            return
        }
        
        switch jobStatus.status {
        case "completed":
            // Create calendar events from the result
            if let events = jobStatus.eventsToCreate, !events.isEmpty {
                let calendarEvents = events.map { $0.toCalendarEvent() }
                let (createdIDs, _) = CalendarService.shared.createEvents(calendarEvents)
                
                // Add to capture history
                for (index, event) in events.enumerated() where index < createdIDs.count {
                    CaptureHistoryManager.shared.addCapture(event, eventID: createdIDs[index])
                }
                
                print("Recovered job \(jobID): created \(createdIDs.count) event(s)")
                
                // Notify user
                sendLocalNotification(
                    title: createdIDs.count == 1 ? "Event Created" : "\(createdIDs.count) Events Created",
                    body: events.first?.title ?? "Events from pending capture"
                )
            }
            removePendingJob(jobID: jobID)
            
        case "failed":
            print("Job \(jobID) failed: \(jobStatus.error ?? "Unknown error")")
            removePendingJob(jobID: jobID)
            
            // Notify user of failure
            sendLocalNotification(
                title: "Capture Failed",
                body: jobStatus.error ?? "Please try again"
            )
            
        case "processing":
            // Still processing - keep it pending
            print("Job \(jobID) still processing")
            
        default:
            print("Job \(jobID) has unknown status: \(jobStatus.status)")
            removePendingJob(jobID: jobID)
        }
    }
    
    // MARK: - Notifications
    
    private func sendLocalNotification(title: String, body: String) {
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

import UserNotifications
