//
//  CalendarPickerView.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 29.01.26.
//

import SwiftUI
import EventKit
import PostHog

/// Displays a list of available calendars for the user to select
struct CalendarPickerView: View {
    @ObservedObject var calendarService = CalendarService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Events To")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 20)
            
            if calendarService.calendars.isEmpty {
                // No calendars available
                VStack(spacing: 8) {
                    Text("No calendars available")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Text("Please grant calendar access in Settings")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08), lineWidth: 1))
                .padding(.horizontal, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(calendarService.calendars, id: \.calendarIdentifier) { calendar in
                        CalendarRow(
                            calendar: calendar,
                            isSelected: calendar.calendarIdentifier == calendarService.selectedCalendarID,
                            onSelect: {
                                calendarService.selectCalendar(calendar)
                                PostHogSDK.shared.capture("calendar_selected", properties: [
                                    "calendar_title": calendar.title,
                                    "calendar_source": calendar.source?.title ?? "Unknown"
                                ])
                            }
                        )
                        
                        if calendar.calendarIdentifier != calendarService.calendars.last?.calendarIdentifier {
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
}

// MARK: - Calendar Row

private struct CalendarRow: View {
    let calendar: EKCalendar
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                // Calendar color indicator
                Circle()
                    .fill(Color(calendar.uiColor))
                    .frame(width: 12, height: 12)
                    .padding(.leading, 4)
                
                // Calendar info
                VStack(alignment: .leading, spacing: 2) {
                    Text(calendar.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    if let sourceName = calendar.source?.title, sourceName != calendar.title {
                        Text(sourceName)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact Calendar Picker (for inline use)

/// A compact version showing just the selected calendar with option to change
struct CompactCalendarPicker: View {
    @ObservedObject var calendarService = CalendarService.shared
    @State private var showingPicker = false
    
    var body: some View {
        Button(action: { showingPicker = true }) {
            HStack(spacing: 12) {
                // Calendar icon with color
                if let calendar = calendarService.selectedCalendar {
                    Circle()
                        .fill(Color(calendar.uiColor))
                        .frame(width: 10, height: 10)
                }
                
                Image(systemName: "calendar")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save Events To")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    
                    Text(calendarService.selectedCalendar?.title ?? "Select Calendar")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
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
        .sheet(isPresented: $showingPicker) {
            CalendarPickerSheet()
        }
    }
}

// MARK: - Calendar Picker Sheet

struct CalendarPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var calendarService = CalendarService.shared
    
    var body: some View {
        NavigationStack {
            ScrollView {
                CalendarPickerView()
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
}

#Preview {
    CalendarPickerView()
}
