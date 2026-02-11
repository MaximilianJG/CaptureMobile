//
//  BackgroundUploadManager.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 17.01.26.
//

import Foundation
import UIKit

/// Manages a persistent queue of screenshot uploads with retry logic.
///
/// When a capture upload fails (e.g., network error), the image is saved to disk and
/// retried later. The queue is processed serially to avoid overwhelming the network
/// or backend. Pending uploads survive app restarts and are retried on next launch.
final class BackgroundUploadManager {
    static let shared = BackgroundUploadManager()
    
    // MARK: - Configuration
    
    /// Maximum number of retry attempts per upload before discarding
    private let maxRetries = 3
    
    /// Base delay for exponential backoff (seconds): 2s, 4s, 8s
    private let baseRetryDelay: TimeInterval = 2.0
    
    /// Maximum age for a pending upload before it's discarded (1 hour)
    private let maxUploadAge: TimeInterval = 3600
    
    // MARK: - State
    
    /// Serial queue to protect shared state
    private let serialQueue = DispatchQueue(label: "com.capture.uploadmanager")
    
    /// Whether the queue is currently being processed
    private var isProcessing = false
    
    // MARK: - File Paths
    
    /// Directory for storing pending upload images
    private var pendingUploadsDirectory: URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = documentsDir.appendingPathComponent("pending_uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    /// Path to the metadata JSON file
    private var metadataFileURL: URL {
        return pendingUploadsDirectory.appendingPathComponent("metadata.json")
    }
    
    // MARK: - Metadata Model
    
    /// Metadata for a single pending upload
    struct PendingUpload: Codable, Identifiable {
        let id: String
        let userID: String
        let createdAt: Date
        var retryCount: Int
        /// Filename of the image data on disk (relative to pending_uploads/)
        let imageFilename: String
    }
    
    private init() {}
    
    // MARK: - Public API
    
    /// Enqueue a failed upload for retry.
    /// Saves the image to disk and adds metadata to the queue.
    /// - Parameters:
    ///   - image: The screenshot that failed to upload
    ///   - userID: The user's Apple ID
    /// - Returns: The pending upload ID (for tracking)
    @discardableResult
    func enqueue(image: UIImage, userID: String) -> String {
        let uploadID = UUID().uuidString
        let imageFilename = "\(uploadID).jpg"
        
        // Save image to disk
        let imageURL = pendingUploadsDirectory.appendingPathComponent(imageFilename)
        if let imageData = image.jpegData(compressionQuality: 0.8) {
            try? imageData.write(to: imageURL)
        } else {
            print("BackgroundUploadManager: Failed to encode image for \(uploadID)")
            return uploadID
        }
        
        // Add metadata
        var uploads = loadMetadata()
        let pending = PendingUpload(
            id: uploadID,
            userID: userID,
            createdAt: Date(),
            retryCount: 0,
            imageFilename: imageFilename
        )
        uploads.append(pending)
        saveMetadata(uploads)
        
        print("BackgroundUploadManager: Enqueued upload \(uploadID.prefix(8))... (\(uploads.count) total pending)")
        
        return uploadID
    }
    
    /// Process all pending uploads serially.
    /// Called on app launch and can be called manually to retry.
    /// Safe to call multiple times - only one processing loop runs at a time.
    func processPendingUploads() async {
        // Ensure only one processing loop runs at a time
        let shouldProcess: Bool = serialQueue.sync {
            if isProcessing { return false }
            isProcessing = true
            return true
        }
        
        guard shouldProcess else {
            print("BackgroundUploadManager: Already processing, skipping")
            return
        }
        
        defer {
            serialQueue.sync { isProcessing = false }
        }
        
        var uploads = loadMetadata()
        guard !uploads.isEmpty else { return }
        
        print("BackgroundUploadManager: Processing \(uploads.count) pending upload(s)...")
        
        // Process each upload serially
        var uploadsToRemove: [String] = []
        
        for (index, upload) in uploads.enumerated() {
            // Skip uploads that are too old
            if Date().timeIntervalSince(upload.createdAt) > maxUploadAge {
                print("BackgroundUploadManager: Upload \(upload.id.prefix(8))... expired, removing")
                uploadsToRemove.append(upload.id)
                continue
            }
            
            // Skip uploads that have exceeded max retries
            if upload.retryCount >= maxRetries {
                print("BackgroundUploadManager: Upload \(upload.id.prefix(8))... exceeded max retries, removing")
                uploadsToRemove.append(upload.id)
                continue
            }
            
            // Wait with exponential backoff before retrying (skip for first attempt)
            if upload.retryCount > 0 {
                let delay = baseRetryDelay * pow(2.0, Double(upload.retryCount - 1))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            
            // Load image from disk
            let imageURL = pendingUploadsDirectory.appendingPathComponent(upload.imageFilename)
            guard let imageData = try? Data(contentsOf: imageURL),
                  let image = UIImage(data: imageData) else {
                print("BackgroundUploadManager: Image file missing for \(upload.id.prefix(8))..., removing")
                uploadsToRemove.append(upload.id)
                continue
            }
            
            // Attempt upload
            if let jobID = await APIService.shared.uploadScreenshotAsync(image, userID: upload.userID) {
                print("BackgroundUploadManager: Upload \(upload.id.prefix(8))... succeeded (job: \(jobID.prefix(8))...)")
                
                // Track the new job
                CaptureProcessingState.shared.startProcessing(jobID: jobID)
                PendingJobManager.shared.savePendingJob(jobID: jobID)
                
                uploadsToRemove.append(upload.id)
            } else {
                // Upload failed - increment retry count
                uploads[index].retryCount += 1
                print("BackgroundUploadManager: Upload \(upload.id.prefix(8))... failed (attempt \(uploads[index].retryCount)/\(maxRetries))")
            }
        }
        
        // Remove completed/expired/failed uploads
        for uploadID in uploadsToRemove {
            removeUpload(uploadID, from: &uploads)
        }
        
        // Save updated metadata
        saveMetadata(uploads)
        
        print("BackgroundUploadManager: Done. \(uploads.count) upload(s) remaining.")
    }
    
    /// Number of pending uploads
    var pendingCount: Int {
        return loadMetadata().count
    }
    
    /// Clear all pending uploads (e.g., on sign out)
    func clearAll() {
        saveMetadata([])
        // Remove all image files
        if let files = try? FileManager.default.contentsOfDirectory(at: pendingUploadsDirectory, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "jpg" {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func loadMetadata() -> [PendingUpload] {
        guard let data = try? Data(contentsOf: metadataFileURL) else {
            return []
        }
        return (try? JSONDecoder().decode([PendingUpload].self, from: data)) ?? []
    }
    
    private func saveMetadata(_ uploads: [PendingUpload]) {
        if let data = try? JSONEncoder().encode(uploads) {
            try? data.write(to: metadataFileURL)
        }
    }
    
    private func removeUpload(_ uploadID: String, from uploads: inout [PendingUpload]) {
        // Remove image file
        if let upload = uploads.first(where: { $0.id == uploadID }) {
            let imageURL = pendingUploadsDirectory.appendingPathComponent(upload.imageFilename)
            try? FileManager.default.removeItem(at: imageURL)
        }
        
        // Remove from array
        uploads.removeAll { $0.id == uploadID }
    }
}
