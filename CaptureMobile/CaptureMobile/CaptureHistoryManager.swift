//
//  CaptureHistoryManager.swift
//  CaptureMobile
//

import Foundation
import Combine

// MARK: - Processing State

final class CaptureProcessingState: ObservableObject {
    static let shared = CaptureProcessingState()

    @Published var isProcessing: Bool = false
    @Published var hasPendingFailure: Bool = false

    private var activeJobs: [String: Date] = [:]
    private let activeJobsKey = "capture_active_jobs"
    private let failureKey = "capture_has_failure"
    private let jobTimeoutSeconds: TimeInterval = 60

    private init() {
        loadActiveJobs()
        if UserDefaults.standard.bool(forKey: failureKey) { hasPendingFailure = true }
        isProcessing = !activeJobs.isEmpty
    }

    func startProcessing(jobID: String) {
        activeJobs[jobID] = Date()
        saveActiveJobs()
        DispatchQueue.main.async {
            self.isProcessing = true
            self.hasPendingFailure = false
        }
    }

    func markSuccess(jobID: String) {
        activeJobs.removeValue(forKey: jobID)
        saveActiveJobs()
        updateState()
        if activeJobs.isEmpty { UserDefaults.standard.set(false, forKey: failureKey) }
    }

    func stopProcessing(jobID: String) {
        activeJobs.removeValue(forKey: jobID)
        saveActiveJobs()
        updateState()
    }

    func checkForFailure() {
        let timedOut = activeJobs.filter { Date().timeIntervalSince($0.value) > jobTimeoutSeconds }.map(\.key)
        for id in timedOut { activeJobs.removeValue(forKey: id) }
        if !timedOut.isEmpty {
            saveActiveJobs()
            DispatchQueue.main.async { self.hasPendingFailure = true }
            UserDefaults.standard.set(true, forKey: failureKey)
        }
        updateState()
    }

    func clearFailure() {
        DispatchQueue.main.async { self.hasPendingFailure = false }
        UserDefaults.standard.set(false, forKey: failureKey)
    }

    private func updateState() {
        DispatchQueue.main.async { self.isProcessing = !self.activeJobs.isEmpty }
    }

    private func loadActiveJobs() {
        guard let data = UserDefaults.standard.data(forKey: activeJobsKey),
              let jobs = try? JSONDecoder().decode([String: Date].self, from: data) else { return }
        activeJobs = jobs
    }

    private func saveActiveJobs() {
        if let data = try? JSONEncoder().encode(activeJobs) {
            UserDefaults.standard.set(data, forKey: activeJobsKey)
        }
    }
}

// MARK: - Capture Model

struct Capture: Identifiable {
    let id: String
    let title: String
    let category: String
    let captureMethod: String
    let timeCaptured: Date
    let extractedData: [String: Any]
    let imageUrl: String?
    let tags: [String]

    var capturedAgo: String {
        let seconds = Date().timeIntervalSince(timeCaptured)
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        if seconds < 604_800 { return "\(Int(seconds / 86400))d ago" }
        return "\(Int(seconds / 604_800))w ago"
    }

    var methodLabel: String {
        switch captureMethod {
        case "screenshot": return "Screenshot"
        case "photo": return "Photo"
        case "note": return "Note"
        default: return captureMethod.capitalized
        }
    }

    var categoryIcon: String {
        switch category {
        case "restaurant": return "fork.knife"
        case "clothing": return "tshirt.fill"
        case "event": return "calendar"
        case "note": return "note.text"
        case "movie": return "film"
        case "book": return "book.fill"
        default: return "square.grid.2x2"
        }
    }

    init(from record: APIService.CaptureRecord) {
        self.id = record.id
        self.title = record.captureTitle
        self.category = record.category
        self.captureMethod = record.captureMethod
        self.extractedData = record.extractedData.mapValues(\.value)
        self.imageUrl = record.imageUrl
        self.tags = record.tags

        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timeCaptured = fmt.date(from: record.timeCaptured) ?? Date()
    }
}

// MARK: - Capture History Manager

final class CaptureHistoryManager: ObservableObject {
    static let shared = CaptureHistoryManager()

    @Published var captures: [Capture] = []
    @Published var isLoading = false

    private let cacheDirectory: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("captures_cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {}

    @MainActor
    func loadCaptures(category: String? = nil) async {
        guard let userID = AppleAuthManager.shared.getUserID() else { return }

        let cacheKey = category ?? "all"
        if captures.isEmpty, let cached = loadFromCache(key: cacheKey) {
            captures = cached.map { Capture(from: $0) }
        }

        isLoading = true
        let records = await APIService.shared.getCaptures(userID: userID, category: category)
        if !records.isEmpty {
            captures = records.map { Capture(from: $0) }
            saveToCache(records, key: cacheKey)
        }
        isLoading = false
    }

    @MainActor
    func removeCapture(id: String) {
        captures.removeAll { $0.id == id }
    }

    @MainActor
    func deleteCapture(id: String) async {
        guard let userID = AppleAuthManager.shared.getUserID() else { return }
        let backup = captures
        captures.removeAll { $0.id == id }
        let success = await APIService.shared.deleteCapture(captureID: id, userID: userID)
        if !success {
            captures = backup
        }
    }

    @MainActor
    func clearHistory() {
        captures = []
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Disk Cache

    private func cacheURL(for key: String) -> URL {
        cacheDirectory.appendingPathComponent("\(key).json")
    }

    private func saveToCache(_ records: [APIService.CaptureRecord], key: String) {
        DispatchQueue.global(qos: .utility).async {
            guard let data = try? JSONEncoder().encode(records) else { return }
            try? data.write(to: self.cacheURL(for: key))
        }
    }

    private func loadFromCache(key: String) -> [APIService.CaptureRecord]? {
        guard let data = try? Data(contentsOf: cacheURL(for: key)) else { return nil }
        return try? JSONDecoder().decode([APIService.CaptureRecord].self, from: data)
    }
}
