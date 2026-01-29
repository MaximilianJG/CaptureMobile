//
//  HomeView.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 17.01.26.
//

import SwiftUI
import PostHog

struct HomeView: View {
    @ObservedObject var authManager = AppleAuthManager.shared
    @ObservedObject var captureHistory = CaptureHistoryManager.shared
    @ObservedObject var calendarService = CalendarService.shared
    @State private var showManageSheet = false
    @State private var showSetupPopup = false
    @State private var showCalendarPermissionAlert = false
    
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
                    
                    // Calendar Selection
                    calendarSection
                    
                    // Setup section (only if no captures yet)
                    if captureHistory.recentCaptures.isEmpty {
                        setupSection
                    }
                    
                    // Recent Captures (only if there are captures)
                    if !captureHistory.recentCaptures.isEmpty {
                        recentCapturesSection
                    }
                    
                    // Footer link
                    footerLink
                }
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showManageSheet) {
            ManageAccountSheet()
        }
        .sheet(isPresented: $showSetupPopup) {
            SetupSheet()
        }
        .alert("Calendar Access Required", isPresented: $showCalendarPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enable calendar access in Settings to save events.")
        }
        .task {
            // Request calendar access on first appearance
            if !calendarService.hasAccess {
                let granted = await calendarService.requestAccess()
                if !granted {
                    showCalendarPermissionAlert = true
                }
            }
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            Text("Capture")
                .font(.system(size: 32, weight: .bold))
            
            Spacer()
            
            Button(action: { showSetupPopup = true }) {
                Text("Setup")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.black, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Calendar Section
    private var calendarSection: some View {
        CalendarPickerView()
    }
    
    // MARK: - Setup Section (inline)
    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Setup")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 20)
            
            SetupContentView()
                .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Profile Card
    private var profileCard: some View {
        HStack(spacing: 12) {
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(authManager.currentUser?.displayName ?? "User")
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                
                Text(authManager.currentUser?.displayEmail ?? "")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
    
    // MARK: - Footer Link
    private var footerLink: some View {
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
        .padding(.top, 8)
    }
}

// MARK: - Setup Content View (Reusable)
struct SetupContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Step 1: Install Shortcut (with button on same line)
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 8))
                
                Text("Install Shortcut")
                    .font(.system(size: 16, weight: .semibold))
                
                Spacer(minLength: 8)
                
                Button(action: {
                    PostHogSDK.shared.capture("shortcut_install_tapped")
                    ShortcutManager.shared.installShortcut()
                }) {
                    Text("Tap to install")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black, in: Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            
            Divider().padding(.leading, 60)
            
            // Step 2: Bind to Control Center (with numbered sub-steps)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "switch.2")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Bind to Control Center")
                        .font(.system(size: 16, weight: .semibold))
                    
                    VStack(alignment: .leading, spacing: 6) {
                        SetupSubStep(number: 1, text: "Swipe down from the top right edge")
                        SetupSubStep(number: 2, text: "Add a control in the top left")
                        SetupSubStep(number: 3, text: "Search for \"Run Shortcut\" control")
                        SetupSubStep(number: 4, text: "Search for \"Capture something\"")
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            
            Divider().padding(.leading, 60)
            
            // Step 3: Start Capturing (title only)
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 8))
                
                Text("Start Capturing!")
                    .font(.system(size: 16, weight: .semibold))
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - Setup Sub Step (for numbered instructions)
private struct SetupSubStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)
            
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Setup Sheet (Popup)
struct SetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                SetupContentView()
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Setup")
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

// MARK: - Capture Row
private struct CaptureRow: View {
    let capture: CapturedEvent
    
    var body: some View {
        Button(action: openInCalendar) {
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
                
                // Chevron to indicate tappable
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
    
    private func openInCalendar() {
        // Parse the event date and open Calendar app at that date
        guard let date = capture.eventDate else {
            // Fallback: just open Calendar app
            if let url = URL(string: "calshow:") {
                UIApplication.shared.open(url)
            }
            return
        }
        
        // calshow: takes a Unix timestamp (seconds since Jan 1, 2001 for NSDate reference)
        let timestamp = date.timeIntervalSinceReferenceDate
        if let url = URL(string: "calshow:\(timestamp)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Manage Account Sheet
struct ManageAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var authManager = AppleAuthManager.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Profile
                VStack(spacing: 6) {
                    Text(authManager.currentUser?.displayName ?? "User")
                        .font(.system(size: 18, weight: .semibold))
                    
                    Text(authManager.currentUser?.displayEmail ?? "Apple ID User")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)
                
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
