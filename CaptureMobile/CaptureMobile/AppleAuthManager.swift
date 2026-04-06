//
//  AppleAuthManager.swift
//  CaptureMobile
//

import Foundation
import SwiftUI
import Combine
import AuthenticationServices
import PostHog
import Supabase

class AppleAuthManager: NSObject, ObservableObject {
    static let shared = AppleAuthManager()

    @Published var isSignedIn: Bool = false
    @Published var currentUser: UserProfile?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let keychain = KeychainHelper.shared
    private let supabase = SupabaseManager.shared.client

    struct UserProfile {
        let userID: String          // Supabase UUID
        let appleUserID: String     // Original Apple user ID
        let email: String?
        let name: String?

        var displayName: String { name ?? email ?? "User" }
        var displayEmail: String { email ?? "Apple ID User" }
    }

    private override init() {
        super.init()

        // Restore session from Supabase (persisted automatically)
        Task {
            await restoreSession()
        }
    }

    // MARK: - Restore Session

    @MainActor
    private func restoreSession() async {
        if let session = try? await supabase.auth.session {
            let uid = session.user.id.uuidString
            SupabaseManager.shared.currentUserID = uid

            let appleUID = keychain.readString(forKey: .appleUserID) ?? ""
            let email = keychain.readString(forKey: .userEmail)
            let name = keychain.readString(forKey: .userName)

            currentUser = UserProfile(
                userID: uid,
                appleUserID: appleUID,
                email: email,
                name: name
            )
            isSignedIn = true

            if !appleUID.isEmpty {
                checkCredentialState(userID: appleUID)
            }
            return
        }

        // Fallback: check keychain for Apple user ID (pre-migration)
        if let appleUID = keychain.readString(forKey: .appleUserID) {
            let email = keychain.readString(forKey: .userEmail)
            let name = keychain.readString(forKey: .userName)
            currentUser = UserProfile(
                userID: appleUID,
                appleUserID: appleUID,
                email: email,
                name: name
            )
            isSignedIn = true
            checkCredentialState(userID: appleUID)
        }
    }

    // MARK: - Get User ID (Supabase UUID preferred)

    func getUserID() -> String? {
        if let supabaseID = SupabaseManager.shared.currentUserID {
            return supabaseID
        }
        return keychain.readString(forKey: .appleUserID)
    }

    // MARK: - Update Profile

    @MainActor
    func updateName(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let user = currentUser else { return }
        _ = keychain.save(trimmed, forKey: .userName)
        currentUser = UserProfile(
            userID: user.userID, appleUserID: user.appleUserID,
            email: user.email, name: trimmed
        )
        PostHogSDK.shared.capture("profile_name_updated")
    }

    // MARK: - Check Credential State

    private func checkCredentialState(userID: String) {
        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: userID) { [weak self] state, _ in
            DispatchQueue.main.async {
                if state == .revoked || state == .notFound {
                    self?.signOut()
                }
            }
        }
    }

    // MARK: - Sign In

    @MainActor
    func signIn() {
        isLoading = true
        errorMessage = nil
        PostHogSDK.shared.capture("sign_in_started", properties: ["provider": "apple"])

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
        PostHogSDK.shared.capture("sign_out")
        PostHogSDK.shared.reset()

        Task { try? await supabase.auth.signOut() }

        _ = keychain.delete(forKey: .appleUserID)
        UserDefaults.standard.removeObject(forKey: "shortcutCreated")
        CaptureHistoryManager.shared.clearHistory()

        isSignedIn = false
        currentUser = nil
    }

    // MARK: - Handle Sign In Result

    @MainActor
    private func handleSignInResult(_ credential: ASAuthorizationAppleIDCredential) {
        let appleUID = credential.user

        // Name/email only on first sign-in
        var email = credential.email ?? keychain.readString(forKey: .userEmail)
        var fullName: String? = {
            if let g = credential.fullName?.givenName, let f = credential.fullName?.familyName {
                return "\(g) \(f)"
            }
            return credential.fullName?.givenName ?? keychain.readString(forKey: .userName)
        }()

        // Save to keychain
        _ = keychain.save(appleUID, forKey: .appleUserID)
        if let e = email { _ = keychain.save(e, forKey: .userEmail) }
        if let n = fullName { _ = keychain.save(n, forKey: .userName) }

        // Exchange Apple identity token with Supabase Auth
        Task {
            var supabaseUserID = appleUID

            if let tokenData = credential.identityToken,
               let idToken = String(data: tokenData, encoding: .utf8) {
                do {
                    let session = try await supabase.auth.signInWithIdToken(
                        credentials: .init(provider: .apple, idToken: idToken)
                    )
                    supabaseUserID = session.user.id.uuidString
                    SupabaseManager.shared.currentUserID = supabaseUserID
                    print("✅ Supabase auth: \(supabaseUserID)")
                } catch {
                    print("⚠️ Supabase auth failed, using Apple ID: \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                currentUser = UserProfile(
                    userID: supabaseUserID,
                    appleUserID: appleUID,
                    email: email,
                    name: fullName
                )
                isSignedIn = true
                isLoading = false
            }

            PostHogSDK.shared.identify(supabaseUserID, userProperties: [
                "name": fullName ?? "Unknown",
                "email": email ?? "hidden",
                "auth_provider": "apple"
            ])
            PostHogSDK.shared.capture("sign_in_completed", properties: ["provider": "apple"])
            DeviceTokenManager.shared.registerIfNeeded()
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleAuthManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let cred = authorization.credential as? ASAuthorizationAppleIDCredential {
            Task { @MainActor in handleSignInResult(cred) }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            isLoading = false
            if let e = error as? ASAuthorizationError, e.code == .canceled { return }
            errorMessage = error.localizedDescription
            PostHogSDK.shared.capture("sign_in_failed", properties: ["error": error.localizedDescription])
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleAuthManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else { return UIWindow() }
        return window
    }
}
