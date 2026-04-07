//
//  APIService.swift
//  CaptureMobile
//

import Foundation
import UIKit
import PostHog

final class APIService {
    static let shared = APIService()
    private init() {}

    private let baseURL = "https://capturemobile-production.up.railway.app"
    private let apiKey = "bad3515c210e9b769dcb3276cb18553ebff1f0b3935c84f4f1d3aedc064c30e4"

    // MARK: - Errors

    enum APIError: LocalizedError {
        case invalidURL
        case noUserID
        case encodingFailed
        case networkError(Error)
        case serverError(Int, String?)
        case decodingFailed(String)
        case rateLimited(String)
        case imageTooLarge

        var errorDescription: String? {
            switch self {
            case .invalidURL:           return "Invalid URL"
            case .noUserID:             return "Not authenticated. Please sign in."
            case .encodingFailed:       return "Failed to encode image"
            case .networkError(let e):  return "Network error: \(e.localizedDescription)"
            case .serverError(let c, let m): return "Server error (\(c)): \(m ?? "Unknown")"
            case .decodingFailed(let d): return "Decoding failed: \(d)"
            case .rateLimited(let m):   return m
            case .imageTooLarge:        return "Image too large. Try a smaller screenshot."
            }
        }
    }

    // MARK: - Response Models

    struct AsyncUploadResponse: Codable {
        let success: Bool
        let jobId: String
        let message: String
        enum CodingKeys: String, CodingKey {
            case success
            case jobId = "job_id"
            case message
        }
    }

    struct JobStatusResponse: Codable {
        let jobId: String
        let status: String
        let capture: CaptureRecord?
        let error: String?
        enum CodingKeys: String, CodingKey {
            case jobId = "job_id"
            case status, capture, error
        }
    }

    struct CaptureRecord: Codable {
        let id: String
        let captureTitle: String
        let category: String
        let captureMethod: String
        let timeCaptured: String
        let extractedData: [String: AnyCodable]
        let imageUrl: String?
        let tags: [String]
        let content: String?
        enum CodingKeys: String, CodingKey {
            case id
            case captureTitle = "capture_title"
            case category
            case captureMethod = "capture_method"
            case timeCaptured = "time_captured"
            case extractedData = "extracted_data"
            case imageUrl = "image_url"
            case tags
            case content
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            captureTitle = try container.decode(String.self, forKey: .captureTitle)
            category = try container.decode(String.self, forKey: .category)
            captureMethod = try container.decode(String.self, forKey: .captureMethod)
            timeCaptured = try container.decode(String.self, forKey: .timeCaptured)
            extractedData = try container.decode([String: AnyCodable].self, forKey: .extractedData)
            imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
            tags = (try? container.decodeIfPresent([String].self, forKey: .tags)) ?? []
            content = try container.decodeIfPresent(String.self, forKey: .content)
        }
    }

    struct UserTag: Codable, Identifiable {
        let id: String
        let name: String
    }

    struct UserTagsResponse: Codable {
        let tags: [UserTagRecord]
    }

    struct UserTagRecord: Codable {
        let id: String
        let userId: String
        let name: String
        enum CodingKeys: String, CodingKey {
            case id
            case userId = "user_id"
            case name
        }
    }

    struct CapturesResponse: Codable {
        let captures: [CaptureRecord]
    }

    // MARK: - Upload Capture (async)

    func uploadCaptureAsync(image: UIImage?, text: String?, userID: String, source: String = "notes") async -> String? {
        PostHogSDK.shared.capture("capture_sent", properties: ["source": source])

        guard let url = URL(string: "\(baseURL)/capture") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 60

        var body: [String: Any] = ["user_id": userID, "source": source]
        if let image {
            let resized = Self.resizeForUpload(image, maxDimension: 1920)
            if let data = resized.jpegData(compressionQuality: 0.7) {
                body["image"] = data.base64EncodedString()
            }
        }
        if let text, !text.isEmpty {
            body["text"] = text
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let res = try JSONDecoder().decode(AsyncUploadResponse.self, from: data)
            return res.success ? res.jobId : nil
        } catch {
            print("Capture upload failed: \(error)")
            return nil
        }
    }

