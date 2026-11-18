import PhotosUI
import SwiftData
import SwiftUI

struct DefectCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(OfflineSyncQueue.self) private var syncQueue

    let project: InspectionProject
    let initialSystem: BuildingSystem

    @State private var audioRecorder = AudioRecorderManager()

    @State private var selectedSystem: BuildingSystem
    @State private var selectedSeverity: DefectSeverity = .majorDefect
    @State private var quickLocation: String = ""
    @State private var quickNotes: String = ""

    // Up to 4 downsampled JPEG photos + per-photo callout strokes
    @State private var photoDatas: [Data] = []
    @State private var strokesByPhotoIndex: [Int: [CalloutStroke]] = [:]
    @State private var activePhotoIndex: Int = 0
    @State private var selectedTool: CalloutTool = .freehand

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var showingAIDisclosureAlert = false
    @AppStorage("hasAcceptedAIDataDisclosure") private var hasAcceptedAIDataDisclosure = false

    init(project: InspectionProject, initialSystem: BuildingSystem = .exterior) {
        self.project = project
        self.initialSystem = initialSystem
        _selectedSystem = State(initialValue: initialSystem)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    photoMarkupSection
                    voiceMemoSection
                    metadataSection
                }
                .padding(16)
            }
            .background(DesignSystem.Colors.surfacePrimary)
            .navigationTitle("Capture Finding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        audioRecorder.stopRecording()
                        audioRecorder.stopPlayback()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save Finding") {
                        if hasAcceptedAIDataDisclosure {
                            saveDefectEntry()
                        } else {
                            showingAIDisclosureAlert = true
                        }
                    }
                    .bold()
                    .disabled(photoDatas.isEmpty && !audioRecorder.hasRecordedMemo && quickNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: pickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    await loadPickedPhotos(newItems)
                    pickerItems = []
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraImagePicker { image in
                    if photoDatas.count < AppConfig.Media.maxPhotosPerDefect,
                       let processed = ImageProcessor.processUIImage(image) {
                        photoDatas.append(processed)
                        activePhotoIndex = photoDatas.count - 1
                    }
                }
            }
            .alert("Microphone Error", isPresented: Binding(
                get: { audioRecorder.errorMessage != nil },
                set: { if !$0 { audioRecorder.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(audioRecorder.errorMessage ?? "")
            }
            .alert("AI Processing & Privacy", isPresented: $showingAIDisclosureAlert) {
                Button("Agree & Save") {
                    hasAcceptedAIDataDisclosure = true
                    saveDefectEntry()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Attached inspection photos and voice memos are transmitted securely to FieldInspect's stateless AI proxy (Google Gemini API) solely to generate your InterNACHI defect narrative. Data is not retained by the proxy.")
            }
        }
    }

    // MARK: - Photo & Red Callout Canvas Section

    private var photoMarkupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Site Photos (\(photoDatas.count)/\(AppConfig.Media.maxPhotosPerDefect))", systemImage: "camera.viewfinder")
                    .font(.headline)
                Spacer()
                if !photoDatas.isEmpty {
                    Menu {
                        ForEach(CalloutTool.allCases) { tool in
                            Button {
                                selectedTool = tool
                            } label: {
                                Label(tool.rawValue, systemImage: tool.sfSymbol)
                            }
                        }
                    } label: {
                        Label(selectedTool.rawValue, systemImage: selectedTool.sfSymbol)
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(DesignSystem.Colors.severitySafetyHazard.opacity(0.12), in: Capsule())
                            .foregroundStyle(DesignSystem.Colors.severitySafetyHazard)
                    }
                }
            }

            if photoDatas.indices.contains(activePhotoIndex),
               let uiImage = UIImage(data: photoDatas[activePhotoIndex]) {
                AnnotationCanvasView(
                    image: uiImage,
                    tool: selectedTool,
                    strokes: Binding(
                        get: { strokesByPhotoIndex[activePhotoIndex] ?? [] },
                        set: { strokesByPhotoIndex[activePhotoIndex] = $0 }
                    )
                )
                .frame(height: 270)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DesignSystem.Colors.cardBorder, lineWidth: 1)
                )

                HStack {
                    Button {
                        var current = strokesByPhotoIndex[activePhotoIndex] ?? []
                        if !current.isEmpty {
                            current.removeLast()
                            strokesByPhotoIndex[activePhotoIndex] = current
                        }
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                    .disabled((strokesByPhotoIndex[activePhotoIndex] ?? []).isEmpty)

                    Button(role: .destructive) {
                        strokesByPhotoIndex[activePhotoIndex] = []
                    } label: {
                        Label("Clear Markup", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled((strokesByPhotoIndex[activePhotoIndex] ?? []).isEmpty)

                    Spacer()

                    Button(role: .destructive) {
                        removeActivePhoto()
                    } label: {
                        Label("Remove", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
                .font(.caption.bold())
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(DesignSystem.Colors.surfaceSecondary)
                        .frame(height: 170)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                                .foregroundStyle(.secondary.opacity(0.4))
                        )
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus")
                            .font(.largeTitle)
                            .foregroundStyle(DesignSystem.Colors.brandAccent)
                        Text("Snap or select up to 4 defect photos, then draw red callouts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
            }

            // Thumbnail strip + Add buttons
            HStack(spacing: 10) {
                ForEach(Array(photoDatas.enumerated()), id: \.offset) { index, data in
                    if let thumb = UIImage(data: data) {
                        Button {
                            activePhotoIndex = index
                        } label: {
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(
                                            activePhotoIndex == index ? DesignSystem.Colors.brandAccent : .clear,
                                            lineWidth: 2.5
                                        )
                                )
                        }
                    }
                }

                Spacer()

                if photoDatas.count < AppConfig.Media.maxPhotosPerDefect {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Camera", systemImage: "camera.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.brandPrimary)
                    }

                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: AppConfig.Media.maxPhotosPerDefect - photoDatas.count,
                        matching: .images
                    ) {
                        Label("Library", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .background(DesignSystem.Colors.surfaceSecondary, in: RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius))
    }

    // MARK: - Hold-to-Record Voice Memo Section

    private var voiceMemoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Inspector Voice Memo", systemImage: "mic.fill")
                    .font(.headline)
                Spacer()
                if audioRecorder.hasRecordedMemo {
                    Label("Memo Ready", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(DesignSystem.Colors.severitySatisfactory)
                }
            }

            // Hold-to-Record Button
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(audioRecorder.isRecording ? DesignSystem.Colors.severitySafetyHazard : DesignSystem.Colors.brandPrimary)
                    .frame(height: 64)

                HStack(spacing: 10) {
                    Image(systemName: audioRecorder.isRecording ? "waveform" : "mic.fill")
                        .font(.title3.bold())
                        .symbolEffect(.pulse, isActive: audioRecorder.isRecording)
                    Text(audioRecorder.isRecording ? "Recording… Release to Stop" : "Hold to Dictate Defect Finding")
                        .font(.headline)
                }
                .foregroundStyle(.white)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        // Idempotent: only the first touch event of a hold starts a recording.
                        audioRecorder.beginHoldToRecord()
                    }
                    .onEnded { _ in
                        // Always end the hold, even if recording hasn't started yet (e.g. permission prompt).
                        audioRecorder.endHoldToRecord()
                    }
            )

            if audioRecorder.hasRecordedMemo {
                HStack(spacing: 12) {
                    Button {
                        audioRecorder.togglePlayback()
                    } label: {
                        Label(
                            audioRecorder.isPlaying ? "Stop" : "Play Memo",
                            systemImage: audioRecorder.isPlaying ? "stop.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        audioRecorder.clearMemo()
                    } label: {
                        Label("Re-record", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
                .font(.caption.bold())
            }
        }
        .padding(14)
        .background(DesignSystem.Colors.surfaceSecondary, in: RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius))
    }

    // MARK: - Metadata & Fallback Notes

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("System & Quick Context", systemImage: "slider.horizontal.3")
                .font(.headline)

            Picker("Building System", selection: $selectedSystem) {
                ForEach(BuildingSystem.allCases) { system in
                    Label(system.displayName, systemImage: system.sfSymbol).tag(system)
                }
            }
            .pickerStyle(.menu)

            Picker("Initial Severity", selection: $selectedSeverity) {
                ForEach(DefectSeverity.allCases) { tier in
                    Text(tier.displayName).tag(tier)
                }
            }
            .pickerStyle(.segmented)

            TextField("Location (optional, e.g. Basement — Main Panel)", text: $quickLocation)
                .textFieldStyle(.roundedBorder)

            TextField("Optional text note (if unable to speak)", text: $quickNotes, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Image(systemName: syncQueue.isOnline ? "sparkles" : "wifi.slash")
                    .foregroundStyle(syncQueue.isOnline ? DesignSystem.Colors.severityMonitor : DesignSystem.Colors.brandAccent)
                Text(
                    syncQueue.isOnline
                    ? "Online: Gemini AI will synthesize photos + voice memo upon save."
                    : "Offline: Finding will be saved locally with 'Queued for AI (Offline)'."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(DesignSystem.Colors.surfaceSecondary, in: RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius))
    }

    // MARK: - Actions

    private func loadPickedPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard photoDatas.count < AppConfig.Media.maxPhotosPerDefect else { break }
            if let raw = try? await item.loadTransferable(type: Data.self),
               let processed = ImageProcessor.downsampleAndCompress(data: raw) {
                photoDatas.append(processed)
                activePhotoIndex = photoDatas.count - 1
            }
        }
    }

    private func removeActivePhoto() {
        guard photoDatas.indices.contains(activePhotoIndex) else { return }
        photoDatas.remove(at: activePhotoIndex)
        var reindexed: [Int: [CalloutStroke]] = [:]
        for (key, value) in strokesByPhotoIndex {
            if key < activePhotoIndex {
                reindexed[key] = value
            } else if key > activePhotoIndex {
                reindexed[key - 1] = value
            }
        }
        strokesByPhotoIndex = reindexed
        activePhotoIndex = max(0, min(activePhotoIndex, photoDatas.count - 1))
    }

    private func saveDefectEntry() {
        audioRecorder.stopRecording()
        audioRecorder.stopPlayback()

        let bakedPhotos: [Data] = photoDatas.enumerated().map { index, data in
            let strokes = strokesByPhotoIndex[index] ?? []
            return ImageProcessor.bakeAnnotations(onto: data, strokes: strokes)
        }

        let trimmedNotes = quickNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = DefectEntry(
            buildingSystem: selectedSystem,
            severity: selectedSeverity,
            syncStatus: .pendingAI,
            location: quickLocation.trimmingCharacters(in: .whitespacesAndNewlines),
            defectTitle: trimmedNotes.isEmpty ? "\(selectedSystem.shortName) Finding" : String(trimmedNotes.prefix(48)),
            observationNarrative: trimmedNotes,
            recommendation: "",
            photos: bakedPhotos,
            audioMemoData: audioRecorder.recordedAudioData,
            project: project
        )

        modelContext.insert(entry)
        try? modelContext.save()
        syncQueue.enqueueAndProcessIfOnline(entry)
        dismiss()
    }
}

