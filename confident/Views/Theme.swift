import SwiftUI

/// Centralized palette + reusable gradients for the futuristic dark theme.
enum Theme {

    // Surfaces
    static let bgBase     = Color(red: 0.030, green: 0.038, blue: 0.090)
    static let bgElevated = Color(red: 0.075, green: 0.090, blue: 0.165)
    static let surfaceTint = Color.white.opacity(0.06)
    static let strokeTint  = Color.white.opacity(0.14)

    // Neon accents
    static let neonCyan    = Color(red: 0.20, green: 0.95, blue: 1.00)
    static let neonViolet  = Color(red: 0.60, green: 0.30, blue: 0.95)
    static let neonMagenta = Color(red: 1.00, green: 0.20, blue: 0.55)
    static let neonGreen   = Color(red: 0.30, green: 0.95, blue: 0.55)
    static let neonAmber   = Color(red: 1.00, green: 0.78, blue: 0.30)

    // Brand gradient — used on the user bubble, send button, accents
    static let brand = LinearGradient(
        colors: [neonViolet, neonCyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let brandReversed = LinearGradient(
        colors: [neonCyan, neonViolet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
