//
//  PendingJobManager.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 30.01.26.
//

import Foundation
import Combine
import UserNotifications

/// Manages pending capture jobs that need to be recovered when the app opens.
/// Used as a fallback when push notifications aren't available.
final class PendingJobManager: ObservableObject {
    static let shared = PendingJobManager()
    
    private let pendingJobsKey = "pending_capture_jobs"
    private let completedJobsKey = "completed_capture_jobs"
    
    /// Thread-safe set of job IDs currently being recovered, to prevent concurrent
    /// recovery of the same job (e.g. if recoverPendingJobs is called while push
    /// handler is also processing the same job).
    private let recoveringQueue = DispatchQueue(label: "com.capture.recoveringJobs")
    private var recoveringJobIDs: Set<String> = []
    
    @Published var hasPendingJobs: Bool = false
    
    private init() {
        hasPendingJobs = !getPendingJobs().isEmpty
        pruneCompletedJobs()
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
    
    /// Remove a job ID from pending and mark it as completed.
    /// Completed jobs are tracked to prevent re-processing by recovery.
    func removePendingJob(jobID: String) {
        var jobs = getPendingJobs()
        jobs.removeAll { $0 == jobID }
        UserDefaults.standard.set(jobs, forKey: pendingJobsKey)
        
        // Track as completed so recoverPendingJobs won't re-process it
        markJobCompleted(jobID)
        
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
    
    // MARK: - Completed Job Tracking
    
    /// Mark a job as completed to prevent duplicate processing
    private func markJobCompleted(_ jobID: String) {
        var completed = getCompletedJobs()
        completed[jobID] = Date()
        saveCompletedJobs(completed)
    }
    
    /// Mark a job as being processed by the push handler.
    /// This prevents the recovery system from racing and creating duplicate events.
    func markJobAsProcessing(_ jobID: String) {
        markJobCompleted(jobID)
    }
    
    /// Check if a job has already been completed
    func isJobCompleted(_ jobID: String) -> Bool {
        return getCompletedJobs()[jobID] != nil
    }
    
    private func getCompletedJobs() -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: completedJobsKey),
              let jobs = try? JSONDecoder().decode([String: Date].self, from: data) else {
            return [:]
        }
        return jobs
    }
    
    private func saveCompletedJobs(_ jobs: [String: Date]) {
        if let data = try? JSONEncoder().encode(jobs) {
            UserDefaults.standard.set(data, forKey: completedJobsKey)
        }
    }
    
    /// Remove completed jobs older than 1 hour to prevent unbounded growth
    private func pruneCompletedJobs() {
        var completed = getCompletedJobs()
        let cutoff = Date().addingTimeInterval(-3600)
        completed = completed.filter { $0.value > cutoff }
        saveCompletedJobs(completed)
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
    
    /// Atomically claim a job for recovery. Returns true if claimed, false if already being recovered.
    private func claimForRecovery(_ jobID: String) -> Bool {
        return recoveringQueue.sync {
            let (inserted, _) = recoveringJobIDs.insert(jobID)
            return inserted
        }
    }
    
    private func releaseRecoveryClaim(_ jobID: String) {
        recoveringQueue.sync {
            _ = recoveringJobIDs.remove(jobID)
        }
    }
    
    /// Recover a single job
    private func recoverJob(jobID: String) async {
        // Skip if this job was already completed by the push notification handler
        guard !isJobCompleted(jobID) else {
            print("Job \(jobID.prefix(8)) already completed - removing from pending")
            removePendingJob(jobID: jobID)
            return
        }
        
        // Prevent concurrent recovery of the same job
        guard claimForRecovery(jobID) else {
            print("Job \(jobID.prefix(8)) already being recovered - skipping")
            return
        }
        defer { releaseRecoveryClaim(jobID) }
        
        guard let jobStatus = await APIService.shared.checkJobStatus(jobID: jobID) else {
            print("Job \(jobID) not found - removing from pending")
            removePendingJob(jobID: jobID)
            return
        }
        
        // Double-check after the async network call: the push handler may have
        // processed this job while we were waiting for the API response.
        guard !isJobCompleted(jobID) else {
            print("Job \(jobID.prefix(8)) completed while fetching status - skipping")
            return
        }
        
        switch jobStatus.status {
        case "completed":
            // Final check right before creating events - the push handler may have
            // marked this job as completed while we were fetching the status.
            guard !isJobCompleted(jobID) else {
                print("Job \(jobID.prefix(8)) completed by push handler before event creation - skipping")
                removePendingJob(jobID: jobID)
                return
            }
            
            // Mark as completed BEFORE creating events to prevent the push handler
            // from racing and creating duplicates.
            markJobCompleted(jobID)
            
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
