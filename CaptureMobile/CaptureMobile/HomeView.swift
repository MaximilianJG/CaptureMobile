//
//  HomeView.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 17.01.26.
//

import SwiftUI
import PostHog

struct HomeView: View {
    @ObservedObject var authManager = GoogleAuthManager.shared
    @ObservedObject var captureHistory = CaptureHistoryManager.shared
    @AppStorage("shortcutCreated") private var shortcutCreated = false
    @AppStorage("howItWorksExpanded") private var howItWorksExpanded = true
    @State private var showManageSheet = false
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Header
                    headerView
                    
                    // Profile Card
                    profileCard
                    
                    // Setup Shortcut (only if not configured)
                    if !shortcutCreated {
                        setupShortcutCard
                    }
                    
                    // How it works (collapsible)
                    howItWorksSection
                    
                    // Recent Captures (only if there are captures)
                    if !captureHistory.recentCaptures.isEmpty {
                        recentCapturesSection
                    }
                    
                    // Subtle re-add shortcut link (always visible at bottom)
                    reAddShortcutLink
                }
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showManageSheet) {
            ManageAccountSheet()
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            Text("Capture")
                .font(.system(size: 32, weight: .bold))
            
            Spacer()
            
            Button(action: {}) {
                Text("Free Plan")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.white, in: Capsule())
                    .overlay(Capsule().stroke(Color.black.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Profile Card
    private var profileCard: some View {
        HStack(spacing: 12) {
            // Avatar
            AsyncImage(url: authManager.currentUser?.profileImageURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.quaternary)
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(authManager.currentUser?.name ?? "User")
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                
                Text(authManager.currentUser?.email ?? "")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
            }
            
            Spacer()
            
            // Manage button - white with border
            Button("Manage") {
                PostHogSDK.shared.capture("manage_account_opened")
                showManageSheet = true
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white, in: Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(0.15), lineWidth: 1))
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 20)
    }
    
    // MARK: - Setup Shortcut Card
    private var setupShortcutCard: some View {
        Button(action: {
            // Track shortcut install tap
            PostHogSDK.shared.capture("shortcut_install_tapped")
            
            // Directly open Shortcuts app - no popup
            ShortcutManager.shared.installShortcut()
            shortcutCreated = true
        }) {
            VStack(spacing: 12) {
                // Icon with badge
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: "arrow.down.app.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                }
                
                // Text
                VStack(spacing: 4) {
                    Text("Setup iOS Shortcut")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                    
                    Text("Required to capture screenshots")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.8))
                }
                
                // CTA
                HStack(spacing: 6) {
                    Text("Tap to install")
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.white, in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
            .background(
                LinearGradient(
                    colors: [Color.black, Color.black.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 20)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
    
    // MARK: - Recent Captures Section
    private var recentCapturesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Captures")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 20)
            
            VStack(spacing: 0) {
                ForEach(Array(captureHistory.recentCaptures.enumerated()), id: \.element.id) { index, capture in
                    CaptureRow(capture: capture)
                    
                    if index < captureHistory.recentCaptures.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08), lineWidth: 1))
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - How It Works (Collapsible)
    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Collapsible header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    howItWorksExpanded.toggle()
                }
            }) {
                HStack {
                    Text("How it works")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    
                    Spacer()
                    
                    Image(systemName: howItWorksExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if howItWorksExpanded {
                VStack(spacing: 0) {
                    StepRow(
                        number: 1,
                        title: "Take a screenshot",
                        subtitle: "Use the shortcut to take a screenshot of an event"
                    )
                    Divider().padding(.leading, 60)
                    StepRow(
                        number: 2,
                        title: "AI analyzes",
                        subtitle: "AI analyzes this screenshot and extracts information"
                    )
                    Divider().padding(.leading, 60)
                    StepRow(
                        number: 3,
                        title: "Event created",
                        subtitle: "AI creates the relevant event in your calendar"
                    )
                }
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08), lineWidth: 1))
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    // MARK: - Re-add Shortcut Link (subtle, always visible)
    private var reAddShortcutLink: some View {
        HStack(spacing: 16) {
            Button(action: {
                PostHogSDK.shared.capture("shortcut_readd_tapped")
                ShortcutManager.shared.installShortcut()
                shortcutCreated = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                    Text("Re-add Shortcut")
                        .font(.system(size: 13))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            
            Text("·")
                .foregroundStyle(.quaternary)
            
            Button(action: {
                PostHogSDK.shared.capture("feedback_tapped")
                if let url = URL(string: "https://maximilianglasmacher.notion.site/2d037e9160b7805faf48c8daed29daa7?pvs=105") {
                    UIApplication.shared.open(url)
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 12))
                    Text("Send Feedback")
                        .font(.system(size: 13))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }
}

// MARK: - Step Row
private struct StepRow: View {
    let number: Int
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.black, in: Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Capture Row
private struct CaptureRow: View {
    let capture: CapturedEvent
    
    var body: some View {
        Button(action: {
            openCalendarLink()
        }) {
            HStack(spacing: 14) {
                // Source app icon
                Image(systemName: capture.sourceAppIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 8))
                
                // Event details
                VStack(alignment: .leading, spacing: 2) {
                    Text(capture.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text(capture.formattedDate)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                        
                        if let sourceApp = capture.sourceApp {
                            Text("·")
                                .foregroundStyle(.quaternary)
                            Text(sourceApp)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func openCalendarLink() {
        guard let link = capture.calendarLink,
              let url = URL(string: link) else {
            return
        }
        UIApplication.shared.open(url)
    }
}

// MARK: - Manage Account Sheet
struct ManageAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var authManager = GoogleAuthManager.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Profile
                VStack(spacing: 10) {
                    AsyncImage(url: authManager.currentUser?.profileImageURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .foregroundStyle(.quaternary)
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                    
                    Text(authManager.currentUser?.name ?? "User")
                        .font(.system(size: 18, weight: .semibold))
                    
                    Text(authManager.currentUser?.email ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 16)
                
                Divider().padding(.horizontal, 24)
                
                // Disconnect
                Button(role: .destructive) {
                    authManager.signOut()
                    dismiss()
                } label: {
                    Label("Disconnect Account", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 16, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)
                
                Spacer()
            }
            .navigationTitle("Manage Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.light)
    }
}

#Preview {
    HomeView()
}
