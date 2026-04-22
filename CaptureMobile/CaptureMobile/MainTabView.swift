//
//  MainTabView.swift
//  CaptureMobile
//

import SwiftUI
import PostHog

struct MainTabView: View {
    @State private var selectedTab: Tab = .notes
    @State private var capturedPreview: UIImage?
    @State private var noteText: String = ""
    @State private var isSending = false

    private var hasCameraContent: Bool {
        capturedPreview != nil
    }

    private var hasNoteContent: Bool {
        !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                NotesView(
                    noteText: $noteText,
                    isSending: isSending,
                    onSend: { sendContent() }
                ).tag(Tab.notes)
                CameraView(capturedPreview: $capturedPreview).tag(Tab.camera)
                HomeView().tag(Tab.captures)
                ProfileView().tag(Tab.profile)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .allowsHitTesting(capturedPreview == nil)

            Group {
                if hasCameraContent {
                    sendDismissBar
                } else {
                    FloatingTabBar(selectedTab: $selectedTab)
                }
            }
            .padding(.bottom, 16)
        }
        .ignoresSafeArea(.keyboard)
    }

    // MARK: - Send / Dismiss Bar

    private var sendDismissBar: some View {
        HStack(spacing: 0) {
            Button { dismissContent() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(CaptureColors.text)
                    .frame(width: 52).padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            Button { sendContent() } label: {
                HStack(spacing: 6) {
                    if isSending {
                        ProgressView().scaleEffect(0.75).tint(.white)
                    } else {
                        Text("Send").font(CaptureFont.caption).fontWeight(.semibold)
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(CaptureColors.primary, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSending)
        }
        .padding(.horizontal, CaptureSpacing.sm).padding(.vertical, 6)
        .background(CaptureColors.card, in: Capsule())
        .overlay(Capsule().stroke(CaptureColors.border, lineWidth: 0.5))
        .captureShadow(.floating)
        .padding(.horizontal, CaptureSpacing.base)
        .transition(.opacity)
    }

    // MARK: - Actions

    private func dismissContent() {
        if capturedPreview != nil { capturedPreview = nil }
        else { noteText = "" }
    }

    private func sendContent() {
        isSending = true
        let image = capturedPreview
        let text = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = image != nil ? "camera" : "notes"

        PostHogSDK.shared.capture("capture_sent", properties: [
            "source": source, "has_image": image != nil, "has_text": !text.isEmpty
        ])

        Task {
            guard let userID = AppleAuthManager.shared.getUserID() else {
                await MainActor.run { isSending = false }
                return
            }

            if let jobID = await APIService.shared.uploadCaptureAsync(
                image: image, text: text.isEmpty ? nil : text, userID: userID, source: source
            ) {
                CaptureProcessingState.shared.startProcessing(jobID: jobID)
                PendingJobManager.shared.savePendingJob(jobID: jobID)
            } else if let image {
                BackgroundUploadManager.shared.enqueue(image: image, userID: userID)
            }

            await MainActor.run {
                capturedPreview = nil
                noteText = ""
                isSending = false
            }
        }
    }
}

#Preview { MainTabView() }
