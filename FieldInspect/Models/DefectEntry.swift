import Foundation
import SwiftData

@Model
final class DefectEntry {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    // Domain classification
    var buildingSystemRaw: String = BuildingSystem.exterior.rawValue
    var severityRaw: String = DefectSeverity.monitor.rawValue
    var syncStatusRaw: String = SyncStatus.pendingAI.rawValue

    // Structured AI & Editable Findings
    var location: String = ""
    var defectTitle: String = ""
    var observationNarrative: String = ""
    var recommendation: String = ""
    var rawTranscript: String = ""
    var visualObservationsAdded: String?
    var lastSyncError: String?

    // Up to 4 annotated & downsampled JPEG photos stored externally
    @Attribute(.externalStorage) var photo1Data: Data?
    @Attribute(.externalStorage) var photo2Data: Data?
    @Attribute(.externalStorage) var photo3Data: Data?
    @Attribute(.externalStorage) var photo4Data: Data?

    // Voice memo (.m4a) stored externally for offline retry
    @Attribute(.externalStorage) var audioMemoData: Data?

    var project: InspectionProject?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        buildingSystem: BuildingSystem = .exterior,
        severity: DefectSeverity = .monitor,
        syncStatus: SyncStatus = .pendingAI,
        location: String = "",
        defectTitle: String = "",
        observationNarrative: String = "",
        recommendation: String = "",
        rawTranscript: String = "",
        visualObservationsAdded: String? = nil,
        photos: [Data] = [],
        audioMemoData: Data? = nil,
        project: InspectionProject? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.buildingSystemRaw = buildingSystem.rawValue
        self.severityRaw = severity.rawValue
        self.syncStatusRaw = syncStatus.rawValue
        self.location = location
        self.defectTitle = defectTitle
        self.observationNarrative = observationNarrative
        self.recommendation = recommendation
        self.rawTranscript = rawTranscript
        self.visualObservationsAdded = visualObservationsAdded
        self.audioMemoData = audioMemoData
        self.project = project
        self.setPhotos(photos)
    }

    var buildingSystem: BuildingSystem {
        get { BuildingSystem(rawValue: buildingSystemRaw) ?? .exterior }
        set { buildingSystemRaw = newValue.rawValue }
    }

    var severity: DefectSeverity {
        get { DefectSeverity(rawValue: severityRaw) ?? .monitor }
        set { severityRaw = newValue.rawValue }
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pendingAI }
        set { syncStatusRaw = newValue.rawValue }
    }

    var photos: [Data] {
        [photo1Data, photo2Data, photo3Data, photo4Data].compactMap { $0 }
    }

    func setPhotos(_ newPhotos: [Data]) {
        let clamped = Array(newPhotos.prefix(AppConfig.Media.maxPhotosPerDefect))
        photo1Data = clamped.indices.contains(0) ? clamped[0] : nil
        photo2Data = clamped.indices.contains(1) ? clamped[1] : nil
        photo3Data = clamped.indices.contains(2) ? clamped[2] : nil
        photo4Data = clamped.indices.contains(3) ? clamped[3] : nil
    }
}
