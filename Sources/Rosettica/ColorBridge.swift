import AppKit
import SwiftUI
import RosetticaCore

extension RGBAColor {
    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(
            red: ns.redComponent,
            green: ns.greenComponent,
            blue: ns.blueComponent,
            alpha: ns.alphaComponent
        )
    }

    var luminance: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}
