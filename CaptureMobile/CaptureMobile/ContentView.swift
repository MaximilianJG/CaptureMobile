//
//  ContentView.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 17.01.26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var authManager = AppleAuthManager.shared
    
    var body: some View {
        Group {
            if authManager.isSignedIn {
                HomeView()
            } else {
                AuthView()
            }
        }
        .animation(.smooth(duration: 0.3), value: authManager.isSignedIn)
    }
}

#Preview {
    ContentView()
}
