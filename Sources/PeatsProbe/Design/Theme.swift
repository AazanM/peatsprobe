import SwiftUI

/// Colour tokens transcribed from the SoundPEATS Control design file. Both
/// palettes are defined explicitly so the window never borrows the system
/// appearance halfway through a switch.
struct PeatsTheme: Equatable {
    var board: Color
    var shell: Color
    var shellFG: Color
    var shellFG2: Color
    var shellLine: Color

    var card: Color
    var card2: Color
    var card3: Color
    var cardFG: Color
    var cardFG2: Color
    var cardLine: Color
    var cardSolid: Color
    var cardSolidFG: Color

    var ok: Color
    var blue: Color
    var blueHover: Color
    var amber: Color
    var red: Color

    var shadow: Color
    var isDark: Bool

    static let light = PeatsTheme(
        board: Color(hex: 0xD9D4CA),
        shell: Color(hex: 0xF4F1EA),
        shellFG: Color(hex: 0x201D17),
        shellFG2: Color(hex: 0x6E6656),
        shellLine: Color(hex: 0x201D17, opacity: 0.14),
        card: Color(hex: 0xE9E0CD),
        card2: Color(hex: 0xDED2B9),
        card3: Color(hex: 0xD4C6A9),
        cardFG: Color(hex: 0x211E17),
        cardFG2: Color(hex: 0x6D6553),
        cardLine: Color(hex: 0x211E17, opacity: 0.14),
        cardSolid: Color(hex: 0x211E17),
        cardSolidFG: Color(hex: 0xF2ECDD),
        ok: Color(hex: 0x1F8F47),
        blue: Color(hex: 0x0A6ED1),
        blueHover: Color(hex: 0x0959A8),
        amber: Color(hex: 0xB98307),
        red: Color(hex: 0xC0392B),
        shadow: Color(hex: 0x3C321E, opacity: 0.16),
        isDark: false
    )

    static let dark = PeatsTheme(
        board: Color(hex: 0x17171A),
        shell: Color(hex: 0x202023),
        shellFG: Color(hex: 0xF2F2F5),
        shellFG2: Color(hex: 0x97979E),
        shellLine: Color(white: 1, opacity: 0.12),
        card: Color(hex: 0x000000),
        card2: Color(hex: 0x26262A),
        card3: Color(hex: 0x2C2C31),
        cardFG: Color(hex: 0xF4F4F7),
        cardFG2: Color(hex: 0x9B9BA3),
        cardLine: Color(white: 1, opacity: 0.13),
        cardSolid: Color(hex: 0xF4F4F7),
        cardSolidFG: Color(hex: 0x000000),
        ok: Color(hex: 0x34C759),
        blue: Color(hex: 0x2997FF),
        blueHover: Color(hex: 0x64B2FF),
        amber: Color(hex: 0xF5C33B),
        red: Color(hex: 0xFF5F52),
        shadow: Color(black: 0.55),
        isDark: true
    )
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    init(black opacity: Double) {
        self.init(.sRGB, red: 0, green: 0, blue: 0, opacity: opacity)
    }
}

private struct PeatsThemeKey: EnvironmentKey {
    static let defaultValue = PeatsTheme.light
}

extension EnvironmentValues {
    var peats: PeatsTheme {
        get { self[PeatsThemeKey.self] }
        set { self[PeatsThemeKey.self] = newValue }
    }
}

/// Type ramp. The design calls for Plus Jakarta Sans and IBM Plex Mono; on a
/// Mac the closest faithful pairing without shipping fonts is the system face
/// with tightened tracking, plus the system monospace for the technical rows.
enum PeatsFont {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }

    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    /// Display headings in the design are set tight; body copy is not.
    func displayTracking(_ size: CGFloat) -> some View {
        tracking(size * -0.03)
    }
}
