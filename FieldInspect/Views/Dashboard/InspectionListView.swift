import SwiftData
import SwiftUI

struct InspectionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(OfflineSyncQueue.self) private var syncQueue
    @Environment(StoreKitManager.self) private var storeKit

    @Query(sort: \InspectionProject.inspectionDate, order: .reverse)
    private var projects: [InspectionProject]

    @State private var showingNewInspection = false
    @State private var showingPaywall = false
    @State private var searchText = ""

    private var filteredProjects: [InspectionProject] {
        guard !searchText.isEmpty else { return projects }
        return projects.filter {
            $0.propertyAddress.localizedCaseInsensitiveContains(searchText) ||
            $0.clientName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var activeProjects: [InspectionProject] {
        filteredProjects.filter { !$0.isCompleted }
    }

    private var completedProjects: [InspectionProject] {
        filteredProjects.filter { $0.isCompleted }
    }

    var body: some View {
        NavigationStack {
            List {
                if !syncQueue.isOnline || syncQueue.pendingCount > 0 {
                    Section {
                        syncStatusBanner
                    }
                }

                if projects.isEmpty {
                    Section {
                        emptyStateView
                    }
                } else {
                    if !activeProjects.isEmpty {
                        Section("Active Inspections") {
                            ForEach(activeProjects) { project in
                                NavigationLink {
                                    PropertyWorkspaceView(project: project)
                                } label: {
                                    InspectionProjectRow(project: project)
                                }
                            }
                            .onDelete { offsets in
                                deleteProjects(activeProjects, at: offsets)
                            }
                        }
                    }

                    if !completedProjects.isEmpty {
                        Section("Completed Reports") {
                            ForEach(completedProjects) { project in
                                NavigationLink {
                                    PropertyWorkspaceView(project: project)
                                } label: {
                                    InspectionProjectRow(project: project)
                                }
                            }
                            .onDelete { offsets in
                                deleteProjects(completedProjects, at: offsets)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Search address or client")
            .navigationTitle(AppConfig.appName)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !storeKit.isProActive {
                        Button {
                            showingPaywall = true
                        } label: {
                            Label("Pro", systemImage: "crown.fill")
                                .font(.caption.bold())
                                .foregroundStyle(DesignSystem.Colors.brandAccent)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        startNewInspection()
                    } label: {
                        Label("New Inspection", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundStyle(DesignSystem.Colors.brandAccent)
                    }
                }
            }
            .sheet(isPresented: $showingNewInspection) {
                NewInspectionSheet()
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
        }
    }

    private var syncStatusBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: syncQueue.isOnline ? "arrow.triangle.2.circlepath.circle.fill" : "wifi.slash")
                .font(.title3)
                .foregroundStyle(syncQueue.isOnline ? DesignSystem.Colors.severityMonitor : DesignSystem.Colors.brandAccent)

            VStack(alignment: .leading, spacing: 2) {
                Text(syncQueue.isOnline ? "Syncing Offline Queue" : "Offline Mode (Basement / Crawlspace)")
                    .font(.subheadline.bold())
                Text(
                    syncQueue.pendingCount > 0
                    ? "\(syncQueue.pendingCount) finding(s) queued for Gemini AI synthesis."
                    : "Findings will be queued locally and processed automatically when online."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if syncQueue.isOnline && syncQueue.pendingCount > 0 {
                Button("Sync") {
                    syncQueue.retryAllAndSync()
                }
                .buttonStyle(.bordered)
                .tint(DesignSystem.Colors.brandAccent)
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            BrandLogoView()
                .frame(maxWidth: 210, maxHeight: 64)
            Text("No Property Inspections Yet")
                .font(.headline)
            Text("Tap + to start a new residential inspection. Snap defect photos, draw callouts, and dictate findings—even offline.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Start First Inspection") {
                startNewInspection()
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.brandAccent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// Single paywall gate for every "new inspection" entry point (toolbar + empty state).
    private func startNewInspection() {
        if storeKit.canExportOrCreateInspection(existingProjectCount: projects.count) {
            showingNewInspection = true
        } else {
            showingPaywall = true
        }
    }

    private func deleteProjects(_ list: [InspectionProject], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(list[index])
        }
        try? modelContext.save()
    }
}

private struct InspectionProjectRow: View {
    let project: InspectionProject

    var body: some View {
        HStack(spacing: 12) {
            if let data = project.coverPhotoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DesignSystem.Colors.brandPrimary.opacity(0.1))
                    Image(systemName: "house.fill")
                        .foregroundStyle(DesignSystem.Colors.brandPrimary)
                }
                .frame(width: 60, height: 60)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(project.propertyAddress.isEmpty ? "Untitled Property" : project.propertyAddress)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if !project.clientName.isEmpty {
                        Text(project.clientName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(project.inspectionDate, style: .date)
                        .font(DesignSystem.Typography.monospacedCaption())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    miniCountBadge(count: project.count(for: .safetyHazard), color: DesignSystem.Colors.severitySafetyHazard, label: "Safety")
                    miniCountBadge(count: project.count(for: .majorDefect), color: DesignSystem.Colors.severityMajorDefect, label: "Major")
                    miniCountBadge(count: project.count(for: .monitor), color: DesignSystem.Colors.severityMonitor, label: "Monitor")

                    if project.pendingAICount > 0 {
                        Text("\(project.pendingAICount) Queued")
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(DesignSystem.Colors.brandAccent)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func miniCountBadge(count: Int, color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(count) \(label)")
                .font(.caption2.bold().monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
