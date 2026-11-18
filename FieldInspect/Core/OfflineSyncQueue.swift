import Foundation
import Network
import Observation
import SwiftData

@Observable
@MainActor
final class OfflineSyncQueue {
    private(set) var isOnline: Bool = true
    private(set) var isProcessingQueue: Bool = false
    private(set) var pendingCount: Int = 0

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let monitorQueue = DispatchQueue(label: "com.fieldinspect.ai.networkmonitor")
    @ObservationIgnored private var modelContainer: ModelContainer?
    @ObservationIgnored private var activeTask: Task<Void, Never>?

    @ObservationIgnored private var isMonitoringStarted = false

    init() {}

    deinit {
        monitor.cancel()
    }

    func configure(modelContainer: ModelContainer) {
        guard self.modelContainer == nil else { return } // onAppear can fire more than once
        self.modelContainer = modelContainer
        if !isMonitoringStarted {
            isMonitoringStarted = true
            startMonitoring()
        }
        recoverInterruptedEntries()
        refreshPendingCount()
        if isOnline {
            triggerSyncIfNeeded()
        }
    }

    func enqueueAndProcessIfOnline(_ entry: DefectEntry) {
        if isOnline {
            entry.syncStatus = .pendingAI
            refreshPendingCount()
            triggerSyncIfNeeded()
        } else {
            entry.syncStatus = .pendingAI
            refreshPendingCount()
        }
    }

    func retryEntry(_ entry: DefectEntry) {
        entry.syncStatus = .pendingAI
        entry.lastSyncError = nil
        try? entry.modelContext?.save()
        refreshPendingCount()
        triggerSyncIfNeeded()
    }

    /// "Sync" buttons: re-queue findings that previously failed, then drain the queue.
    /// (The pending badge counts failed entries too, so syncing only `.pendingAI` left the
    /// banner stuck with nothing happening when the user tapped Sync.)
    func retryAllAndSync() {
        if let container = modelContainer {
            let context = container.mainContext
            let failedRaw = SyncStatus.failed.rawValue
            let descriptor = FetchDescriptor<DefectEntry>(
                predicate: #Predicate { $0.syncStatusRaw == failedRaw }
            )
            if let failed = try? context.fetch(descriptor), !failed.isEmpty {
                for entry in failed {
                    entry.syncStatus = .pendingAI
                    entry.lastSyncError = nil
                }
                try? context.save()
            }
        }
        refreshPendingCount()
        triggerSyncIfNeeded()
    }

