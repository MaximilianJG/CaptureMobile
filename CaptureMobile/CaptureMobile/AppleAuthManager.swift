//
//  AppleAuthManager.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 29.01.26.
//

import Foundation
import SwiftUI
import Combine
import AuthenticationServices
import PostHog

class AppleAuthManager: NSObject, ObservableObject {
    static let shared = AppleAuthManager()
    
    @Published var isSignedIn: Bool = false
    @Published var currentUser: UserProfile?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private let keychain = KeychainHelper.shared
    
    struct UserProfile {
        let userID: String
        let email: String?
        let name: String?
        
        var displayName: String {
            name ?? email ?? "User"
        }
        
        var displayEmail: String {
            email ?? "Apple ID User"
        }
    }
    
    private override init() {
        super.init()
        
        // Check keychain synchronously to prevent flash of auth view
        if let userID = keychain.readString(forKey: .appleUserID) {
            let email = keychain.readString(forKey: .userEmail)
            let name = keychain.readString(forKey: .userName)
            
            self.currentUser = UserProfile(
                userID: userID,
                email: email,
                name: name
            )
            self.isSignedIn = true
            
            // Verify credential state in background
            checkCredentialState(userID: userID)
        }
    }
    
    // MARK: - Get User ID (for API calls)
    func getUserID() -> String? {
        return keychain.readString(forKey: .appleUserID)
    }
    
    // MARK: - Check Credential State
    private func checkCredentialState(userID: String) {
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        appleIDProvider.getCredentialState(forUserID: userID) { [weak self] state, error in
            DispatchQueue.main.async {
                switch state {
                case .authorized:
                    // User is still authorized
                    break
                case .revoked, .notFound:
                    // User revoked authorization or not found - sign out
                    self?.signOut()
                case .transferred:
                    // User transferred to a different iCloud account
                    break
                @unknown default:
                    break
                }
            }
        }
    }
    
    // MARK: - Sign In
    @MainActor
    func signIn() {
        isLoading = true
        errorMessage = nil
        
        PostHogSDK.shared.capture("sign_in_started", properties: [
            "provider": "apple"
        ])
        
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
    
    // MARK: - Sign Out
    @MainActor
    func signOut() {
        PostHogSDK.shared.capture("sign_out", properties: [
            "provider": "apple"
        ])
        PostHogSDK.shared.reset()
        
        keychain.clearAll()
        
        // Reset shortcut setup flag
        UserDefaults.standard.removeObject(forKey: "shortcutCreated")
        
        // Clear capture history
        CaptureHistoryManager.shared.clearHistory()
        
        isSignedIn = false
        currentUser = nil
    }
    
    // MARK: - Handle Sign In Result
    @MainActor
    private func handleSignInResult(_ credential: ASAuthorizationAppleIDCredential) {
        let userID = credential.user
        
        // Name and email are only provided on FIRST sign-in
        // We must save them as Apple won't send them again
        var email = credential.email
        var fullName: String? = nil
        
        if let givenName = credential.fullName?.givenName,
           let familyName = credential.fullName?.familyName {
            fullName = "\(givenName) \(familyName)"
        } else if let givenName = credential.fullName?.givenName {
            fullName = givenName
        }
        
        // Check if we already have stored values (for returning users)
        if email == nil {
            email = keychain.readString(forKey: .userEmail)
        }
        if fullName == nil {
            fullName = keychain.readString(forKey: .userName)
        }
        
        // Save to keychain
        _ = keychain.save(userID, forKey: .appleUserID)
        if let email = email {
            _ = keychain.save(email, forKey: .userEmail)
        }
        if let name = fullName {
            _ = keychain.save(name, forKey: .userName)
        }
        
        currentUser = UserProfile(
            userID: userID,
            email: email,
            name: fullName
        )
        
        isSignedIn = true
        isLoading = false
        
        // Identify user in PostHog
        PostHogSDK.shared.identify(userID, userProperties: [
            "name": fullName ?? "Unknown",
            "email": email ?? "hidden",
            "auth_provider": "apple"
        ])
        
        PostHogSDK.shared.capture("sign_in_completed", properties: [
            "provider": "apple"
        ])
    }
}

// MARK: - ASAuthorizationControllerDelegate
extension AppleAuthManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            Task { @MainActor in
                handleSignInResult(appleIDCredential)
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            isLoading = false
            
            // Don't show error for user cancellation
            if let authError = error as? ASAuthorizationError,
               authError.code == .canceled {
                return
            }
            
            errorMessage = error.localizedDescription
            
            PostHogSDK.shared.capture("sign_in_failed", properties: [
                "provider": "apple",
                "error": error.localizedDescription
            ])
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding
extension AppleAuthManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return UIWindow()
        }
        return window
    }
}
