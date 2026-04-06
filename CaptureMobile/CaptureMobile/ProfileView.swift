//
//  ProfileView.swift
//  CaptureMobile
//

import SwiftUI
import PostHog

struct ProfileView: View {
    @ObservedObject var authManager = AppleAuthManager.shared
    @ObservedObject var calendarService = CalendarService.shared
    @State private var showManageSheet = false
    @State private var showSetupPopup = false
    @State private var showCalendarPermissionAlert = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    headerView
                    profileCard
                    calendarSection
                    footerLink
                }
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
        }
        .sheet(isPresented: $showManageSheet) { ManageAccountSheet() }
        .sheet(isPresented: $showSetupPopup) { SetupSheet() }
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
            if !calendarService.hasAccess {
                let granted = await calendarService.requestAccess()
                if !granted { showCalendarPermissionAlert = true }
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Profile")
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

    // MARK: - Profile Card

    private var profileCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(authManager.currentUser?.displayName ?? "User")
                    .font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Text(authManager.currentUser?.displayEmail ?? "")
                    .font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button("Manage") {
                PostHogSDK.shared.capture("manage_account_opened")
                showManageSheet = true
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.black)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color.white, in: Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(0.15), lineWidth: 1))
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08)))
        .padding(.horizontal, 20)
    }

    // MARK: - Calendar Section

    private var calendarSection: some View {
        CalendarPickerView()
    }

    // MARK: - Footer

    private var footerLink: some View {
        Button {
            PostHogSDK.shared.capture("feedback_tapped")
            if let url = URL(string: "https://maximilianglasmacher.notion.site/2d037e9160b7805faf48c8daed29daa7?pvs=105") {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left").font(.system(size: 12))
                Text("Send Feedback").font(.system(size: 13))
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }
}

// MARK: - Manage Account Sheet

struct ManageAccountSheet: View {
    @ObservedObject var authManager = AppleAuthManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var nameText: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Display Name")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                    TextField("Your name", text: $nameText)
                        .font(.system(size: 16))
                        .padding(12)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    authManager.updateName(nameText)
                    dismiss()
                } label: {
                    Text("Save")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(.black, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Divider()

                Button(role: .destructive) {
                    authManager.signOut()
                    dismiss()
                } label: {
                    Text("Sign Out")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Manage Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            nameText = authManager.currentUser?.displayName ?? ""
        }
    }
}

// MARK: - Setup Sheet

struct SetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    setupStep(
                        number: 1,
                        title: "Install the Shortcut",
                        description: "Tap below to add the Capture shortcut, which lets you send screenshots instantly.",
                        action: {
                            Button {
                                ShortcutManager.shared.installShortcut()
                            } label: {
                                Text("Install Shortcut")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16).padding(.vertical, 10)
                                    .background(.black, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    )

                    setupStep(
                        number: 2,
                        title: "Assign to Back Tap",
                        description: "Go to Settings → Accessibility → Touch → Back Tap, then assign \"Capture\" to Double or Triple Tap."
                    )

                    setupStep(
                        number: 3,
                        title: "Capture Anything",
                        description: "Take a screenshot, double-tap the back of your phone, or use the camera & notes tab to create captures."
                    )
                }
                .padding(20)
            }
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func setupStep<Content: View>(
        number: Int,
        title: String,
        description: String,
        @ViewBuilder action: () -> Content = { EmptyView() }
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.black, in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                action()
            }
        }
    }
}

#Preview { ProfileView() }
