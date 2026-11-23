import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

/// Colors from the approved light design. Greys are darkened for 4.5:1 contrast.
enum Theme {
    static let background = Color(hex: 0xF6F7F3)
    static let panel = Color.white
    static let border = Color(hex: 0xEDF0EB)
    static let divider = Color(hex: 0xEDF1EC)
    static let ink = Color(hex: 0x1D3038)
    static let muted = Color(hex: 0x5E6A70)
    static let eyebrow = Color(hex: 0x4E6E67)
    static let label = Color(hex: 0x3F5F58)

    static let teal = Color(hex: 0x157D72)
    static let tealText = Color(hex: 0x137A75)
    static let tealLight = Color(hex: 0x6BBFA9)
    static let mint = Color(hex: 0xE8F2ED)
    static let mintText = Color(hex: 0x17675E)
    static let brandTile = Color(hex: 0xD8EEE1)
    static let brandBar = Color(hex: 0x197E77)
    static let apricot = Color(hex: 0xEF9F67)

    static let field = Color(hex: 0xFBFCFA)
    static let fieldBorder = Color(hex: 0xE4EBE4)
    static let track = Color(hex: 0xE3EBE5)
    static let switchOn = Color(hex: 0x229681)
    static let switchOff = Color(hex: 0xC9D5CC)
    static let segment = Color(hex: 0xF1F5F0)

    static let tile = Color(hex: 0xFBFCF9)
    static let tileBorder = Color(hex: 0xE9EDE8)
    static let tileActive = Color(hex: 0xEAF7EF)
    static let tileActiveBorder = Color(hex: 0x64B59F)

    static let buttonBorder = Color(hex: 0xE3EAE5)
    static let buttonText = Color(hex: 0x2F4F48)
    static let smallButton = Color(hex: 0xF5F8F4)
    static let smallButtonBorder = Color(hex: 0xE4ECE6)
    static let smallButtonText = Color(hex: 0x3F6B62)
    static let danger = Color(hex: 0xFFF0EC)
    static let dangerText = Color(hex: 0xA3463A)

    static let deepTeal = Color(hex: 0x0F4744)
    static let inside = Color(hex: 0x169984)
    static let outside = Color(hex: 0xD99A5E)
    static let sceneIcon = Color(hex: 0xC27F3A)
    static let chipBorder = Color(hex: 0xDEEADB)
    static let chipBackground = Color(hex: 0xF7FAF5)
    static let shadow = Color(hex: 0x19423F, opacity: 0.06)
}