    // MARK: - Get Captures

    func getCaptures(userID: String, category: String? = nil) async -> [CaptureRecord] {
        var urlString = "\(baseURL)/captures?user_id=\(userID)"
        if let cat = category, cat != "all" {
            urlString += "&category=\(cat)"
        }
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let res = try JSONDecoder().decode(CapturesResponse.self, from: data)
            return res.captures
        } catch {
            print("Fetch captures failed: \(error)")
            return []
        }
    }

    // MARK: - Delete Capture

    func deleteCapture(captureID: String, userID: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/captures/\(captureID)?user_id=\(userID)") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 15

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            print("Delete capture failed: \(error)")
            return false
        }
    }

    // MARK: - Update Capture Content

    func updateCaptureContent(captureID: String, userID: String, content: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/captures/\(captureID)") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 15

        let body: [String: Any] = ["user_id": userID, "content": content]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            print("Update capture content failed: \(error)")
            return false
        }
    }

    // MARK: - Job Status

    func checkJobStatus(jobID: String) async -> JobStatusResponse? {
        guard let url = URL(string: "\(baseURL)/job-status/\(jobID)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(JobStatusResponse.self, from: data)
        } catch {
            print("Job status check failed: \(error)")
            return nil
        }
    }

    // MARK: - Device Token Registration

    func registerDeviceToken(_ token: String, userID: String) async {
        guard let url = URL(string: "\(baseURL)/register-device") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 15

        #if DEBUG
        let isSandbox = true
        #else
        let isSandbox = false
        #endif

        let body: [String: Any] = ["device_token": token, "user_id": userID, "is_sandbox": isSandbox]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - User Tags

    func getUserTags(userID: String) async -> [UserTag] {
        guard let url = URL(string: "\(baseURL)/tags?user_id=\(userID)") else { return [] }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let json = try JSONDecoder().decode(UserTagsResponse.self, from: data)
            return json.tags.map { UserTag(id: $0.id, name: $0.name) }
        } catch {
            print("Fetch tags failed: \(error)")
            return []
        }
    }

    func createUserTag(userID: String, name: String) async -> UserTag? {
        guard let url = URL(string: "\(baseURL)/tags") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 15

        let body: [String: Any] = ["user_id": userID, "name": name]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            struct CreateResponse: Codable { let success: Bool; let tag: UserTagRecord }
            let res = try JSONDecoder().decode(CreateResponse.self, from: data)
            return UserTag(id: res.tag.id, name: res.tag.name)
        } catch {
            print("Create tag failed: \(error)")
            return nil
        }
    }

    func deleteUserTag(tagID: String, userID: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/tags/\(tagID)?user_id=\(userID)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 15

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            print("Delete tag failed: \(error)")
            return false
        }
    }

    // MARK: - Health Check

    func healthCheck() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }

    // MARK: - Image Resize

    private static func resizeForUpload(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard max(size.width, size.height) > maxDimension else { return image }
        let scale = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

// MARK: - AnyCodable (for flexible JSON decoding)

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) { value = b }
        else if let i = try? container.decode(Int.self) { value = i }
        else if let d = try? container.decode(Double.self) { value = d }
        else if let s = try? container.decode(String.self) { value = s }
        else if let a = try? container.decode([AnyCodable].self) { value = a.map(\.value) }
        else if let d = try? container.decode([String: AnyCodable].self) { value = d.mapValues(\.value) }
        else { value = NSNull() }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let b as Bool: try container.encode(b)
        case let i as Int: try container.encode(i)
        case let d as Double: try container.encode(d)
        case let s as String: try container.encode(s)
        default: try container.encodeNil()
        }
    }
}
