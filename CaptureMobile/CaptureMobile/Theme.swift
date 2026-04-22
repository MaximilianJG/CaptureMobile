//
//  Theme.swift
//  CaptureMobile
//

import SwiftUI

// MARK: - Color Tokens

enum CaptureColors {
    // Primary
    static let primary = Color(hex: 0xC66240)
    static let primaryLight = Color(hex: 0xD4845F)
    static let primaryDark = Color(hex: 0xA84E30)
    static let primaryMuted = Color(hex: 0xC66240).opacity(0.07)
    static let primaryGhost = Color(hex: 0xC66240).opacity(0.03)

    // Neutrals
    static let bg = Color(hex: 0xFAF8F5)
    static let card = Color.white
    static let cardPressed = Color(hex: 0xF7F4F0)
    static let surface = Color(hex: 0xF0ECE7)
    static let text = Color(hex: 0x1A1714)
    static let textSecondary = Color(hex: 0x6B6560)
    static let textTertiary = Color(hex: 0x9C9690)
    static let textHint = Color(hex: 0xB5B0A8)
    static let border = Color(hex: 0x1A1714).opacity(0.06)
    static let borderStrong = Color(hex: 0x1A1714).opacity(0.12)

    // Semantic
    static let success = Color(hex: 0x5DCAA5)
    static let successMuted = Color(hex: 0x5DCAA5).opacity(0.10)
    static let warning = Color(hex: 0xEF9F27)
    static let warningMuted = Color(hex: 0xEF9F27).opacity(0.10)
    static let danger = Color(hex: 0xE24B4A)
    static let dangerMuted = Color(hex: 0xE24B4A).opacity(0.10)
    static let info = Color(hex: 0x85B7EB)
    static let infoMuted = Color(hex: 0x85B7EB).opacity(0.10)
}

// MARK: - Typography

enum CaptureFont {
    private static let displayFamily = "LibreFranklin"
    private static let monoFamily = "JetBrainsMono"
    private static let systemFallback = Font.Design.default
    private static let monoFallback = Font.Design.monospaced

    static let display = libreFranklin(size: 32, weight: .bold)
    static let headingLg = libreFranklin(size: 24, weight: .semibold)
    static let heading = libreFranklin(size: 17, weight: .semibold)
    static let title = libreFranklin(size: 15, weight: .semibold)
    static let body = libreFranklin(size: 13, weight: .regular)
    static let bodySm = libreFranklin(size: 12, weight: .regular)
    static let caption = libreFranklin(size: 11, weight: .medium)
    static let monoSm = jetBrainsMono(size: 10.5, weight: .regular)
    static let monoXs = jetBrainsMono(size: 9.5, weight: .regular)
    static let monoSection = jetBrainsMono(size: 9, weight: .medium)
    static let overline = libreFranklin(size: 11, weight: .semibold)

    // UIFont equivalents for text measurement
    static func uiFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        if let font = UIFont(name: uiFontName(for: weight), size: size) {
            return font
        }
        return UIFont.systemFont(ofSize: size, weight: weight)
    }

    private static func libreFranklin(size: CGFloat, weight: Font.Weight) -> Font {
        let name = swiftFontName(family: displayFamily, weight: weight)
        if UIFont(name: name, size: size) != nil {
            return Font.custom(name, size: size)
        }
        return Font.system(size: size, weight: weight, design: systemFallback)
    }

    private static func jetBrainsMono(size: CGFloat, weight: Font.Weight) -> Font {
        let name = swiftFontName(family: monoFamily, weight: weight)
        if UIFont(name: name, size: size) != nil {
            return Font.custom(name, size: size)
        }
        return Font.system(size: size, weight: weight, design: monoFallback)
    }

    private static func swiftFontName(family: String, weight: Font.Weight) -> String {
        let suffix: String
        switch weight {
        case .bold: suffix = "-Bold"
        case .semibold: suffix = "-SemiBold"
        case .medium: suffix = "-Medium"
        case .regular: suffix = "-Regular"
        case .light: suffix = "-Light"
        default: suffix = "-Regular"
        }
        return family + suffix
    }

    private static func uiFontName(for weight: UIFont.Weight) -> String {
        let suffix: String
        switch weight {
        case .bold: suffix = "-Bold"
        case .semibold: suffix = "-SemiBold"
        case .medium: suffix = "-Medium"
        case .regular: suffix = "-Regular"
        case .light: suffix = "-Light"
        default: suffix = "-Regular"
        }
        return displayFamily + suffix
    }
}

// MARK: - Spacing

enum CaptureSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let base: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
    static let huge: CGFloat = 48

    static let cardPadding: CGFloat = 14
    static let cardGap: CGFloat = 10
    static let sectionGap: CGFloat = 28
    static let extractedPadding: CGFloat = 10
    static let tagGap: CGFloat = 5
    static let screenHorizontal: CGFloat = 16
    static let screenHorizontalFeature: CGFloat = 20
}

// MARK: - Radius

enum CaptureRadius {
    static let sm: CGFloat = 5
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let pill: CGFloat = 22
}

// MARK: - Shadows

struct CaptureShadow {
    let color: Color
    let radius: CGFloat
    let y: CGFloat

    static let card = CaptureShadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
    static let cardPressed = CaptureShadow(color: Color.black.opacity(0.05), radius: 12, y: 4)
    static let floating = CaptureShadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
    static let fab = CaptureShadow(color: CaptureColors.primary.opacity(0.25), radius: 10, y: 4)
    static let sheet = CaptureShadow(color: Color.black.opacity(0.06), radius: 15, y: -4)
}

// MARK: - View Extension for Shadows

extension View {
    func captureShadow(_ shadow: CaptureShadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
    }
}

// MARK: - Color Extension (hex init)

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}
