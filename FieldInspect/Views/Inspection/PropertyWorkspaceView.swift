import SwiftData
import SwiftUI

struct PropertyWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(OfflineSyncQueue.self) private var syncQueue

    @Bindable var project: InspectionProject

    @State private var selectedSystemFilter: BuildingSystem?
    @State private var captureInitialSystem: BuildingSystem = .roof
    @State private var showingCaptureSheet = false
    @State private var showingReportPreview = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                executiveSummaryHeader
                if !syncQueue.isOnline || project.pendingAICount > 0 {
                    offlineBanner
                }
                buildingSystemsGrid
                findingsListSection
            }
            .padding(16)
        }
        .background(DesignSystem.Colors.surfacePrimary)
        .navigationTitle(project.propertyAddress.isEmpty ? "Inspection" : project.propertyAddress)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingReportPreview = true
                } label: {
                    Label("PDF", systemImage: "doc.richtext.fill")
                }

                Menu {
                    Button {
                        project.isCompleted.toggle()
                        try? modelContext.save()
                    } label: {
                        Label(
                            project.isCompleted ? "Reopen Inspection" : "Mark Completed",
                            systemImage: project.isCompleted ? "arrow.uturn.left.circle" : "checkmark.circle"
                        )
                    }

                    if project.pendingAICount > 0 && syncQueue.isOnline {
                        Button {
                            syncQueue.retryAllAndSync()
                        } label: {
                            Label("Sync Pending AI (\(project.pendingAICount))", systemImage: "sparkles")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            captureActionBar
        }
        .sheet(isPresented: $showingCaptureSheet) {
            DefectCaptureSheet(
                project: project,
                initialSystem: selectedSystemFilter ?? captureInitialSystem
            )
        }
        .sheet(isPresented: $showingReportPreview) {
            ReportPreviewView(project: project)
        }
    }

    // MARK: - Executive Summary Counter

    private var executiveSummaryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.clientName.isEmpty ? "Residential Inspection" : "Client: \(project.clientName)")
                        .font(.subheadline.bold())
                    Text("\(project.propertyType.rawValue) • Built \(project.yearBuilt) • \(project.weatherConditions)")
                        .font(DesignSystem.Typography.monospacedCaption())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if project.isCompleted {
                    Text("COMPLETED")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(DesignSystem.Colors.severitySatisfactory, in: Capsule())
                }
            }

            HStack(spacing: 8) {
                summaryCounterTile(severity: .safetyHazard, count: project.count(for: .safetyHazard))
                summaryCounterTile(severity: .majorDefect, count: project.count(for: .majorDefect))
                summaryCounterTile(severity: .monitor, count: project.count(for: .monitor))
                summaryCounterTile(severity: .satisfactory, count: project.count(for: .satisfactory))
            }
        }
        .padding(14)
        .background(DesignSystem.Colors.surfaceSecondary, in: RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius))
    }

    private func summaryCounterTile(severity: DefectSeverity, count: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(DesignSystem.Typography.monospacedTitle())
                .foregroundStyle(severity.color)
            Text(severity.shortLabel)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(severity.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Offline Banner

    private var offlineBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: syncQueue.isOnline ? "sparkles" : "wifi.slash")
                .foregroundStyle(DesignSystem.Colors.brandAccent)
            Text(
                syncQueue.isOnline
                ? "\(project.pendingAICount) finding(s) queued for AI synthesis."
                : "Offline (Basement / Crawlspace): Captures save locally and auto-sync later."
            )
            .font(.caption)
            .foregroundStyle(.primary)
            Spacer()
        }
        .padding(12)
        .background(DesignSystem.Colors.brandAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 8 InterNACHI Building Systems Grid

    private var buildingSystemsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Building Systems (InterNACHI)")
                    .font(.headline)
                Spacer()
                if selectedSystemFilter != nil {
                    Button("Show All") {
                        selectedSystemFilter = nil
                    }
                    .font(.caption.bold())
                    .foregroundStyle(DesignSystem.Colors.brandAccent)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(BuildingSystem.allCases) { system in
                    let entries = project.defects(in: system)
                    let isSelected = selectedSystemFilter == system
                    Button {
                        selectedSystemFilter = isSelected ? nil : system
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: system.sfSymbol)
                                .font(.title3)
                                .foregroundStyle(isSelected ? .white : DesignSystem.Colors.brandAccent)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(system.shortName)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(isSelected ? .white : .primary)
                                    .lineLimit(1)
                                Text("\(entries.count) finding\(entries.count == 1 ? "" : "s")")
                                    .font(DesignSystem.Typography.monospacedCaption())
                                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(
                            isSelected ? DesignSystem.Colors.brandPrimary : DesignSystem.Colors.surfaceSecondary,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected ? DesignSystem.Colors.brandAccent : DesignSystem.Colors.cardBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Findings List

    private var findingsListSection: some View {
        let displayedSystems: [BuildingSystem] = selectedSystemFilter.map { [$0] } ?? BuildingSystem.allCases

        return VStack(alignment: .leading, spacing: 12) {
            Text(selectedSystemFilter?.displayName ?? "All Recorded Findings")
                .font(.headline)

            let hasAny = displayedSystems.contains { !project.defects(in: $0).isEmpty }
            if !hasAny {
                VStack(spacing: 10) {
                    Image(systemName: "camera.viewfinder")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No findings recorded yet.")
                        .font(.subheadline.bold())
                    Text("Tap \"Capture Defect\" below to snap photos, draw red callouts, and dictate a voice memo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(DesignSystem.Colors.surfaceSecondary, in: RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius))
            } else {
                ForEach(displayedSystems) { system in
                    let entries = project.defects(in: system)
                    if !entries.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(system.displayName, systemImage: system.sfSymbol)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(DesignSystem.Colors.brandPrimary)
                                Spacer()
                                Text("\(entries.count)")
                                    .font(DesignSystem.Typography.monospacedCaption())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 4)

                            ForEach(entries) { entry in
                                NavigationLink {
                                    DefectDetailEditView(defect: entry)
                                } label: {
                                    DefectEntryCard(entry: entry)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        modelContext.delete(entry)
                                        try? modelContext.save()
                                    } label: {
                                        Label("Delete Finding", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Bottom Action Bar

    private var captureActionBar: some View {
        HStack(spacing: 12) {
            Button {
                captureInitialSystem = selectedSystemFilter ?? .roof
                showingCaptureSheet = true
            } label: {
                Label("Capture Defect", systemImage: "camera.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(DesignSystem.Colors.brandAccent, in: RoundedRectangle(cornerRadius: 12))
            }

            Button {
                showingReportPreview = true
            } label: {
                Label("Report", systemImage: "doc.richtext.fill")
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(DesignSystem.Colors.brandPrimary, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

private struct DefectEntryCard: View {
    let entry: DefectEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let firstPhoto = entry.photos.first, let uiImage = UIImage(data: firstPhoto) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 68, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(entry.severity.color.opacity(0.12))
                    Image(systemName: entry.severity.sfSymbol)
                        .foregroundStyle(entry.severity.color)
                }
                .frame(width: 68, height: 68)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    SeverityBadge(severity: entry.severity, compact: true)
                    SyncStatusBadge(status: entry.syncStatus)
                    Spacer()
                }

                Text(entry.defectTitle.isEmpty ? "Untitled Finding" : entry.defectTitle)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !entry.location.isEmpty {
                    Text(entry.location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !entry.observationNarrative.isEmpty {
                    Text(entry.observationNarrative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(12)
        .background(DesignSystem.Colors.surfaceSecondary, in: RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius)
                .stroke(DesignSystem.Colors.cardBorder, lineWidth: 1)
        )
    }
}
