//
//  GoogleAuthManager.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 17.01.26.
//

import Foundation
import SwiftUI
import Combine
import GoogleSignIn
import PostHog

class GoogleAuthManager: ObservableObject {
    static let shared = GoogleAuthManager()
    
    @Published var isSignedIn: Bool = false
    @Published var currentUser: UserProfile?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private let keychain = KeychainHelper.shared
    
    // Required Google Calendar scope
    private let calendarScope = "https://www.googleapis.com/auth/calendar"
    
    struct UserProfile {
        let email: String
        let name: String
        let profileImageURL: URL?
    }
    
    private init() {
        // Check keychain synchronously FIRST to prevent flash of auth view
        if let email = keychain.readString(forKey: .userEmail),
           let name = keychain.readString(forKey: .userName) {
            let profileURLString = keychain.readString(forKey: .userProfileURL)
            let profileURL = profileURLString.flatMap { URL(string: $0) }
            
            self.currentUser = UserProfile(
                email: email,
                name: name,
                profileImageURL: profileURL
            )
            self.isSignedIn = true
        }
        
        // Then restore Google session in background (validates/refreshes tokens)
        restorePreviousSignIn()
    }
    
    // MARK: - Sign In
    @MainActor
    func signIn() async {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            errorMessage = "Unable to get root view controller"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Track sign in started
        PostHogSDK.shared.capture("sign_in_started")
        
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: rootViewController,
                hint: nil,
                additionalScopes: [calendarScope]
            )
            
            handleSignInResult(result.user, isExplicitSignIn: true)
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            
            // Track sign in failed
            PostHogSDK.shared.capture("sign_in_failed", properties: [
                "error": error.localizedDescription
            ])
        }
    }
    
    // MARK: - Sign Out
    @MainActor
    func signOut() {
        // Track sign out
        PostHogSDK.shared.capture("sign_out")
        PostHogSDK.shared.reset()
        
        GIDSignIn.sharedInstance.signOut()
        keychain.clearAll()
        
        // Reset shortcut setup flag so it shows again for next user
        UserDefaults.standard.removeObject(forKey: "shortcutCreated")
        
        // Clear capture history
        CaptureHistoryManager.shared.clearHistory()
        
        isSignedIn = false
        currentUser = nil
    }
    
    // MARK: - Get Access Token
    func getAccessToken() async -> String? {
        // First try to get from current Google session (works in main app)
        if let user = GIDSignIn.sharedInstance.currentUser {
            do {
                try await user.refreshTokensIfNeeded()
                let token = user.accessToken.tokenString
                _ = keychain.save(token, forKey: .accessToken)
                return token
            } catch {
                print("Failed to refresh token via SDK: \(error)")
            }
        }
        
        // Extension context: SDK session not available, refresh manually using refresh token
        if let refreshToken = keychain.readString(forKey: .refreshToken) {
            if let newAccessToken = await refreshAccessTokenManually(refreshToken: refreshToken) {
                _ = keychain.save(newAccessToken, forKey: .accessToken)
                return newAccessToken
            }
        }
        
        // Last resort: return stored token (may be expired)
        return keychain.readString(forKey: .accessToken)
    }
    
    // MARK: - Manual Token Refresh
    /// Refreshes the access token using the refresh token directly via HTTP.
    /// This is needed when running in extension context where GIDSignIn session isn't available.
    private func refreshAccessTokenManually(refreshToken: String) async -> String? {
        // Get client ID from Info.plist
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            print("Failed to get GIDClientID from Info.plist")
            return nil
        }
        
        let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        
        let bodyString = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
        
        request.httpBody = bodyString.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid response type")
                return nil
            }
            
            if httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let accessToken = json["access_token"] as? String {
                    print("✅ Successfully refreshed access token manually")
                    return accessToken
                }
            } else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("Token refresh failed (\(httpResponse.statusCode)): \(errorBody)")
            }
        } catch {
            print("Token refresh request failed: \(error)")
        }
        
        return nil
    }
    
    // MARK: - Restore Previous Sign In
    private func restorePreviousSignIn() {
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            DispatchQueue.main.async {
                if let user = user {
                    self?.handleSignInResult(user)
                } else {
                    // Check if we have stored credentials
                    if let email = self?.keychain.readString(forKey: .userEmail),
                       let name = self?.keychain.readString(forKey: .userName) {
                        let profileURLString = self?.keychain.readString(forKey: .userProfileURL)
                        let profileURL = profileURLString.flatMap { URL(string: $0) }
                        
                        self?.currentUser = UserProfile(
                            email: email,
                            name: name,
                            profileImageURL: profileURL
                        )
                        self?.isSignedIn = true
                    }
                }
            }
        }
    }
    
    // MARK: - Handle Sign In Result
    @MainActor
    private func handleSignInResult(_ user: GIDGoogleUser, isExplicitSignIn: Bool = false) {
        guard let email = user.profile?.email,
              let name = user.profile?.name else {
            errorMessage = "Failed to get user profile"
            isLoading = false
            return
        }
        
        let profileImageURL = user.profile?.imageURL(withDimension: 200)
        
        // Save to keychain
        _ = keychain.save(user.accessToken.tokenString, forKey: .accessToken)
        _ = keychain.save(user.refreshToken.tokenString, forKey: .refreshToken)
        _ = keychain.save(email, forKey: .userEmail)
        _ = keychain.save(name, forKey: .userName)
        if let url = profileImageURL?.absoluteString {
            _ = keychain.save(url, forKey: .userProfileURL)
        }
        
        currentUser = UserProfile(
            email: email,
            name: name,
            profileImageURL: profileImageURL
        )
        
        isSignedIn = true
        isLoading = false
        
        // Always identify user (links events to this user for the session)
        PostHogSDK.shared.identify(email, userProperties: [
            "name": name,
            "auth_provider": "google"
        ])
        
        // Only track sign_in_completed for explicit sign-ins, not session restoration
        if isExplicitSignIn {
            PostHogSDK.shared.capture("sign_in_completed")
        }
    }
    
    // MARK: - Handle URL
    func handle(_ url: URL) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}
