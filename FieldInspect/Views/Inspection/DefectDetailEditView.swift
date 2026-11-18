import SwiftData
import SwiftUI

struct DefectDetailEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(OfflineSyncQueue.self) private var syncQueue

    @Bindable var defect: DefectEntry
    @State private var audioPlayer = AudioRecorderManager()

    var body: some View {
        Form {
            Section {
                HStack {
                    SeverityBadge(severity: defect.severity)
                    Spacer()
                    SyncStatusBadge(status: defect.syncStatus)
                }

                if let error = defect.lastSyncError, defect.syncStatus == .failed {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(DesignSystem.Colors.severitySafetyHazard)
                        Button("Retry AI Synthesis") {
                            syncQueue.retryEntry(defect)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.brandAccent)
                    }
                } else if defect.syncStatus == .pendingAI {
                    HStack {
                        Text("Waiting for connectivity or queue turn.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if syncQueue.isOnline {
                            Button("Analyze Now") {
                                syncQueue.retryEntry(defect)
                            }
                            .font(.caption.bold())
                        }
                    }
                }
            }

            if !defect.photos.isEmpty {
                Section("Site Photos (\(defect.photos.count))") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(defect.photos.enumerated()), id: \.offset) { _, data in
                                if let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 220, height: 165)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Classification") {
                Picker("Building System", selection: Binding(
                    get: { defect.buildingSystem },
                    set: { defect.buildingSystem = $0 }
                )) {
                    ForEach(BuildingSystem.allCases) { system in
                        Label(system.displayName, systemImage: system.sfSymbol).tag(system)
                    }
                }

                Picker("Severity", selection: Binding(
                    get: { defect.severity },
                    set: { defect.severity = $0 }
                )) {
                    ForEach(DefectSeverity.allCases) { tier in
                        Text(tier.displayName).tag(tier)
                    }
                }

                TextField("Location (e.g. Basement — Main Panel)", text: $defect.location)
                TextField("Defect Headline", text: $defect.defectTitle)
            }

            Section("Observation Narrative") {
                TextEditor(text: $defect.observationNarrative)
                    .frame(minHeight: 110)
            }

            Section("Recommendation (InterNACHI)") {
                TextEditor(text: $defect.recommendation)
                    .frame(minHeight: 90)
            }

            if let visualNote = defect.visualObservationsAdded, !visualNote.isEmpty {
                Section("AI Visual Cross-Verification") {
                    Text(visualNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if defect.audioMemoData != nil || !defect.rawTranscript.isEmpty {
                Section("Voice Memo & Transcript") {
                    if let audioData = defect.audioMemoData {
                        Button {
                            audioPlayer.togglePlayback(data: audioData)
                        } label: {
                            Label(
                                audioPlayer.isPlaying ? "Stop Voice Memo" : "Play Voice Memo",
                                systemImage: audioPlayer.isPlaying ? "stop.circle.fill" : "play.circle.fill"
                            )
                            .foregroundStyle(DesignSystem.Colors.brandAccent)
                        }
                    }

                    if !defect.rawTranscript.isEmpty {
                        Text(defect.rawTranscript)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Edit Finding")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    try? modelContext.save()
                    dismiss()
                }
                .bold()
            }
        }
        .onDisappear {
            audioPlayer.stopPlayback()
            try? modelContext.save()
        }
    }
}
