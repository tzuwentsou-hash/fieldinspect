import SwiftUI

/// Field-ready, high-contrast design system for outdoor & crawlspace legibility.
enum DesignSystem {
    enum Colors {
        static let brandPrimary = Color(hex: 0x1E293B)       // Deep Slate
        static let brandAccent = Color(hex: 0xD97706)        // High-Visibility Field Amber

        static let backgroundLight = Color(hex: 0xF8FAFC)
        static let backgroundDark = Color(hex: 0x0F172A)

        // InterNACHI Severity Semantic Colors
        static let severitySafetyHazard = Color(hex: 0xDC2626) // Crimson Red
        static let severityMajorDefect = Color(hex: 0xEA580C)  // Safety Orange
        static let severityMonitor = Color(hex: 0x2563EB)      // Cobalt Blue
        static let severitySatisfactory = Color(hex: 0x16A34A) // Emerald Green

        static let cardBorder = Color.secondary.opacity(0.22)
        static let surfaceSecondary = Color(UIColor.secondarySystemGroupedBackground)
        static let surfacePrimary = Color(UIColor.systemGroupedBackground)
    }

    enum Typography {
        static func monospacedCaption() -> Font {
            .caption.monospacedDigit()
        }

        static func monospacedHeadline() -> Font {
            .headline.monospacedDigit()
        }

        static func monospacedTitle() -> Font {
            .title2.bold().monospacedDigit()
        }
    }

    enum Layout {
        static let cornerRadius: CGFloat = 12
        static let cardPadding: CGFloat = 14
        static let sectionSpacing: CGFloat = 16
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

/// Reusable high-contrast pill badge for InterNACHI severity levels.
struct SeverityBadge: View {
    let severity: DefectSeverity
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: severity.sfSymbol)
                .font(compact ? .caption2.bold() : .caption.bold())
            Text(compact ? severity.shortLabel : severity.displayName)
                .font(compact ? .caption2.bold() : .caption.bold())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 5)
        .background(severity.color, in: Capsule())
    }
}

/// Reusable status badge for offline/queued/syncing/failed AI entries.
struct SyncStatusBadge: View {
    let status: SyncStatus

    var body: some View {
        if status != .synced {
            HStack(spacing: 4) {
                Image(systemName: status.sfSymbol)
                    .font(.caption2.bold())
                Text(status.displayName)
                    .font(.caption2.bold())
            }
            .foregroundStyle(status.foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.backgroundColor, in: Capsule())
        }
    }
}

/// Adaptive horizontal brand logo that switches cleanly between Light and Dark Mode.
struct BrandLogoView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(colorScheme == .dark ? "BrandLogoDark" : "BrandLogo")
            .resizable()
            .scaledToFit()
    }
}
