//
//  CalendarPickerView.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 29.01.26.
//

import SwiftUI
import EventKit
import PostHog

/// Compact calendar picker that shows current selection and expands to sheet
struct CalendarPickerView: View {
    @ObservedObject var calendarService = CalendarService.shared
    @State private var showingPicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: CaptureSpacing.md) {
            Text("Saving Events To")
                .font(CaptureFont.overline)
                .foregroundStyle(CaptureColors.textSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, CaptureSpacing.screenHorizontalFeature)

            Button(action: { showingPicker = true }) {
                HStack(spacing: 14) {
                    Image(systemName: "calendar")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(CaptureColors.primary, in: RoundedRectangle(cornerRadius: CaptureRadius.md))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(calendarService.selectedCalendar?.source?.title ?? "Select Calendar")
                            .font(CaptureFont.title)
                            .foregroundStyle(CaptureColors.text)
                            .lineLimit(1)

                        if let calendar = calendarService.selectedCalendar {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(calendar.uiColor))
                                    .frame(width: 8, height: 8)

                                Text(calendar.title)
                                    .font(CaptureFont.bodySm)
                                    .foregroundStyle(CaptureColors.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CaptureColors.textTertiary)
                }
                .padding(CaptureSpacing.base)
                .background(CaptureColors.card, in: RoundedRectangle(cornerRadius: CaptureRadius.lg))
                .overlay(RoundedRectangle(cornerRadius: CaptureRadius.lg).stroke(CaptureColors.border, lineWidth: 0.5))
                .captureShadow(.card)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, CaptureSpacing.screenHorizontalFeature)
        }
        .sheet(isPresented: $showingPicker) {
            CalendarPickerSheet()
        }
    }
}

// MARK: - Calendar Picker Sheet

struct CalendarPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var calendarService = CalendarService.shared
    
    /// Group calendars by their source
    private var groupedCalendars: [(source: EKSource, calendars: [EKCalendar])] {
        let grouped = Dictionary(grouping: calendarService.calendars) { $0.source }
        return grouped.compactMap { source, calendars -> (EKSource, [EKCalendar])? in
            guard let source = source else { return nil }
            return (source, calendars.sorted { $0.title < $1.title })
        }
        .sorted { $0.source.title < $1.source.title }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if calendarService.calendars.isEmpty {
                        VStack(spacing: CaptureSpacing.md) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 40))
                                .foregroundStyle(CaptureColors.textSecondary)

                            Text("No calendars available")
                                .font(CaptureFont.heading)
                                .foregroundStyle(CaptureColors.textSecondary)

                            Text("Please grant calendar access in Settings")
                                .font(CaptureFont.bodySm)
                                .foregroundStyle(CaptureColors.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, CaptureSpacing.xxxl)
                    } else {
                        // Grouped calendar list
                        ForEach(groupedCalendars, id: \.source.sourceIdentifier) { source, calendars in
                            CalendarSourceSection(
                                source: source,
                                calendars: calendars,
                                selectedID: calendarService.selectedCalendarID,
                                onSelect: { calendar in
                                    calendarService.selectCalendar(calendar)
                                    PostHogSDK.shared.capture("calendar_selected", properties: [
                                        "calendar_title": calendar.title,
                                        "calendar_source": source.title
                                    ])
                                    dismiss()
                                }
                            )
                        }
                    }
                    
                    VStack(spacing: CaptureSpacing.xs) {
                        Button(action: openCalendarSettings) {
                            HStack(spacing: 6) {
                                Image(systemName: "gear")
                                    .font(.system(size: 14))
                                Text("Don't see your calendar? Add it in Settings")
                                    .font(CaptureFont.bodySm)
                            }
                            .foregroundStyle(CaptureColors.textSecondary)
                        }
                        .buttonStyle(.plain)

                        Text("Settings → Calendar → Accounts → Add Account")
                            .font(CaptureFont.monoXs)
                            .foregroundStyle(CaptureColors.textTertiary)
                    }
                    .padding(.top, CaptureSpacing.sm)
                    .padding(.bottom, CaptureSpacing.lg)
                }
                .padding(.top, 16)
            }
            .background(CaptureColors.bg)
            .navigationTitle("Select Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.light)
    }
    
    private func openCalendarSettings() {
        // Open the Settings app - unfortunately iOS doesn't allow deep-linking
        // to specific settings pages reliably, so we open the main Settings
        // and show instructions
        if let url = URL(string: "App-prefs:") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Calendar Source Section

private struct CalendarSourceSection: View {
    let source: EKSource
    let calendars: [EKCalendar]
    let selectedID: String?
    let onSelect: (EKCalendar) -> Void
    
    /// Format source title with account info
    private var sectionTitle: String {
        switch source.sourceType {
        case .local:
            return "On My iPhone"
        case .calDAV:
            // Usually iCloud or other CalDAV accounts
            if source.title.lowercased().contains("icloud") {
                return "iCloud"
            }
            return source.title
        case .exchange:
            return "Exchange"
        case .subscribed:
            return "Subscribed"
        case .birthdays:
            return "Birthdays"
        default:
            return source.title
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: CaptureSpacing.sm) {
            Text(sectionTitle)
                .font(CaptureFont.overline)
                .foregroundStyle(CaptureColors.textSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, CaptureSpacing.screenHorizontalFeature)

            VStack(spacing: 0) {
                ForEach(calendars, id: \.calendarIdentifier) { calendar in
                    CalendarRow(
                        calendar: calendar,
                        isSelected: calendar.calendarIdentifier == selectedID,
                        onSelect: { onSelect(calendar) }
                    )

                    if calendar.calendarIdentifier != calendars.last?.calendarIdentifier {
                        Divider().padding(.leading, 52).foregroundStyle(CaptureColors.border)
                    }
                }
            }
            .background(CaptureColors.card, in: RoundedRectangle(cornerRadius: CaptureRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: CaptureRadius.lg).stroke(CaptureColors.border, lineWidth: 0.5))
            .padding(.horizontal, CaptureSpacing.screenHorizontalFeature)
        }
    }
}

// MARK: - Calendar Row

private struct CalendarRow: View {
    let calendar: EKCalendar
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: CaptureSpacing.md) {
                Circle()
                    .fill(Color(calendar.uiColor))
                    .frame(width: 12, height: 12)

                Text(calendar.title)
                    .font(CaptureFont.title)
                    .foregroundStyle(CaptureColors.text)
                    .lineLimit(1)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CaptureColors.primary)
                }
            }
            .padding(.horizontal, CaptureSpacing.base)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CalendarPickerView()
}
