import PhotosUI
import SwiftData
import SwiftUI

struct NewInspectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreKitManager.self) private var storeKit

    @State private var propertyAddress = ""
    @State private var clientName = ""
    @State private var propertyType: PropertyType = .singleFamily
    @State private var yearBuilt: Int = 1995
    @State private var weatherConditions = WeatherCondition.clear.rawValue
    @State private var ambientTemperature = WeatherCondition.defaultAmbientTemperature

    @AppStorage("inspectorName") private var savedInspectorName = ""
    @AppStorage("companyName") private var savedCompanyName = ""
    @AppStorage("licenseNumber") private var savedLicenseNumber = ""

    @State private var inspectorName = ""
    @State private var companyName = ""
    @State private var licenseNumber = ""

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var coverPhotoData: Data?
    @State private var showingCamera = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Property Details") {
                    TextField("Property Address (e.g. 742 Evergreen Ter)", text: $propertyAddress)
                        .textContentType(.fullStreetAddress)
                    TextField("Client Name", text: $clientName)
                        .textContentType(.name)
                    Picker("Property Type", selection: $propertyType) {
                        ForEach(PropertyType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    Stepper(value: $yearBuilt, in: 1850...2030) {
                        HStack {
                            Text("Year Built")
                            Spacer()
                            // Verbatim: a localized Int would render the year as "1,995".
                            Text(verbatim: String(yearBuilt))
                                .font(DesignSystem.Typography.monospacedHeadline())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Site Conditions") {
                    Picker("Weather", selection: $weatherConditions) {
                        ForEach(WeatherCondition.allCases) { option in
                            Text(option.displayName).tag(option.rawValue)
                        }
                    }
                    TextField("Ambient Temperature (e.g. 68°F)", text: $ambientTemperature)
                }

                Section("Cover Photo") {
                    if let coverPhotoData, let uiImage = UIImage(data: coverPhotoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 170)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    HStack(spacing: 12) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button {
                                showingCamera = true
                            } label: {
                                Label("Take Photo", systemImage: "camera.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }

                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label("Choose Photo", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Section("Inspector Credentials") {
                    TextField("Inspector Name", text: $inspectorName)
                    TextField("Inspection Company", text: $companyName)
                    TextField("State / Provincial License #", text: $licenseNumber)
                        .font(DesignSystem.Typography.monospacedCaption())
                }
            }
            .navigationTitle("New Inspection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        createProject()
                    }
                    .bold()
                    .disabled(propertyAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                inspectorName = savedInspectorName
                companyName = savedCompanyName
                licenseNumber = savedLicenseNumber
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let rawData = try? await newItem.loadTransferable(type: Data.self),
                       let processed = ImageProcessor.downsampleAndCompress(data: rawData) {
                        coverPhotoData = processed
                    }
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraImagePicker { image in
                    if let processed = ImageProcessor.processUIImage(image) {
                        coverPhotoData = processed
                    }
                }
            }
        }
    }

    private func createProject() {
        savedInspectorName = inspectorName
        savedCompanyName = companyName
        savedLicenseNumber = licenseNumber

        let project = InspectionProject(
            propertyAddress: propertyAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            clientName: clientName.trimmingCharacters(in: .whitespacesAndNewlines),
            propertyType: propertyType,
            yearBuilt: yearBuilt,
            weatherConditions: weatherConditions,
            ambientTemperature: ambientTemperature,
            inspectionDate: Date(),
            isCompleted: false,
            inspectorName: inspectorName,
            companyName: companyName,
            licenseNumber: licenseNumber,
            coverPhotoData: coverPhotoData
        )
        modelContext.insert(project)
        try? modelContext.save()
        storeKit.recordInspectionCreated()
        dismiss()
    }
}

/// Reusable UIKit camera sheet wrapper.
struct CameraImagePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImageCaptured: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss, onImageCaptured: onImageCaptured)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let dismiss: DismissAction
        let onImageCaptured: (UIImage) -> Void

        init(dismiss: DismissAction, onImageCaptured: @escaping (UIImage) -> Void) {
            self.dismiss = dismiss
            self.onImageCaptured = onImageCaptured
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImageCaptured(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
