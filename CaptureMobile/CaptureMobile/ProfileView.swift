//
//  ProfileView.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 20.03.26.
//

import SwiftUI
import PostHog

struct ProfileView: View {
    @ObservedObject var authManager = AppleAuthManager.shared
    @ObservedObject var calendarService = CalendarService.shared
    @StateObject private var notionManager = NotionManager.shared
    @State private var showManageSheet = false
    @State private var showSetupPopup = false
    @State private var showCalendarPermissionAlert = false
    @State private var showNotionPagePicker = false

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    headerView
                    profileCard
                    notionSection
                    calendarSection
                    footerLink
                }
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
        }
        .sheet(isPresented: $showManageSheet) {
            ManageAccountSheet()
        }
        .sheet(isPresented: $showSetupPopup) {
            SetupSheet()
        }
        .sheet(isPresented: $showNotionPagePicker) {
            NotionPagePickerSheet(notionManager: notionManager)
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
            if !calendarService.hasAccess {
                let granted = await calendarService.requestAccess()
                if !granted {
                    showCalendarPermissionAlert = true
                }
            }
            await notionManager.checkStatus()
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
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)

                Text(authManager.currentUser?.displayEmail ?? "")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

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

    // MARK: - Notion Section

    private var notionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text")
                    .font(.system(size: 14, weight: .medium))
                Text("Notion")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)

            VStack(spacing: 12) {
                if notionManager.isConnected {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(notionManager.workspaceName ?? "Connected")
                                .font(.system(size: 15, weight: .medium))
                            if let pageTitle = notionManager.parentPageTitle {
                                Text("Saving to: \(pageTitle)")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("No parent page selected")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08), lineWidth: 1))

                    HStack(spacing: 10) {
                        Button {
                            Task {
                                await notionManager.fetchPages()
                                showNotionPagePicker = true
                            }
                        } label: {
                            Text("Select Page")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.white, in: Capsule())
                                .overlay(Capsule().stroke(Color.black.opacity(0.15), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await notionManager.disconnect() }
                        } label: {
                            Text("Disconnect")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.white, in: Capsule())
                                .overlay(Capsule().stroke(Color.red.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button {
                        Task { await notionManager.connect() }
                    } label: {
                        HStack(spacing: 8) {
                            if notionManager.isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "link")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            Text("Connect Notion")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(notionManager.isLoading)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Calendar Section

    private var calendarSection: some View {
        CalendarPickerView()
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

// MARK: - Notion Page Picker Sheet

struct NotionPagePickerSheet: View {
    @ObservedObject var notionManager: NotionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if notionManager.availablePages.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(notionManager.availablePages) { page in
                        Button {
                            Task {
                                await notionManager.setParentPage(id: page.id, title: page.title)
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(.secondary)
                                Text(page.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if notionManager.parentPageId == page.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Parent Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            if notionManager.availablePages.isEmpty {
                await notionManager.fetchPages()
            }
        }
    }
}

#Preview {
    ProfileView()
}
