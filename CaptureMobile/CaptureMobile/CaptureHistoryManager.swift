//
//  CaptureHistoryManager.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 21.01.26.
//

import Foundation
import Combine

// MARK: - Processing State

/// Tracks whether a capture is currently being processed
/// Used to show "Analyzing..." placeholder in the UI
final class CaptureProcessingState: ObservableObject {
    static let shared = CaptureProcessingState()
    
    @Published var isProcessing: Bool = false
    @Published var startedAt: Date?
    
    private init() {
        // Check if we were processing when app was killed
        // (processing state is stored in UserDefaults for persistence)
        let wasProcessing = UserDefaults.standard.bool(forKey: "capture_is_processing")
        if wasProcessing {
            // Check if it's been more than 2 minutes (probably failed/stuck)
            if let startTime = UserDefaults.standard.object(forKey: "capture_processing_start") as? Date,
               Date().timeIntervalSince(startTime) > 120 {
                // Clear stale processing state
                stopProcessing()
            } else {
                isProcessing = true
                startedAt = UserDefaults.standard.object(forKey: "capture_processing_start") as? Date
            }
        }
    }
    
    func startProcessing() {
        DispatchQueue.main.async {
            self.isProcessing = true
            self.startedAt = Date()
            UserDefaults.standard.set(true, forKey: "capture_is_processing")
            UserDefaults.standard.set(Date(), forKey: "capture_processing_start")
        }
    }
    
    func stopProcessing() {
        DispatchQueue.main.async {
            self.isProcessing = false
            self.startedAt = nil
            UserDefaults.standard.set(false, forKey: "capture_is_processing")
            UserDefaults.standard.removeObject(forKey: "capture_processing_start")
        }
    }
}

// MARK: - Captured Event

/// Represents a captured event stored in local history
struct CapturedEvent: Codable, Identifiable {
    let id: String
    let title: String
    let startTime: String
    let calendarLink: String?
    let sourceApp: String?
    let capturedAt: Date
    
    /// Creates a CapturedEvent from an ExtractedEventInfo response
    init(from eventInfo: APIService.ExtractedEventInfo, eventID: String? = nil) {
        self.id = eventID ?? UUID().uuidString
        self.title = eventInfo.title
        // Build start time string from date and time
        if let time = eventInfo.startTime {
            self.startTime = "\(eventInfo.date)T\(time)"
        } else {
            self.startTime = eventInfo.date
        }
        self.calendarLink = nil  // EventKit events don't have web links
        self.sourceApp = eventInfo.sourceApp
        self.capturedAt = Date()
    }
    
    /// Creates a CapturedEvent directly (for testing or direct creation)
    init(id: String, title: String, startTime: String, calendarLink: String?, sourceApp: String?, capturedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.calendarLink = calendarLink
        self.sourceApp = sourceApp
        self.capturedAt = capturedAt
    }
}

/// Manages the local storage of recent captures using UserDefaults
final class CaptureHistoryManager: ObservableObject {
    static let shared = CaptureHistoryManager()
    
    private let maxCaptures = 20
    private let storageKey = "recent_captures"
    
    @Published var recentCaptures: [CapturedEvent] = []
    
    private init() {
        loadCaptures()
    }
    
    // MARK: - Public Methods
    
    /// Adds a new capture to the history from extracted event info
    /// - Parameters:
    ///   - eventInfo: The event info from the API response
    ///   - eventID: Optional EventKit event identifier
    func addCapture(_ eventInfo: APIService.ExtractedEventInfo, eventID: String? = nil) {
        let capture = CapturedEvent(from: eventInfo, eventID: eventID)
        addCapture(capture)
    }
    
    /// Adds a captured event to the history
    /// - Parameter capture: The captured event to add
    func addCapture(_ capture: CapturedEvent) {
        var captures = recentCaptures
        
        // Remove any existing capture with the same ID
        captures.removeAll { $0.id == capture.id }
        
        // Insert at the beginning (most recent first)
        captures.insert(capture, at: 0)
        
        // Keep only the most recent captures
        if captures.count > maxCaptures {
            captures = Array(captures.prefix(maxCaptures))
        }
        
        recentCaptures = captures
        saveCaptures()
    }
    
