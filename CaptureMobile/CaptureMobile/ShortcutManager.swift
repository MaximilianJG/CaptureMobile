//
//  ShortcutManager.swift
//  CaptureMobile
//
//  Created by Maximilian Glasmacher on 17.01.26.
//

import Foundation
import UIKit

final class ShortcutManager {
    static let shared = ShortcutManager()
    private init() {}
    
    // MARK: - Configuration
    
    /// TODO: Replace with your actual iCloud shortcut link after creating and uploading the shortcut
    /// 
    /// To get this link:
    /// 1. Create a shortcut with: "Take Screenshot" → "Send to Capture"
    /// 2. Tap the shortcut name → Share → "Copy iCloud Link"
    /// 3. Paste the link here
    static let iCloudShortcutLink = "https://www.icloud.com/shortcuts/80663858d9b24fa3932876527c7d4f91"
    
    // MARK: - Install Shortcut
    
    /// Opens the iCloud shortcut link to install the pre-made shortcut
    func installShortcut() {
        guard let url = URL(string: ShortcutManager.iCloudShortcutLink) else {
            // Fallback: open Shortcuts app
            openShortcutsApp()
            return
        }
        
        UIApplication.shared.open(url)
    }
    
    // MARK: - Open Shortcuts App
    
    func openShortcutsApp() {
        if let url = URL(string: "shortcuts://") {
            UIApplication.shared.open(url)
        }
    }
}
