//
//  FloatingTabBar.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 20.03.26.
//

import SwiftUI

enum Tab: Int, CaseIterable {
    case notes
    case camera
    case captures
    case profile

    var icon: String {
        switch self {
        case .notes:    return "note.text"
        case .camera:   return "camera"
        case .captures: return "clock.arrow.circlepath"
        case .profile:  return "person"
        }
    }

    var selectedIcon: String {
        switch self {
        case .notes:    return "note.text"
        case .camera:   return "camera.fill"
        case .captures: return "clock.arrow.circlepath"
        case .profile:  return "person.fill"
        }
    }

    var label: String {
        switch self {
        case .notes:    return "Notes"
        case .camera:   return "Camera"
        case .captures: return "Captures"
        case .profile:  return "Profile"
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selectedTab: Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.rawValue) { tab in
                let isActive = selectedTab == tab
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                } label: {
                    Image(systemName: isActive ? tab.selectedIcon : tab.icon)
                        .font(.system(size: 22))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isActive ? CaptureColors.primary : CaptureColors.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, CaptureSpacing.sm)
        .padding(.vertical, 6)
        .background(CaptureColors.card, in: Capsule())
        .overlay(Capsule().stroke(CaptureColors.border, lineWidth: 0.5))
        .captureShadow(.floating)
        .padding(.horizontal, CaptureSpacing.base)
    }
}