    /// Returns the most recent captures
    /// - Returns: Array of captured events, most recent first
    func getRecentCaptures() -> [CapturedEvent] {
        return recentCaptures
    }
    
    /// Clears all capture history
    func clearHistory() {
        recentCaptures = []
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
    
    // MARK: - Private Methods
    
    private func loadCaptures() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            recentCaptures = []
            return
        }
        
        do {
            let decoder = JSONDecoder()
            recentCaptures = try decoder.decode([CapturedEvent].self, from: data)
        } catch {
            print("Failed to load capture history: \(error)")
            recentCaptures = []
        }
    }
    
    private func saveCaptures() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(recentCaptures)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to save capture history: \(error)")
        }
    }
}

// MARK: - Helper Extensions

extension CapturedEvent {
    /// Returns the parsed event date, or nil if parsing fails
    var eventDate: Date? {
        // Try different formats
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        
        // Try full ISO format first
        if let date = isoFormatter.date(from: startTime) {
            return date
        }
        
        // Try date with time
        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let date = dateTimeFormatter.date(from: startTime) {
            return date
        }
        
        // Try date only format
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        if let date = dateOnlyFormatter.date(from: startTime) {
            return date
        }
        
        return nil
    }
    
    /// Returns a formatted date string for display
    var formattedDate: String {
        // Parse the ISO date string
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        
        // Try different formats
        var date: Date?
        
        // Try full ISO format first
        date = isoFormatter.date(from: startTime)
        
        // Try date only format
        if date == nil {
            let dateOnlyFormatter = DateFormatter()
            dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
            date = dateOnlyFormatter.date(from: startTime)
        }
        
        // Try date with time
        if date == nil {
            let dateTimeFormatter = DateFormatter()
            dateTimeFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
            date = dateTimeFormatter.date(from: startTime)
        }
        
        guard let parsedDate = date else {
            return startTime // Return raw string if parsing fails
        }
        
        // Format for display
        let displayFormatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(parsedDate) {
            displayFormatter.dateFormat = "'Today,' HH:mm"
        } else if calendar.isDateInTomorrow(parsedDate) {
            displayFormatter.dateFormat = "'Tomorrow,' HH:mm"
        } else if calendar.isDate(parsedDate, equalTo: Date(), toGranularity: .weekOfYear) {
            displayFormatter.dateFormat = "EEEE, HH:mm" // e.g., "Friday, 14:00"
        } else {
            displayFormatter.dateFormat = "MMM d, HH:mm" // e.g., "Jan 25, 14:00"
        }
        
        return displayFormatter.string(from: parsedDate)
    }
    
    /// Returns a short relative time string for when it was captured
    var capturedAgo: String {
        let now = Date()
        let seconds = now.timeIntervalSince(capturedAt)
        
        if seconds < 60 {
            return "Just now"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes)m ago"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return "\(hours)h ago"
        } else if seconds < 604800 {
            let days = Int(seconds / 86400)
            return "\(days)d ago"
        } else {
            let weeks = Int(seconds / 604800)
            return "\(weeks)w ago"
        }
    }
    
    /// Returns an SF Symbol name for the source app
    var sourceAppIcon: String {
        guard let app = sourceApp?.lowercased() else {
            return "app.fill"
        }
        
        switch app {
        case "whatsapp":
            return "message.fill"
        case "imessage", "messages":
            return "message.fill"
        case "instagram":
            return "camera.fill"
        case "gmail", "mail", "outlook":
            return "envelope.fill"
        case "linkedin":
            return "person.2.fill"
        case "slack":
            return "number.square.fill"
        case "microsoft teams", "teams":
            return "video.fill"
        case "calendar":
            return "calendar"
        case "notes":
            return "note.text"
        case "twitter", "x":
            return "at"
        case "messenger", "facebook messenger":
            return "bubble.left.and.bubble.right.fill"
        case "telegram":
            return "paperplane.fill"
        default:
            return "app.fill"
        }
    }
}
