//
//  AuthView.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 17.01.26.
//

import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @ObservedObject var authManager = AppleAuthManager.shared
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Subtle gradient background
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.98, blue: 0.99),
                        Color.white
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: geometry.size.height * 0.12)
                    
                    // Header
                    VStack(spacing: 10) {
                        Text("Capture")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(.black)
                        
                        VStack(spacing: 2) {
                            Text("Create events from")
                            Text("anywhere")
                        }
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    }
                    
                    Spacer()
                        .frame(height: geometry.size.height * 0.05)
                    
                    // Logo - bigger
                    Image("CaptureLogoWhite")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: min(geometry.size.width * 0.6, 280))
                    
                    Spacer()
                    
                    // Sign in button
                    VStack(spacing: 20) {
                        if authManager.isLoading {
                            ProgressView()
                                .controlSize(.large)
                        } else {
                            Button(action: {
                                authManager.signIn()
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: 18, weight: .medium))
                                    Text("Sign in with Apple")
                                        .font(.system(size: 18, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .frame(width: 260, height: 54)
                                .background(.black, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if let error = authManager.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    }
                    .padding(.bottom, 50)
                }
            }
        }
        .preferredColorScheme(.light)
    }
}

#Preview {
    AuthView()
}
