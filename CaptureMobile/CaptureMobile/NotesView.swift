//
//  NotesView.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 20.03.26.
//

import SwiftUI

struct NotesView: View {
    @ObservedObject var authManager = AppleAuthManager.shared
    @Binding var noteText: String
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                headerSection
                    .padding(.top, 16)
                    .padding(.horizontal, 24)

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
            Text(greeting + ".")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.primary)

            Text(authManager.currentUser?.displayName ?? "")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)

            Text(formattedDate)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
    }

    // MARK: - Editor

    private var editor: some View {
        TextEditor(text: $noteText)
            .font(.system(size: 17))
            .foregroundStyle(.primary)
            .scrollContentBackground(.hidden)
            .focused($isEditorFocused)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 100)
    }

    // MARK: - Helpers

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Morning" }
        if hour < 17 { return "Afternoon" }
        return "Evening"
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }
}
