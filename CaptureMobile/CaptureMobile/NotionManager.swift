//
//  NotionManager.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 20.03.26.
//

import Foundation
import Combine
import AuthenticationServices

@MainActor
final class NotionManager: NSObject, ObservableObject {
    static let shared = NotionManager()

    @Published var isConnected = false
    @Published var workspaceName: String?
    @Published var parentPageId: String?
    @Published var parentPageTitle: String?
    @Published var availablePages: [NotionPage] = []
    @Published var isLoading = false

    struct NotionPage: Identifiable {
        let id: String
        let title: String
    }

    private let baseURL = "https://capturemobile-production.up.railway.app"
    private let apiKey = "bad3515c210e9b769dcb3276cb18553ebff1f0b3935c84f4f1d3aedc064c30e4"

    private override init() {
        super.init()
    }

    // MARK: - Check Status

    func checkStatus() async {
        guard let userID = AppleAuthManager.shared.getUserID() else { return }

        guard let url = URL(string: "\(baseURL)/notion/status?user_id=\(userID)") else { return }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let connected = json?["connected"] as? Bool ?? false
            isConnected = connected
            workspaceName = json?["workspace_name"] as? String
            parentPageId = json?["parent_page_id"] as? String
            parentPageTitle = json?["parent_page_title"] as? String
        } catch {
            print("Notion status check failed: \(error)")
        }
    }

    // MARK: - OAuth Connect

    func connect() async {
        guard let userID = AppleAuthManager.shared.getUserID() else { return }
        isLoading = true

        guard let url = URL(string: "\(baseURL)/notion/auth-url?user_id=\(userID)") else {
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let authURLString = json?["url"] as? String,
                  let authURL = URL(string: authURLString) else {
                isLoading = false
                return
            }

            await startOAuthSession(url: authURL)
        } catch {
            print("Failed to get Notion auth URL: \(error)")
            isLoading = false
        }
    }

    private func startOAuthSession(url: URL) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "capture"
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    defer { continuation.resume() }

                    if let error {
                        print("Notion OAuth error: \(error)")
                        self?.isLoading = false
                        return
                    }

                    self?.isLoading = false
                    await self?.checkStatus()
                }
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    // MARK: - Disconnect

    func disconnect() async {
        guard let userID = AppleAuthManager.shared.getUserID() else { return }

        guard let url = URL(string: "\(baseURL)/notion/disconnect?user_id=\(userID)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        _ = try? await URLSession.shared.data(for: request)
        isConnected = false
        workspaceName = nil
        parentPageId = nil
        parentPageTitle = nil
        availablePages = []
    }

    // MARK: - Fetch Pages

    func fetchPages() async {
        guard let userID = AppleAuthManager.shared.getUserID() else { return }

        guard let url = URL(string: "\(baseURL)/notion/pages?user_id=\(userID)") else { return }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let pagesRaw = json?["pages"] as? [[String: Any]] ?? []
            availablePages = pagesRaw.compactMap { raw in
                guard let id = raw["id"] as? String, let title = raw["title"] as? String else { return nil }
                return NotionPage(id: id, title: title)
            }
        } catch {
            print("Failed to fetch Notion pages: \(error)")
        }
    }

    // MARK: - Set Parent Page

    func setParentPage(id: String, title: String) async {
        guard let userID = AppleAuthManager.shared.getUserID() else { return }

        guard let url = URL(string: "\(baseURL)/notion/set-parent") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let body: [String: Any] = [
            "user_id": userID,
            "page_id": id,
            "page_title": title
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        _ = try? await URLSession.shared.data(for: request)
        parentPageId = id
        parentPageTitle = title
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension NotionManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return UIWindow()
        }
        return window
    }
}
