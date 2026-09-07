import AppKit
import Foundation

enum AppTheme {
    static let windowBackground = NSColor(calibratedRed: 0.955, green: 0.958, blue: 0.965, alpha: 1)
    static let panelBackground = NSColor.white
    static let barBackground = NSColor(calibratedRed: 0.975, green: 0.978, blue: 0.985, alpha: 1)
    static let controlBackground = NSColor(calibratedRed: 0.915, green: 0.925, blue: 0.94, alpha: 1)
    static let primaryBlue = NSColor(calibratedRed: 0.04, green: 0.39, blue: 0.82, alpha: 1)
    static let accentFill = NSColor(calibratedRed: 0.04, green: 0.39, blue: 0.82, alpha: 1)
    static let selectedBlue = NSColor(calibratedRed: 0.90, green: 0.94, blue: 0.995, alpha: 1)
    static let border = NSColor(calibratedWhite: 0.15, alpha: 0.09)
    static let text = NSColor(calibratedRed: 0.13, green: 0.145, blue: 0.17, alpha: 1)
    static let secondaryText = NSColor(calibratedRed: 0.43, green: 0.46, blue: 0.51, alpha: 1)
    static let videoBackground = NSColor(calibratedRed: 0.025, green: 0.03, blue: 0.045, alpha: 1)
    static let videoHighlight = NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.19, alpha: 1)
    static let videoSecondaryText = NSColor(calibratedRed: 0.70, green: 0.73, blue: 0.80, alpha: 1)
    static let canvasBorder = NSColor.white.withAlphaComponent(0.10)
}

enum AppBuildInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }

    static var creationTime: String {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "MVPBuildDate") as? String,
            let date = ISO8601DateFormatter().date(from: value)
        else {
            return "Development build"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
