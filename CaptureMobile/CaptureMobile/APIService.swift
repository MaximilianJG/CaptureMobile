//
//  APIService.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 17.01.26.
//

import Foundation
import UIKit

final class APIService {
    static let shared = APIService()
    private init() {}
    
    // MARK: - Configuration
    // TODO: Update with your actual backend URL
    private let baseURL = "http://localhost:8000"
    
    // MARK: - Errors
    enum APIError: LocalizedError {
        case invalidURL
        case noAccessToken
        case encodingFailed
        case networkError(Error)
        case serverError(Int, String?)
        case decodingFailed
        case noEventFound
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL configuration"
            case .noAccessToken:
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
            }
        }
    }
    
    // MARK: - Response Models
    struct AnalyzeResponse: Codable {
        let success: Bool
        let eventCreated: EventDetails?
        let message: String
        
        enum CodingKeys: String, CodingKey {
            case success
            case eventCreated = "event_created"
            case message
        }
    }
    
    struct EventDetails: Codable {
        let id: String?
        let title: String
        let startTime: String
        let endTime: String?
        let location: String?
        let description: String?
        let calendarLink: String?
        
        enum CodingKeys: String, CodingKey {
            case id
            case title
            case startTime = "start_time"
            case endTime = "end_time"
            case location
            case description
            case calendarLink = "calendar_link"
        }
    }
    
    // MARK: - Analyze Screenshot
    /// Sends a screenshot to the backend for analysis and calendar event creation
    /// - Parameter image: The screenshot image to analyze
    /// - Returns: The analysis response with event details
    func analyzeScreenshot(_ image: UIImage) async throws -> AnalyzeResponse {
        // Get access token
        guard let accessToken = await GoogleAuthManager.shared.getAccessToken() else {
            throw APIError.noAccessToken
        }
        
        // Encode image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw APIError.encodingFailed
        }
        let base64Image = imageData.base64EncodedString()
        
        // Build request
        guard let url = URL(string: "\(baseURL)/analyze-screenshot") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "image": base64Image,
            "access_token": accessToken
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        // Send request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8)
            throw APIError.serverError(httpResponse.statusCode, errorMessage)
        }
        
        // Decode response
        let decoder = JSONDecoder()
        guard let analyzeResponse = try? decoder.decode(AnalyzeResponse.self, from: data) else {
            throw APIError.decodingFailed
        }
        
        return analyzeResponse
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
    /// Mock response for testing without backend
    func mockAnalyzeScreenshot() -> AnalyzeResponse {
        return AnalyzeResponse(
            success: true,
            eventCreated: EventDetails(
                id: "mock-event-123",
                title: "Team Meeting",
                startTime: "2026-01-20T10:00:00",
                endTime: "2026-01-20T11:00:00",
                location: "Conference Room A",
                description: "Weekly team sync",
                calendarLink: "https://calendar.google.com/event?eid=mock123"
            ),
            message: "Event created successfully!"
        )
    }
}
#endif