    func triggerSyncIfNeeded() {
        guard isOnline, !isProcessingQueue, modelContainer != nil else { return }
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            await self?.processPendingFIFO()
        }
    }

    func refreshPendingCount() {
        guard let container = modelContainer else { return }
        let context = container.mainContext
        let pendingRaw = SyncStatus.pendingAI.rawValue
        let failedRaw = SyncStatus.failed.rawValue
        let descriptor = FetchDescriptor<DefectEntry>(
            predicate: #Predicate { $0.syncStatusRaw == pendingRaw || $0.syncStatusRaw == failedRaw }
        )
        pendingCount = (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Entries left in `.syncing` when the app was killed/crashed mid-request would otherwise never be
    /// picked up again (the FIFO loop only fetches `.pendingAI`). Put them back in the queue on launch.
    private func recoverInterruptedEntries() {
        guard let container = modelContainer else { return }
        let context = container.mainContext
        let syncingRaw = SyncStatus.syncing.rawValue
        let descriptor = FetchDescriptor<DefectEntry>(
            predicate: #Predicate { $0.syncStatusRaw == syncingRaw }
        )
        guard let stuck = try? context.fetch(descriptor), !stuck.isEmpty else { return }
        for entry in stuck {
            entry.syncStatus = .pendingAI
        }
        try? context.save()
    }

    /// Weak basement/crawlspace signal often reports a "satisfied" path while requests still time out.
    /// Those failures are transient: keep the entry queued instead of marking it failed.
    private static func isTransientNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .internationalRoamingOff, .dataNotAllowed, .callIsActive:
            return true
        default:
            return false
        }
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = (path.status == .satisfied)
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = online
                if online && (wasOffline || self.pendingCount > 0) {
                    self.triggerSyncIfNeeded()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    private func processPendingFIFO() async {
        guard let container = modelContainer else { return }
        isProcessingQueue = true
        defer {
            isProcessingQueue = false
            refreshPendingCount()
        }

        let context = container.mainContext
        let pendingRaw = SyncStatus.pendingAI.rawValue

        while isOnline && !Task.isCancelled {
            let descriptor = FetchDescriptor<DefectEntry>(
                predicate: #Predicate { $0.syncStatusRaw == pendingRaw },
                sortBy: [SortDescriptor(\.createdAt, order: .forward)]
            )

            guard let nextEntry = try? context.fetch(descriptor).first else {
                break
            }

            nextEntry.syncStatus = .syncing
            nextEntry.lastSyncError = nil
            try? context.save()

            let photos = nextEntry.photos
            let audioData = nextEntry.audioMemoData
            let propertyType = nextEntry.project?.propertyType ?? .singleFamily
            let yearBuilt = nextEntry.project?.yearBuilt ?? 1995
            let hintNotes = nextEntry.observationNarrative.isEmpty ? nil : nextEntry.observationNarrative
            // Snapshot of the editable fields when the request starts. If the inspector edits a field
            // in DefectDetailEditView while the request is in flight, their edit wins over the AI text.
            let sentLocation = nextEntry.location
            let sentTitle = nextEntry.defectTitle
            let sentNarrative = nextEntry.observationNarrative
            let sentRecommendation = nextEntry.recommendation

            do {
                let result = try await GeminiInspectionService.shared.analyzeDefect(
                    photos: photos,
                    audioMemoData: audioData,
                    propertyType: propertyType,
                    yearBuilt: yearBuilt,
                    inspectorHintNotes: hintNotes
                )

                // The finding (or its whole inspection) may have been deleted while the request was in
                // flight; writing to a deleted SwiftData model crashes.
                guard !nextEntry.isDeleted, nextEntry.modelContext != nil else { continue }

                nextEntry.rawTranscript = result.rawTranscript
                if let parsedSystem = BuildingSystem(rawValue: result.buildingSystem) {
                    nextEntry.buildingSystem = parsedSystem
                }
                if let parsedSeverity = DefectSeverity(rawValue: result.severity) {
                    nextEntry.severity = parsedSeverity
                }
                if !result.location.isEmpty, nextEntry.location == sentLocation {
                    nextEntry.location = result.location
                }
                if !result.defectTitle.isEmpty, nextEntry.defectTitle == sentTitle {
                    nextEntry.defectTitle = result.defectTitle
                }
                if !result.observationNarrative.isEmpty, nextEntry.observationNarrative == sentNarrative {
                    nextEntry.observationNarrative = result.observationNarrative
                }
                if !result.recommendation.isEmpty, nextEntry.recommendation == sentRecommendation {
                    nextEntry.recommendation = result.recommendation
                }
                nextEntry.visualObservationsAdded = result.visualObservationsAdded
                nextEntry.syncStatus = .synced
                nextEntry.lastSyncError = nil
                try? context.save()
            } catch is CancellationError {
                guard !nextEntry.isDeleted, nextEntry.modelContext != nil else { break }
                nextEntry.syncStatus = .pendingAI
                try? context.save()
                break
            } catch {
                guard !nextEntry.isDeleted, nextEntry.modelContext != nil else { continue }
                // Keep queued if the connection dropped / timed out mid-request and stop draining the
                // queue (it resumes on the next path change or manual "Sync"); otherwise mark failed
                // for manual retry and move on to the next entry.
                if !isOnline || Self.isTransientNetworkError(error) {
                    nextEntry.syncStatus = .pendingAI
                    try? context.save()
                    break
                } else {
                    nextEntry.syncStatus = .failed
                    nextEntry.lastSyncError = error.localizedDescription
                    try? context.save()
                }
            }
        }
    }
}
