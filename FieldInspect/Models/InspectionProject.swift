import Foundation
import SwiftData

@Model
final class InspectionProject {
    var id: UUID = UUID()
    var propertyAddress: String = ""
    var clientName: String = ""
    var propertyTypeRaw: String = PropertyType.singleFamily.rawValue
    var yearBuilt: Int = 1995
    var weatherConditions: String = "Clear"
    var ambientTemperature: String = "68°F"
    var inspectionDate: Date = Date()
    var isCompleted: Bool = false

    // Inspector credentials
    var inspectorName: String = ""
    var companyName: String = ""
    var licenseNumber: String = ""

    // Cover photo stored externally to keep SQLite queries fast
    @Attribute(.externalStorage)
    var coverPhotoData: Data?

    @Relationship(deleteRule: .cascade, inverse: \DefectEntry.project)
    var defects: [DefectEntry]? = []

    init(
        id: UUID = UUID(),
        propertyAddress: String = "",
        clientName: String = "",
        propertyType: PropertyType = .singleFamily,
        yearBuilt: Int = 1995,
        weatherConditions: String = "Clear",
        ambientTemperature: String = "68°F",
        inspectionDate: Date = Date(),
        isCompleted: Bool = false,
        inspectorName: String = "",
        companyName: String = "",
        licenseNumber: String = "",
        coverPhotoData: Data? = nil
    ) {
        self.id = id
        self.propertyAddress = propertyAddress
        self.clientName = clientName
        self.propertyTypeRaw = propertyType.rawValue
        self.yearBuilt = yearBuilt
        self.weatherConditions = weatherConditions
        self.ambientTemperature = ambientTemperature
        self.inspectionDate = inspectionDate
        self.isCompleted = isCompleted
        self.inspectorName = inspectorName
        self.companyName = companyName
        self.licenseNumber = licenseNumber
        self.coverPhotoData = coverPhotoData
    }

    var propertyType: PropertyType {
        get { PropertyType(rawValue: propertyTypeRaw) ?? .singleFamily }
        set { propertyTypeRaw = newValue.rawValue }
    }

    var safeDefects: [DefectEntry] {
        (defects ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    func count(for severity: DefectSeverity) -> Int {
        safeDefects.filter { $0.severity == severity }.count
    }

    func defects(in system: BuildingSystem) -> [DefectEntry] {
        safeDefects
            .filter { $0.buildingSystem == system }
            .sorted {
                if $0.severity.sortPriority != $1.severity.sortPriority {
                    return $0.severity.sortPriority < $1.severity.sortPriority
                }
                return $0.createdAt < $1.createdAt
            }
    }

    var pendingAICount: Int {
        safeDefects.filter { $0.syncStatus == .pendingAI || $0.syncStatus == .failed }.count
    }
}
