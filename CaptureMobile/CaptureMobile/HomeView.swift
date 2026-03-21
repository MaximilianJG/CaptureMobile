//
//  HomeView.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 17.01.26.
//

import SwiftUI
import PostHog
import EventKitUI
import Combine

struct HomeView: View {
    @ObservedObject var captureHistory = CaptureHistoryManager.shared
    @ObservedObject var processingState = CaptureProcessingState.shared
    @State private var timeRefreshTrigger = Date()
    let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    headerView
                    
                    if processingState.isProcessing && !processingState.hasPendingFailure {
                        processingSection
                    }
                    
                    if captureHistory.recentCaptures.isEmpty && !processingState.isProcessing && !processingState.hasPendingFailure {
                        setupSection
                    }
                    
                    if !captureHistory.recentCaptures.isEmpty || processingState.hasPendingFailure {
                        recentCapturesSection
                            .id(timeRefreshTrigger)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
        }
        .onReceive(refreshTimer) { _ in
            timeRefreshTrigger = Date()
        }
        .onAppear {
            processingState.checkForFailure()
        }
        .preferredColorScheme(.light)
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            Text("Captures")
                .font(.system(size: 32, weight: .bold))
            Spacer()
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Processing Section
    private var processingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Processing")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 20)
            
            HStack(spacing: 14) {
                // Animated icon
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.1))
                        .frame(width: 32, height: 32)
                    
                    ProgressView()
                        .scaleEffect(0.8)
                }
                
                // Processing text
                VStack(alignment: .leading, spacing: 2) {
                    Text("Analyzing Screenshot...")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text("Creating your calendar events")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08), lineWidth: 1))
            .padding(.horizontal, 20)
        }
        .onAppear {
            // Timestamps for failure detection are now tracked per-job
            // in CaptureProcessingState.startProcessing(jobID:)
        }
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
    
    // MARK: - Recent Captures Section
    private var recentCapturesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Captures")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 20)
            
            VStack(spacing: 0) {
                // Show failed capture row at top if there's a pending failure
                if processingState.hasPendingFailure {
                    FailedCaptureRow(onDismiss: {
                        processingState.clearFailure()
                    })
                    
                    if !captureHistory.recentCaptures.isEmpty {
                        Divider().padding(.leading, 56)
                    }
                }
                
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
            .background(Color.white)
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

// MARK: - Failed Capture Row
private struct FailedCaptureRow: View {
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            // Warning icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.orange, in: RoundedRectangle(cornerRadius: 8))
            
            // Message
            VStack(alignment: .leading, spacing: 2) {
                Text("Capture failed")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text("Please try again")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.05))
    }
}

// MARK: - Capture Row
private struct CaptureRow: View {
    let capture: CapturedEvent
    @State private var showingEventDetail = false
    
    var body: some View {
        Button(action: showEventDetail) {
            HStack(spacing: 14) {
                // Source app icon
                Image(systemName: capture.eventIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 8))
                
                // Event details
                VStack(alignment: .leading, spacing: 4) {
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
                
                Text(capture.capturedAgo)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingEventDetail) {
            EventDetailSheet(eventIdentifier: capture.id, eventDate: capture.eventDate)
        }
    }
    
    private func showEventDetail() {
        // Check if event exists before showing sheet
        if CalendarService.shared.getEvent(withIdentifier: capture.id) != nil {
            showingEventDetail = true
        } else {
            // Event not found - fall back to opening Calendar
            openInCalendar()
        }
    }
    
    private func openInCalendar() {
        guard let date = capture.eventDate else {
            if let url = URL(string: "calshow:") {
                UIApplication.shared.open(url)
            }
            return
        }
        
        let timestamp = date.timeIntervalSinceReferenceDate
        if let url = URL(string: "calshow:\(timestamp)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Event Detail Sheet
struct EventDetailSheet: View {
    let eventIdentifier: String
    let eventDate: Date?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        EventDetailViewController(
            eventIdentifier: eventIdentifier,
            onDismiss: { dismiss() }
        )
        .ignoresSafeArea()
    }
}

// MARK: - Event Detail View Controller (UIKit wrapper)
struct EventDetailViewController: UIViewControllerRepresentable {
    let eventIdentifier: String
    let onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> UINavigationController {
        let eventVC = EKEventViewController()
        
        // Fetch the event
        if let event = CalendarService.shared.getEvent(withIdentifier: eventIdentifier) {
            eventVC.event = event
        }
        
        eventVC.allowsEditing = true
        eventVC.allowsCalendarPreview = true
        eventVC.delegate = context.coordinator
        
        let navController = UINavigationController(rootViewController: eventVC)
        
        // Add done button
        eventVC.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: context.coordinator,
            action: #selector(Coordinator.donePressed)
        )
        
        return navController
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }
    
    class Coordinator: NSObject, EKEventViewDelegate {
        let onDismiss: () -> Void
        
        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }
        
        @objc func donePressed() {
            onDismiss()
        }
        
        func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) {
            onDismiss()
        }
    }
}

// MARK: - Manage Account Sheet
struct ManageAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var authManager = AppleAuthManager.shared
    @State private var editedName: String = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Name")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        TextField("Your name", text: $editedName)
                            .font(.system(size: 16))
                            .padding(14)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08), lineWidth: 1))
                            .focused($isNameFocused)
                            .submitLabel(.done)
                            .onSubmit { saveName() }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Email")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        HStack(spacing: 12) {
                            Text(authManager.currentUser?.displayEmail ?? "Apple ID User")
                                .font(.system(size: 16))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    }

                    Spacer().frame(height: 8)

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
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .background(Color.white)
            .navigationTitle("Manage Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveName()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.light)
        .onAppear {
            editedName = authManager.currentUser?.name ?? ""
        }
    }

    private func saveName() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != authManager.currentUser?.name {
            authManager.updateName(trimmed)
        }
        isNameFocused = false
    }
}

#Preview {
    HomeView()
}
