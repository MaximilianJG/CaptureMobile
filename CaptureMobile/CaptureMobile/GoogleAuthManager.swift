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
        isSignedIn = false
        currentUser = nil
    }
    
    // MARK: - Get Access Token
    func getAccessToken() async -> String? {
        // First try to get from current Google session
        if let user = GIDSignIn.sharedInstance.currentUser {
            do {
                try await user.refreshTokensIfNeeded()
                let token = user.accessToken.tokenString
                _ = keychain.save(token, forKey: .accessToken)
                return token
            } catch {
                print("Failed to refresh token: \(error)")
            }
        }
        
        // Fall back to stored token
        return keychain.readString(forKey: .accessToken)
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
