//
//  CalendarService.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 29.01.26.
//

import Foundation
import EventKit
import Combine
import UIKit

/// Manages EventKit calendar access and event creation
final class CalendarService: ObservableObject {
    static let shared = CalendarService()
    
    private let eventStore = EKEventStore()
    
    @Published var calendars: [EKCalendar] = []
    @Published var selectedCalendarID: String?
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    
    private let selectedCalendarKey = "selected_calendar_id"
    
    private init() {
        // Load saved calendar selection
        selectedCalendarID = UserDefaults.standard.string(forKey: selectedCalendarKey)
        
        // Check current authorization status
        updateAuthorizationStatus()
        
        // If authorized, load calendars
        if hasAccess {
            loadCalendars()
        }
    }
    
    // MARK: - Authorization
    
    /// Current authorization status
    private func updateAuthorizationStatus() {
        if #available(iOS 17.0, *) {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        } else {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        }
    }
    
    /// Request calendar access permission
    func requestAccess() async -> Bool {
        do {
            var granted: Bool
            if #available(iOS 17.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await eventStore.requestAccess(to: .event)
            }
            
            await MainActor.run {
                updateAuthorizationStatus()
                if granted {
                    loadCalendars()
                }
            }
            
            return granted
        } catch {
            print("Failed to request calendar access: \(error)")
            return false
        }
    }
    
    /// Check if we have calendar access
    var hasAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }
    
    // MARK: - Calendars
    
    /// Load all writable calendars
    func loadCalendars() {
        let allCalendars = eventStore.calendars(for: .event)
        
        // Filter to only writable calendars
        calendars = allCalendars.filter { $0.allowsContentModifications }
            .sorted { $0.title < $1.title }
        
        // If no calendar selected, select the first one (or default)
        if selectedCalendarID == nil || !calendars.contains(where: { $0.calendarIdentifier == selectedCalendarID }) {
            if let defaultCalendar = eventStore.defaultCalendarForNewEvents {
                selectedCalendarID = defaultCalendar.calendarIdentifier
            } else if let firstCalendar = calendars.first {
                selectedCalendarID = firstCalendar.calendarIdentifier
            }
            saveSelectedCalendar()
        }
    }
    
    /// Get the currently selected calendar
    var selectedCalendar: EKCalendar? {
        guard let id = selectedCalendarID else { return nil }
        return calendars.first { $0.calendarIdentifier == id }
    }
    
    /// Select a calendar by ID
    func selectCalendar(_ calendar: EKCalendar) {
        selectedCalendarID = calendar.calendarIdentifier
        saveSelectedCalendar()
    }
    
    private func saveSelectedCalendar() {
        UserDefaults.standard.set(selectedCalendarID, forKey: selectedCalendarKey)
    }
    
    // MARK: - Event Creation
    
    /// Event data structure matching backend response
    struct ExtractedEvent {
        let title: String
        let date: String  // YYYY-MM-DD
        let startTime: String?  // HH:MM
        let endTime: String?  // HH:MM
        let location: String?
        let description: String?
        let timezone: String?
        let isAllDay: Bool
        let isDeadline: Bool
        let sourceApp: String?
    }
    
    /// Create an event in the selected calendar
    /// Returns the event identifier if successful
    func createEvent(_ eventData: ExtractedEvent) throws -> String {
        guard hasAccess else {
            throw CalendarError.noAccess
        }
        
        guard let calendar = selectedCalendar else {
            throw CalendarError.noCalendarSelected
        }
        
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = eventData.title
        event.location = eventData.location
        
        // Build description
        var descriptionParts: [String] = []
        if let desc = eventData.description {
            descriptionParts.append(desc)
        }
        if eventData.isDeadline, let time = eventData.startTime {
            descriptionParts.append("⏰ Deadline: \(time)")
        }
        descriptionParts.append("\n---\nCreated by Capture")
        event.notes = descriptionParts.joined(separator: "\n")
        
        // Parse dates
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        guard let eventDate = dateFormatter.date(from: eventData.date) else {
            throw CalendarError.invalidDate
        }
        
        // Set timezone
        let timeZone: TimeZone
        if let tzString = eventData.timezone, let tz = TimeZone(identifier: tzString) {
            timeZone = tz
        } else {
            timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        }
        
        if eventData.isAllDay || eventData.startTime == nil {
            // All-day event
            event.isAllDay = true
            event.startDate = eventDate
            event.endDate = eventDate
        } else {
            // Timed event
            event.isAllDay = false
            
            let calendar = Calendar.current
            var startComponents = calendar.dateComponents(in: timeZone, from: eventDate)
            
            // Parse start time
            if let startTime = eventData.startTime {
                let timeParts = startTime.split(separator: ":")
                if timeParts.count >= 2,
                   let hour = Int(timeParts[0]),
                   let minute = Int(timeParts[1]) {
                    startComponents.hour = hour
                    startComponents.minute = minute
                }
            }
            
            guard let startDate = calendar.date(from: startComponents) else {
                throw CalendarError.invalidDate
            }
            event.startDate = startDate
            
            // Parse end time or default to 1 hour
            if let endTime = eventData.endTime {
                var endComponents = calendar.dateComponents(in: timeZone, from: eventDate)
                let timeParts = endTime.split(separator: ":")
                if timeParts.count >= 2,
                   let hour = Int(timeParts[0]),
                   let minute = Int(timeParts[1]) {
                    endComponents.hour = hour
                    endComponents.minute = minute
                    
                    // Handle overnight events
                    if hour < (startComponents.hour ?? 0) {
                        endComponents.day = (endComponents.day ?? 0) + 1
                    }
                }
                
                if let endDate = calendar.date(from: endComponents) {
                    event.endDate = endDate
                } else {
                    event.endDate = startDate.addingTimeInterval(3600)
                }
            } else {
                event.endDate = startDate.addingTimeInterval(3600)
            }
        }
        
        // Add reminder for deadlines
        if eventData.isDeadline {
            let alarm = EKAlarm(relativeOffset: -86400) // 1 day before
            event.addAlarm(alarm)
        }
        
        // Save the event
        try eventStore.save(event, span: .thisEvent)
        
        return event.eventIdentifier
    }
    
    /// Create multiple events, returns array of created event identifiers
    func createEvents(_ events: [ExtractedEvent]) -> (created: [String], failed: Int) {
        var createdIDs: [String] = []
        var failedCount = 0
        
        for eventData in events {
            do {
                let eventID = try createEvent(eventData)
                createdIDs.append(eventID)
            } catch {
                print("Failed to create event '\(eventData.title)': \(error)")
                failedCount += 1
            }
        }
        
        return (createdIDs, failedCount)
    }
    
    // MARK: - Fetch Event
    
    /// Fetch an event by its identifier
    func getEvent(withIdentifier identifier: String) -> EKEvent? {
        return eventStore.event(withIdentifier: identifier)
    }
    
    /// Get the event store (needed for EKEventViewController)
    var store: EKEventStore {
        return eventStore
    }
    
    // MARK: - Errors
    
    enum CalendarError: LocalizedError {
        case noAccess
        case noCalendarSelected
        case invalidDate
        case saveFailed
        
        var errorDescription: String? {
            switch self {
            case .noAccess:
                return "Calendar access not granted. Please enable in Settings."
            case .noCalendarSelected:
                return "No calendar selected. Please select a calendar."
            case .invalidDate:
                return "Invalid event date or time."
            case .saveFailed:
                return "Failed to save event to calendar."
            }
        }
    }
}

// MARK: - Calendar Display Helpers

extension EKCalendar {
    /// Display name with account info
    var displayName: String {
        if let sourceName = source?.title, sourceName != title {
            return "\(title) - \(sourceName)"
        }
        return title
    }
    
    /// Get UIColor from CGColor
    var uiColor: UIColor {
        return UIColor(cgColor: cgColor)
    }
}
