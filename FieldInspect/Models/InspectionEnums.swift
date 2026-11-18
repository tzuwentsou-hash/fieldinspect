import SwiftUI

/// InterNACHI Standard Order Building Systems (8 systems).
enum BuildingSystem: String, Codable, CaseIterable, Identifiable {
    case roof
    case exterior
    case structure
    case electrical
    case hvac
    case plumbing
    case interior
    case insulation

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .roof: return String(localized: "Roofing & Flashings")
        case .exterior: return String(localized: "Exterior, Siding & Grading")
        case .structure: return String(localized: "Foundation & Structure")
        case .electrical: return String(localized: "Electrical System")
        case .hvac: return String(localized: "Heating, Ventilation & Cooling")
        case .plumbing: return String(localized: "Plumbing System")
        case .interior: return String(localized: "Interior, Windows & Doors")
        case .insulation: return String(localized: "Attic, Insulation & Ventilation")
        }
    }

    var shortName: String {
        switch self {
        case .roof: return String(localized: "Roofing")
        case .exterior: return String(localized: "Exterior")
        case .structure: return String(localized: "Structure")
        case .electrical: return String(localized: "Electrical")
        case .hvac: return String(localized: "HVAC")
        case .plumbing: return String(localized: "Plumbing")
        case .interior: return String(localized: "Interior")
        case .insulation: return String(localized: "Attic & Insulation")
        }
    }

    var sfSymbol: String {
        switch self {
        case .roof: return "house.lodge.fill"
        case .exterior: return "building.2.fill"
        case .structure: return "square.stack.3d.down.right.fill"
        case .electrical: return "bolt.trianglebadge.exclamationmark.fill"
        case .hvac: return "fanblades.fill"
        case .plumbing: return "drop.triangle.fill"
        case .interior: return "door.left.hand.open"
        case .insulation: return "thermometer.medium"
        }
    }

    var sortOrder: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

/// InterNACHI Severity Classification Tiers.
enum DefectSeverity: String, Codable, CaseIterable, Identifiable {
    case safetyHazard
    case majorDefect
    case monitor
    case satisfactory

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .safetyHazard: return String(localized: "Safety Hazard")
        case .majorDefect: return String(localized: "Major Defect")
        case .monitor: return String(localized: "Monitor / Maintenance")
        case .satisfactory: return String(localized: "Inspected / Functional")
        }
    }

    var shortLabel: String {
        switch self {
        case .safetyHazard: return String(localized: "Safety")
        case .majorDefect: return String(localized: "Major")
        case .monitor: return String(localized: "Monitor")
        case .satisfactory: return String(localized: "OK")
        }
    }

    var color: Color {
        switch self {
        case .safetyHazard: return DesignSystem.Colors.severitySafetyHazard
        case .majorDefect: return DesignSystem.Colors.severityMajorDefect
        case .monitor: return DesignSystem.Colors.severityMonitor
        case .satisfactory: return DesignSystem.Colors.severitySatisfactory
        }
    }

    var uiColor: UIColor {
        switch self {
        case .safetyHazard: return UIColor(red: 0.863, green: 0.149, blue: 0.149, alpha: 1.0)
        case .majorDefect: return UIColor(red: 0.918, green: 0.345, blue: 0.047, alpha: 1.0)
        case .monitor: return UIColor(red: 0.145, green: 0.388, blue: 0.922, alpha: 1.0)
        case .satisfactory: return UIColor(red: 0.086, green: 0.639, blue: 0.290, alpha: 1.0)
        }
    }

    var sfSymbol: String {
        switch self {
        case .safetyHazard: return "exclamationmark.octagon.fill"
        case .majorDefect: return "exclamationmark.triangle.fill"
        case .monitor: return "eye.fill"
        case .satisfactory: return "checkmark.seal.fill"
        }
    }

    var sortPriority: Int {
        switch self {
        case .safetyHazard: return 0
        case .majorDefect: return 1
        case .monitor: return 2
        case .satisfactory: return 3
        }
    }
}

/// Offline basement/crawlspace sync state for Gemini AI synthesis.
enum SyncStatus: String, Codable, CaseIterable {
    case pendingAI
    case syncing
    case synced
    case failed

    var displayName: String {
        switch self {
        case .pendingAI: return String(localized: "Queued for AI (Offline)")
        case .syncing: return String(localized: "Analyzing with AI…")
        case .synced: return String(localized: "AI Synthesized")
        case .failed: return String(localized: "AI Retry Needed")
        }
    }

    var sfSymbol: String {
        switch self {
        case .pendingAI: return "tray.and.arrow.up.fill"
        case .syncing: return "sparkles"
        case .synced: return "checkmark.circle.fill"
        case .failed: return "arrow.clockwise.circle.fill"
        }
    }

    var foregroundColor: Color {
        switch self {
        case .pendingAI: return .white
        case .syncing: return .white
        case .synced: return DesignSystem.Colors.severitySatisfactory
        case .failed: return .white
        }
    }

    var backgroundColor: Color {
        switch self {
        case .pendingAI: return DesignSystem.Colors.brandAccent
        case .syncing: return DesignSystem.Colors.severityMonitor
        case .synced: return DesignSystem.Colors.severitySatisfactory.opacity(0.15)
        case .failed: return DesignSystem.Colors.severitySafetyHazard
        }
    }
}

enum PropertyType: String, Codable, CaseIterable, Identifiable {
    case singleFamily = "Single Family"
    case townhouse = "Townhouse"
    case condo = "Condominium"
    case multiFamily = "Multi-Family"

    var id: String { rawValue }

    /// Localized label for UI and PDF. `rawValue` stays English: it is persisted and sent to Gemini.
    var displayName: String {
        switch self {
        case .singleFamily: return String(localized: "Single Family")
        case .townhouse: return String(localized: "Townhouse")
        case .condo: return String(localized: "Condominium")
        case .multiFamily: return String(localized: "Multi-Family")
        }
    }
}

/// Weather presets. The English `rawValue` is what gets persisted in `InspectionProject.weatherConditions`,
/// so existing data keeps working; only the displayed label is localized.
enum WeatherCondition: String, CaseIterable, Identifiable {
    case clear = "Clear"
    case partlyCloudy = "Partly Cloudy"
    case overcast = "Overcast"
    case lightRain = "Light Rain"
    case heavyRain = "Heavy Rain"
    case snowCold = "Snow / Cold"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clear: return String(localized: "Clear")
        case .partlyCloudy: return String(localized: "Partly Cloudy")
        case .overcast: return String(localized: "Overcast")
        case .lightRain: return String(localized: "Light Rain")
        case .heavyRain: return String(localized: "Heavy Rain")
        case .snowCold: return String(localized: "Snow / Cold")
        }
    }

    /// Localized label for a stored weather string; free text that isn't a preset is shown as-is.
    static func displayName(for stored: String) -> String {
        WeatherCondition(rawValue: stored)?.displayName ?? stored
    }

    /// Default ambient temperature text in the user's preferred unit (68°F in the US, 20°C elsewhere).
    static var defaultAmbientTemperature: String {
        let formatter = MeasurementFormatter()
        formatter.locale = AppLocale.locale
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 0
        let celsius = Measurement(value: 20, unit: UnitTemperature.celsius)
        let usesFahrenheit = AppLocale.locale.measurementSystem == .us
        let value = usesFahrenheit ? celsius.converted(to: .fahrenheit) : celsius
        return formatter.string(from: value)
    }
}
