//
//  APIService.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 17.01.26.
//

import Foundation
import UIKit
import PostHog

final class APIService {
    static let shared = APIService()
    private init() {}
    
    // MARK: - Configuration
    private let baseURL = "https://capturemobile-production.up.railway.app"
    
    // API Key for backend authentication
    // IMPORTANT: This must match API_SECRET_KEY in your Railway environment
    private let apiKey = "bad3515c210e9b769dcb3276cb18553ebff1f0b3935c84f4f1d3aedc064c30e4"
    
    // MARK: - Errors
    enum APIError: LocalizedError {
        case invalidURL
        case noUserID
        case encodingFailed
        case networkError(Error)
        case serverError(Int, String?)
        case decodingFailed
        case noEventFound
        case rateLimited(String)
        case imageTooLarge
        case calendarError(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL configuration"
            case .noUserID:
                return "Not authenticated. Please sign in again."
            case .encodingFailed:
                return "Failed to encode image"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .serverError(let code, let message):
                return "Server error (\(code)): \(message ?? "Unknown error")"
            case .decodingFailed:
                return "Failed to parse server response"
            case .noEventFound:
                return "No event was detected in the screenshot"
            case .rateLimited(let message):
                return message
            case .imageTooLarge:
                return "Image is too large. Please try a smaller screenshot."
            case .calendarError(let message):
                return message
            }
        }
    }
    
    // MARK: - Response Models
    
    /// Response from backend - contains events to create locally
    struct AnalyzeResponse: Codable {
        let success: Bool
        let eventsToCreate: [ExtractedEventInfo]
        let message: String
        
        enum CodingKeys: String, CodingKey {
            case success
            case eventsToCreate = "events_to_create"
            case message
        }
        
        /// Number of events found
        var eventCount: Int {
            return eventsToCreate.count
        }
    }
    
    /// Event info extracted by backend (matches backend ExtractedEventInfo schema)
    struct ExtractedEventInfo: Codable {
        let title: String
        let date: String
        let startTime: String?
        let endTime: String?
        let location: String?
        let description: String?
        let timezone: String?
        let isAllDay: Bool
        let isDeadline: Bool
        let confidence: Double
        let attendeeName: String?
        let sourceApp: String?
        
        enum CodingKeys: String, CodingKey {
            case title
            case date
            case startTime = "start_time"
            case endTime = "end_time"
            case location
            case description
            case timezone
            case isAllDay = "is_all_day"
            case isDeadline = "is_deadline"
            case confidence
            case attendeeName = "attendee_name"
            case sourceApp = "source_app"
        }
        
        /// Convert to CalendarService.ExtractedEvent
        func toCalendarEvent() -> CalendarService.ExtractedEvent {
            return CalendarService.ExtractedEvent(
                title: title,
                date: date,
                startTime: startTime,
                endTime: endTime,
                location: location,
                description: description,
                timezone: timezone,
                isAllDay: isAllDay,
                isDeadline: isDeadline,
                sourceApp: sourceApp
            )
        }
    }
    
    /// Result after creating events locally
    struct CaptureResult {
        let eventsCreated: Int
        let eventsFailed: Int
        let firstEventTitle: String?
        let message: String
    }
    
    // MARK: - Analyze Screenshot
    /// Sends a screenshot to the backend for analysis and creates events locally
    /// - Parameter image: The screenshot image to analyze
    /// - Returns: The capture result with created event info
    func analyzeAndCreateEvents(_ image: UIImage) async throws -> CaptureResult {
        // Track screenshot sent
        PostHogSDK.shared.capture("screenshot_sent")
        
        // Get user ID
        guard let userID = AppleAuthManager.shared.getUserID() else {
            PostHogSDK.shared.capture("event_created_failed", properties: [
                "error": "no_user_id"
            ])
            throw APIError.noUserID
        }
        
        // Encode image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            PostHogSDK.shared.capture("event_created_failed", properties: [
                "error": "encoding_failed"
            ])
            throw APIError.encodingFailed
        }
        let base64Image = imageData.base64EncodedString()
        
        // Build request
        guard let url = URL(string: "\(baseURL)/analyze-screenshot") else {
            PostHogSDK.shared.capture("event_created_failed", properties: [
                "error": "invalid_url"
            ])
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 120 // 2 minutes for complex screenshots with many events
        
        let body: [String: Any] = [
            "image": base64Image,
            "user_id": userID
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        // Send request
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            PostHogSDK.shared.capture("event_created_failed", properties: [
                "error": "network_error",
                "details": error.localizedDescription
            ])
            throw APIError.networkError(error)
        }
        
        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            PostHogSDK.shared.capture("event_created_failed", properties: [
                "error": "bad_response"
            ])
            throw APIError.networkError(URLError(.badServerResponse))
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8)
            PostHogSDK.shared.capture("event_created_failed", properties: [
                "error": "server_error",
                "status_code": httpResponse.statusCode
            ])
            
            // Handle specific error codes
            switch httpResponse.statusCode {
            case 429:
                let message = parseErrorDetail(from: data) ?? "You've reached your daily limit. Try again tomorrow."
                throw APIError.rateLimited(message)
            case 413:
                throw APIError.imageTooLarge
            default:
                throw APIError.serverError(httpResponse.statusCode, errorMessage)
            }
        }
        
        // Decode response
        let decoder = JSONDecoder()
        guard let analyzeResponse = try? decoder.decode(AnalyzeResponse.self, from: data) else {
            PostHogSDK.shared.capture("event_created_failed", properties: [
                "error": "decoding_failed"
            ])
            throw APIError.decodingFailed
        }
        
        // Check if events were found
        if !analyzeResponse.success || analyzeResponse.eventsToCreate.isEmpty {
            PostHogSDK.shared.capture("event_created_failed", properties: [
                "error": "no_events_found"
            ])
            throw APIError.noEventFound
        }
        
        // Create events locally via EventKit
        let calendarEvents = analyzeResponse.eventsToCreate.map { $0.toCalendarEvent() }
        let (createdIDs, failedCount) = CalendarService.shared.createEvents(calendarEvents)
        
        // Track results
        if createdIDs.isEmpty {
            PostHogSDK.shared.capture("event_created_failed", properties: [
                "error": "calendar_creation_failed",
                "events_found": analyzeResponse.eventCount
            ])
            throw APIError.calendarError("Failed to create events in calendar")
        }
        
        // Track success and add to capture history
        for (index, event) in analyzeResponse.eventsToCreate.enumerated() where index < createdIDs.count {
            PostHogSDK.shared.capture("event_created_success", properties: [
                "event_title": event.title,
                "event_count": createdIDs.count,
                "source_app": event.sourceApp ?? "unknown"
            ])
            
            // Add to capture history
            CaptureHistoryManager.shared.addCapture(event, eventID: createdIDs[index])
        }
        
        // Build result
        let firstTitle = analyzeResponse.eventsToCreate.first?.title
        let message: String
        if createdIDs.count == 1 {
            message = "Event '\(firstTitle ?? "Event")' created successfully!"
        } else if failedCount == 0 {
            message = "Successfully created \(createdIDs.count) events!"
        } else {
            message = "Created \(createdIDs.count) of \(analyzeResponse.eventCount) events (\(failedCount) failed)."
        }
        
        return CaptureResult(
            eventsCreated: createdIDs.count,
            eventsFailed: failedCount,
            firstEventTitle: firstTitle,
            message: message
        )
    }
    
    // MARK: - Helper Methods
    /// Parse error detail from JSON response
    private func parseErrorDetail(from data: Data) -> String? {
        struct ErrorResponse: Codable {
            let detail: String
        }
        return try? JSONDecoder().decode(ErrorResponse.self, from: data).detail
    }
    
    // MARK: - Health Check
    /// Checks if the backend is available
    func healthCheck() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else {
            return false
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

// MARK: - Debug Extension
#if DEBUG
extension APIService {
    /// Mock response for testing without backend (single event)
    func mockAnalyzeResponse() -> AnalyzeResponse {
        return AnalyzeResponse(
            success: true,
            eventsToCreate: [
                ExtractedEventInfo(
                    title: "Team Meeting",
                    date: "2026-01-20",
                    startTime: "10:00",
                    endTime: "11:00",
                    location: "Conference Room A",
                    description: "Weekly team sync",
                    timezone: "Europe/Berlin",
                    isAllDay: false,
                    isDeadline: false,
                    confidence: 0.9,
                    attendeeName: nil,
                    sourceApp: "WhatsApp"
                )
            ],
            message: "Found event: 'Team Meeting'"
        )
    }
    
    /// Mock response for testing multiple events
    func mockAnalyzeResponseMultiple() -> AnalyzeResponse {
        return AnalyzeResponse(
            success: true,
            eventsToCreate: [
                ExtractedEventInfo(
                    title: "Team Meeting",
                    date: "2026-01-20",
                    startTime: "10:00",
                    endTime: "11:00",
                    location: "Conference Room A",
                    description: "Weekly team sync",
                    timezone: "Europe/Berlin",
                    isAllDay: false,
                    isDeadline: false,
                    confidence: 0.9,
                    attendeeName: nil,
                    sourceApp: "WhatsApp"
                ),
                ExtractedEventInfo(
                    title: "Lunch with Sarah",
                    date: "2026-01-20",
                    startTime: "12:30",
                    endTime: "13:30",
                    location: "Cafe Berlin",
                    description: "Catch up over lunch",
                    timezone: "Europe/Berlin",
                    isAllDay: false,
                    isDeadline: false,
                    confidence: 0.85,
                    attendeeName: "Sarah",
                    sourceApp: "iMessage"
                )
            ],
            message: "Found 2 events"
        )
    }
}
#endif
