import AppKit
import Foundation

enum AppTheme {
    static let windowBackground = NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.97, alpha: 1)
    static let panelBackground = NSColor(calibratedWhite: 1, alpha: 0.72)
    static let barBackground = NSColor(calibratedWhite: 1, alpha: 0.78)
    static let controlBackground = NSColor(calibratedRed: 0.89, green: 0.91, blue: 0.95, alpha: 0.78)
    static let primaryBlue = NSColor(calibratedRed: 0.16, green: 0.43, blue: 0.96, alpha: 1)
    static let selectedBlue = NSColor(calibratedRed: 0.19, green: 0.48, blue: 0.98, alpha: 0.16)
    static let border = NSColor(calibratedRed: 0.07, green: 0.10, blue: 0.16, alpha: 0.10)
    static let text = NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.14, alpha: 1)
    static let secondaryText = NSColor(calibratedRed: 0.36, green: 0.39, blue: 0.47, alpha: 1)
    static let videoBackground = NSColor(calibratedRed: 0.035, green: 0.042, blue: 0.062, alpha: 1)
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

