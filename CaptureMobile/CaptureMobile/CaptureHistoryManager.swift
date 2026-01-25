//
//  CaptureHistoryManager.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 21.01.26.
//

import Foundation
import Combine

/// Represents a captured event stored in local history
struct CapturedEvent: Codable, Identifiable {
    let id: String
    let title: String
    let startTime: String
    let calendarLink: String?
    let sourceApp: String?
    let capturedAt: Date
    
    /// Creates a CapturedEvent from an API EventDetails response
    init(from eventDetails: APIService.EventDetails) {
        self.id = eventDetails.id ?? UUID().uuidString
        self.title = eventDetails.title
        self.startTime = eventDetails.startTime
        self.calendarLink = eventDetails.calendarLink
        self.sourceApp = eventDetails.sourceApp
        self.capturedAt = Date()
    }
    
    /// Creates a CapturedEvent directly (for testing)
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
    
    private let maxCaptures = 5
    private let storageKey = "recent_captures"
    
    @Published var recentCaptures: [CapturedEvent] = []
    
    private init() {
        loadCaptures()
    }
    
    // MARK: - Public Methods
    
    /// Adds a new capture to the history
    /// - Parameter eventDetails: The event details from the API response
    func addCapture(_ eventDetails: APIService.EventDetails) {
        let capture = CapturedEvent(from: eventDetails)
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
