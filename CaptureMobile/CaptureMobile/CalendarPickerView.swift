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
        VStack(alignment: .leading, spacing: 12) {
            Text("Saving Events To")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 20)
            
            // Compact selected calendar display
            Button(action: { showingPicker = true }) {
                HStack(spacing: 14) {
                    // Calendar icon
                    Image(systemName: "calendar")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 8))
                    
                    // Source name and calendar
                    VStack(alignment: .leading, spacing: 2) {
                        Text(calendarService.selectedCalendar?.source?.title ?? "Select Calendar")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        // Calendar name with color dot
                        if let calendar = calendarService.selectedCalendar {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(calendar.uiColor))
                                    .frame(width: 8, height: 8)
                                
                                Text(calendar.title)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Chevron
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
                        // No calendars available
                        VStack(spacing: 12) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            
                            Text("No calendars available")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                            
                            Text("Please grant calendar access in Settings")
                                .font(.system(size: 14))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
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
                    
                    // Help link
                    VStack(spacing: 4) {
                        Button(action: openCalendarSettings) {
                            HStack(spacing: 6) {
                                Image(systemName: "gear")
                                    .font(.system(size: 14))
                                Text("Don't see your calendar? Add it in Settings")
                                    .font(.system(size: 14))
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        
                        Text("Settings → Calendar → Accounts → Add Account")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .padding(.top, 16)
            }
            .background(Color(.systemGroupedBackground))
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
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            Text(sectionTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 20)
            
            // Calendar rows
            VStack(spacing: 0) {
                ForEach(calendars, id: \.calendarIdentifier) { calendar in
                    CalendarRow(
                        calendar: calendar,
                        isSelected: calendar.calendarIdentifier == selectedID,
                        onSelect: { onSelect(calendar) }
                    )
                    
                    if calendar.calendarIdentifier != calendars.last?.calendarIdentifier {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08), lineWidth: 1))
            .padding(.horizontal, 20)
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
            HStack(spacing: 12) {
                // Calendar color indicator
                Circle()
                    .fill(Color(calendar.uiColor))
                    .frame(width: 12, height: 12)
                
                // Calendar name
                Text(calendar.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CalendarPickerView()
}
