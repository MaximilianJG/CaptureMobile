//
//  PendingJobManager.swift
//  CaptureMobile
//

import Foundation
import Combine
import UserNotifications

final class PendingJobManager: ObservableObject {
    static let shared = PendingJobManager()

    private let pendingJobsKey = "pending_capture_jobs"
    private let completedJobsKey = "completed_capture_jobs"

    private let recoveringQueue = DispatchQueue(label: "com.capture.recoveringJobs")
    private var recoveringJobIDs: Set<String> = []

    @Published var hasPendingJobs: Bool = false

    private init() {
        hasPendingJobs = !getPendingJobs().isEmpty
        pruneCompletedJobs()
    }

    func savePendingJob(jobID: String) {
        var jobs = getPendingJobs()
        if !jobs.contains(jobID) {
            jobs.append(jobID)
            UserDefaults.standard.set(jobs, forKey: pendingJobsKey)
            DispatchQueue.main.async { self.hasPendingJobs = true }
        }
    }

    func getPendingJobs() -> [String] {
        UserDefaults.standard.stringArray(forKey: pendingJobsKey) ?? []
    }

    func removePendingJob(jobID: String) {
        var jobs = getPendingJobs()
        jobs.removeAll { $0 == jobID }
        UserDefaults.standard.set(jobs, forKey: pendingJobsKey)
        markJobCompleted(jobID)
        DispatchQueue.main.async { self.hasPendingJobs = !jobs.isEmpty }
    }

    func clearAllPendingJobs() {
        UserDefaults.standard.removeObject(forKey: pendingJobsKey)
        DispatchQueue.main.async { self.hasPendingJobs = false }
    }

    // MARK: - Completed Job Tracking

    private func markJobCompleted(_ jobID: String) {
        var completed = getCompletedJobs()
        completed[jobID] = Date()
        saveCompletedJobs(completed)
    }

    func markJobAsProcessing(_ jobID: String) { markJobCompleted(jobID) }

    func isJobCompleted(_ jobID: String) -> Bool {
        getCompletedJobs()[jobID] != nil
    }

    private func getCompletedJobs() -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: completedJobsKey),
              let jobs = try? JSONDecoder().decode([String: Date].self, from: data) else { return [:] }
        return jobs
    }

    private func saveCompletedJobs(_ jobs: [String: Date]) {
        if let data = try? JSONEncoder().encode(jobs) {
            UserDefaults.standard.set(data, forKey: completedJobsKey)
        }
    }

    private func pruneCompletedJobs() {
        var completed = getCompletedJobs()
        let cutoff = Date().addingTimeInterval(-3600)
        completed = completed.filter { $0.value > cutoff }
        saveCompletedJobs(completed)
    }

    // MARK: - Recovery

    func recoverPendingJobs() async {
        let pendingJobs = getPendingJobs()
        guard !pendingJobs.isEmpty else { return }
        print("Recovering \(pendingJobs.count) pending job(s)...")
        for jobID in pendingJobs {
            await recoverJob(jobID: jobID)
        }
    }

    private func claimForRecovery(_ jobID: String) -> Bool {
        recoveringQueue.sync { recoveringJobIDs.insert(jobID).inserted }
    }

    private func releaseRecoveryClaim(_ jobID: String) {
        recoveringQueue.sync { _ = recoveringJobIDs.remove(jobID) }
    }

    private func recoverJob(jobID: String) async {
        guard !isJobCompleted(jobID) else {
            removePendingJob(jobID: jobID)
            return
        }
        guard claimForRecovery(jobID) else { return }
        defer { releaseRecoveryClaim(jobID) }

        guard let jobStatus = await APIService.shared.checkJobStatus(jobID: jobID) else {
            removePendingJob(jobID: jobID)
            return
        }

        guard !isJobCompleted(jobID) else { return }

        switch jobStatus.status {
        case "completed":
            markJobCompleted(jobID)
            removePendingJob(jobID: jobID)
            CaptureProcessingState.shared.markSuccess(jobID: jobID)

            // Refresh the captures list
            Task { @MainActor in
                await CaptureHistoryManager.shared.loadCaptures()
            }

            if let record = jobStatus.capture {
                sendLocalNotification(
                    title: "Capture Saved",
                    body: record.captureTitle
                )

                if record.category == "event" {
                    let capture = Capture(from: record)
                    Task {
                        await CalendarService.shared.createEventFromCapture(capture)
                    }
                }
            }

        case "failed":
            removePendingJob(jobID: jobID)
            CaptureProcessingState.shared.stopProcessing(jobID: jobID)
            sendLocalNotification(title: "Capture Failed", body: jobStatus.error ?? "Please try again")

        case "processing":
            break

        default:
            removePendingJob(jobID: jobID)
        }
    }

    private func sendLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
