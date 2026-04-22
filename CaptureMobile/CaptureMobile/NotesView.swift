//
//  NotesView.swift
//  CaptureMobile

import SwiftUI

struct NotesView: View {
    @ObservedObject var authManager = AppleAuthManager.shared
    @Binding var noteText: String
    @FocusState private var isEditorFocused: Bool

    var isSending: Bool
    var onSend: () -> Void

    private var hasText: Bool {
        !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            CaptureColors.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                headerSection
                    .padding(.top, CaptureSpacing.base)
                    .padding(.horizontal, CaptureSpacing.xl)

                editor
                    .padding(.top, CaptureSpacing.md)
                    .padding(.horizontal, CaptureSpacing.screenHorizontalFeature)
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
                .font(CaptureFont.display)
                .foregroundStyle(CaptureColors.text)
                .tracking(-0.5)

            Text(formattedDateTime)
                .font(CaptureFont.monoSm)
                .foregroundStyle(CaptureColors.textTertiary)
                .padding(.top, 2)
        }
    }

    // MARK: - Editor

    private var editor: some View {
        TextEditor(text: $noteText)
            .font(CaptureFont.heading)
            .foregroundStyle(CaptureColors.text)
            .scrollContentBackground(.hidden)
            .focused($isEditorFocused)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if hasText {
                        keyboardSaveBar
                    }
                }
            }
    }

    // MARK: - Keyboard Save Bar

    private var keyboardSaveBar: some View {
        HStack(spacing: 0) {
            Button {
                isEditorFocused = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(CaptureColors.textSecondary)
                    .frame(width: 44)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            Button {
                saveAndContinue()
            } label: {
                HStack(spacing: 6) {
                    if isSending {
                        ProgressView().scaleEffect(0.7).tint(.white)
                    } else {
                        Text("Save").font(.system(size: 15, weight: .bold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(CaptureColors.primary, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSending)
        }
    }

    // MARK: - Actions

    private func saveAndContinue() {
        guard hasText else { return }
        onSend()
        // Clear the text immediately for the next note; keep focus so the
        // user can start typing again without tapping again.
        noteText = ""
        isEditorFocused = true
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
