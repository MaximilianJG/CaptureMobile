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
}

struct FloatingTabBar: View {
    @Binding var selectedTab: Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                } label: {
                    Image(systemName: selectedTab == tab ? tab.selectedIcon : tab.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(selectedTab == tab ? .primary : .secondary.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.horizontal, 40)
    }
}
