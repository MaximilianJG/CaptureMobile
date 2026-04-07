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
    @State private var showTagsSheet = false
    @State private var showCalendarPermissionAlert = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    headerView
                    profileCard
                    tagsRow
                    calendarSection
                    footerLink
                }
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
        }
        .sheet(isPresented: $showManageSheet) { ManageAccountSheet() }
        .sheet(isPresented: $showSetupPopup) { SetupSheet() }
        .sheet(isPresented: $showTagsSheet) { ManageTagsSheet() }
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

    // MARK: - Tags Row

    private var tagsRow: some View {
        Button {
            showTagsSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "tag")
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Manage Tags")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("Add, remove, or organize your tags")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08)))
        }
        .buttonStyle(.plain)
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

// MARK: - Manage Tags Sheet

struct ManageTagsSheet: View {
    @ObservedObject var tagManager = TagManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var newTagName = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                addTagField
                    .padding(16)

                Divider()

                ScrollView {
                    if tagManager.tags.isEmpty && !tagManager.isLoading {
                        VStack(spacing: 8) {
                            Text("No tags yet")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("Add tags to organize your captures.")
                                .font(.system(size: 14))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.top, 40)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(tagManager.tags) { tag in
                                tagChip(tag)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Manage Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            await tagManager.loadTags()
        }
    }

    private var addTagField: some View {
        HStack(spacing: 10) {
            TextField("New tag name", text: $newTagName)
                .font(.system(size: 15))
                .padding(10)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                .submitLabel(.done)
                .onSubmit { addTag() }

            Button {
                addTag()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.gray : Color.black,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
            }
            .buttonStyle(.plain)
            .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func tagChip(_ tag: APIService.UserTag) -> some View {
        HStack(spacing: 4) {
            Text(tag.name)
                .font(.system(size: 14, weight: .medium))
            Button {
                Task { await tagManager.deleteTag(id: tag.id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6), in: Capsule())
    }

    private func addTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            await tagManager.createTag(name: name)
            newTagName = ""
        }
    }
}

#Preview { ProfileView() }
