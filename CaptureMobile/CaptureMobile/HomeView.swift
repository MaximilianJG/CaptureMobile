//
//  HomeView.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 17.01.26.
//

import SwiftUI

struct HomeView: View {
    @ObservedObject var authManager = GoogleAuthManager.shared
    @AppStorage("shortcutCreated") private var shortcutCreated = false
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
                    
                    // How it works
                    howItWorksSection
                    
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
            // Directly open Shortcuts app - no popup
            ShortcutManager.shared.installShortcut()
            shortcutCreated = true
        }) {
            HStack(spacing: 14) {
                Image(systemName: "apps.iphone")
                    .font(.system(size: 24))
                    .foregroundStyle(.primary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Setup iOS Shortcut")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Tap to configure")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
    
    // MARK: - How It Works
    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How it works")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 20)
            
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
        }
    }
    
    // MARK: - Re-add Shortcut Link (subtle, always visible)
    private var reAddShortcutLink: some View {
        Button(action: {
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
