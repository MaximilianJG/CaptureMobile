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
                LinearGradient(
                    colors: [CaptureColors.bg, CaptureColors.card],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: geometry.size.height * 0.12)

                    VStack(spacing: 10) {
                        Text("Capture")
                            .font(CaptureFont.display)
                            .tracking(-0.8)
                            .foregroundStyle(CaptureColors.text)

                        VStack(spacing: 2) {
                            Text("Create events from")
                            Text("anywhere")
                        }
                        .font(CaptureFont.headingLg)
                        .foregroundStyle(CaptureColors.textSecondary)
                        .multilineTextAlignment(.center)
                    }

                    Spacer()
                        .frame(height: geometry.size.height * 0.05)

                    Image("CaptureLogoWhite")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: min(geometry.size.width * 0.6, 280))

                    Spacer()

                    VStack(spacing: CaptureSpacing.lg) {
                        if authManager.isLoading {
                            ProgressView()
                                .controlSize(.large)
                                .tint(CaptureColors.primary)
                        } else {
                            Button(action: {
                                authManager.signIn()
                            }) {
                                HStack(spacing: CaptureSpacing.sm) {
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: 18))
                                    Text("Sign in with Apple")
                                        .font(CaptureFont.heading)
                                }
                                .foregroundStyle(.white)
                                .frame(width: 260, height: 54)
                                .background(CaptureColors.text, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        if let error = authManager.errorMessage {
                            Text(error)
                                .font(CaptureFont.body)
                                .foregroundStyle(CaptureColors.danger)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, CaptureSpacing.xxl)
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