/// Interactive SwiftUI Canvas overlay for drawing red circles/freehand strokes and arrows on a defect photo.
private struct AnnotationCanvasView: View {
    let image: UIImage
    let tool: CalloutTool
    @Binding var strokes: [CalloutStroke]

    @State private var activeStroke: CalloutStroke?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)

                Canvas { context, size in
                    // Strokes are normalized to the *visible image* rect (not the letterboxed canvas),
                    // so the preview matches the annotations baked onto the JPEG exactly.
                    let imageRect = ImageProcessor.aspectFitRect(imageSize: image.size, in: size)
                    func denormalize(_ p: CGPoint) -> CGPoint {
                        CGPoint(x: imageRect.minX + p.x * imageRect.width, y: imageRect.minY + p.y * imageRect.height)
                    }
                    let allStrokes = strokes + (activeStroke.map { [$0] } ?? [])
                    for stroke in allStrokes where stroke.points.count >= 2 {
                        switch stroke.tool {
                        case .freehand:
                            var path = Path()
                            let pts = stroke.points.map(denormalize)
                            path.move(to: pts[0])
                            for pt in pts.dropFirst() {
                                path.addLine(to: pt)
                            }
                            context.stroke(
                                path,
                                with: .color(Color(red: 0.92, green: 0.12, blue: 0.12)),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                            )

                        case .arrow:
                            guard let first = stroke.points.first, let last = stroke.points.last else { continue }
                            let start = denormalize(first)
                            let end = denormalize(last)
                            var linePath = Path()
                            linePath.move(to: start)
                            linePath.addLine(to: end)
                            context.stroke(
                                linePath,
                                with: .color(Color(red: 0.92, green: 0.12, blue: 0.12)),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                            )

                            let angle = atan2(end.y - start.y, end.x - start.x)
                            let headLength: CGFloat = 18
                            let headAngle: CGFloat = .pi / 6
                            var headPath = Path()
                            headPath.move(to: end)
                            headPath.addLine(to: CGPoint(
                                x: end.x - headLength * cos(angle - headAngle),
                                y: end.y - headLength * sin(angle - headAngle)
                            ))
                            headPath.addLine(to: CGPoint(
                                x: end.x - headLength * cos(angle + headAngle),
                                y: end.y - headLength * sin(angle + headAngle)
                            ))
                            headPath.closeSubpath()
                            context.fill(headPath, with: .color(Color(red: 0.92, green: 0.12, blue: 0.12)))
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let imageRect = ImageProcessor.aspectFitRect(imageSize: image.size, in: geo.size)
                            let nx = max(0, min(1, (value.location.x - imageRect.minX) / max(1, imageRect.width)))
                            let ny = max(0, min(1, (value.location.y - imageRect.minY) / max(1, imageRect.height)))
                            let pt = CGPoint(x: nx, y: ny)

                            if activeStroke == nil {
                                activeStroke = CalloutStroke(tool: tool, points: [pt])
                            } else if tool == .arrow {
                                if activeStroke?.points.count == 1 {
                                    activeStroke?.points.append(pt)
                                } else {
                                    activeStroke?.points[1] = pt
                                }
                            } else {
                                activeStroke?.points.append(pt)
                            }
                        }
                        .onEnded { _ in
                            if let finished = activeStroke, finished.points.count >= 2 {
                                strokes.append(finished)
                            }
                            activeStroke = nil
                        }
                )
            }
        }
        .background(Color.black)
    }
}
