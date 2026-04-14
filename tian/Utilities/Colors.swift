import AppKit

extension NSColor {
    static var terminalBackground: NSColor {
        GhosttyApp.shared.defaultBackgroundColor
    }

    convenience init(ghosttyRGB rgb: (UInt8, UInt8, UInt8)) {
        self.init(
            red: CGFloat(rgb.0) / 255.0,
            green: CGFloat(rgb.1) / 255.0,
            blue: CGFloat(rgb.2) / 255.0,
            alpha: 1.0
        )
    }
}
