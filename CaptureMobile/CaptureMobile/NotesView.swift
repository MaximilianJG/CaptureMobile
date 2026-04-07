//
//  NotesView.swift
//  CaptureMobile

import SwiftUI

struct NotesView: View {
    @ObservedObject var authManager = AppleAuthManager.shared
    @ObservedObject var processingState = CaptureProcessingState.shared
    @Binding var noteText: String
    @FocusState private var isEditorFocused: Bool

    var isSending: Bool
    var onSend: () -> Void
    var onDismiss: () -> Void

    private var hasText: Bool {
        !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                headerSection
                    .padding(.top, 16)
                    .padding(.horizontal, 24)

                if processingState.isProcessing && !processingState.hasPendingFailure {
                    processingBanner
                        .padding(.top, 12)
                        .padding(.horizontal, 24)
                }

                editor
                    .padding(.top, 12)
                    .padding(.horizontal, 20)
            }
        }
        .onTapGesture {
            isEditorFocused = true
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greetingWithName)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.primary)

            Text(formattedDateTime)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
    }

    // MARK: - Processing Banner

    private var processingBanner: some View {
        HStack(spacing: 10) {
            ProgressView().scaleEffect(0.7)
            Text("Analyzing capture...")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Editor

    private var editor: some View {
        TextEditor(text: $noteText)
            .font(.system(size: 17))
            .foregroundStyle(.primary)
            .scrollContentBackground(.hidden)
            .focused($isEditorFocused)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 60)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if hasText {
                        keyboardSendBar
                    }
                }
            }
    }

    // MARK: - Keyboard Send Bar

    private var keyboardSendBar: some View {
        HStack(spacing: 0) {
            Button {
                onDismiss()
                isEditorFocused = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 44).padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            Button {
                onSend()
                isEditorFocused = false
            } label: {
                HStack(spacing: 6) {
                    if isSending {
                        ProgressView().scaleEffect(0.7).tint(.white)
                    } else {
                        Text("Send").font(.system(size: 14, weight: .semibold))
                        Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(Color.black, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSending)
        }
    }

    // MARK: - Helpers

    private var greetingWithName: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay: String
        if hour < 12 { timeOfDay = "Morning" }
        else if hour < 17 { timeOfDay = "Afternoon" }
        else { timeOfDay = "Evening" }

        let firstName = authManager.currentUser?.displayName.components(separatedBy: " ").first ?? ""
        if firstName.isEmpty { return timeOfDay }
        return "\(timeOfDay), \(firstName)"
    }

    private var formattedDateTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d · h:mm a"
        return formatter.string(from: Date())
    }
}
