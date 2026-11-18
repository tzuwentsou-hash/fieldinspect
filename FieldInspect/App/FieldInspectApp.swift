import SwiftData
import SwiftUI

@main
struct FieldInspectApp: App {
    @State private var syncQueue = OfflineSyncQueue()
    @State private var storeKit = StoreKitManager()
    @State private var showSplash = true

    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            InspectionProject.self,
            DefectEntry.self
        ])

        let shouldUseCloudKit = AppConfig.isCloudKitProvisioned &&
            FileManager.default.ubiquityIdentityToken != nil

        do {
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: shouldUseCloudKit
                    ? .private(AppConfig.cloudKitContainerIdentifier)
                    : .none
            )
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not initialize SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                InspectionListView()
                    .environment(syncQueue)
                    .environment(storeKit)

                if showSplash {
                    SplashScreenView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task {
                syncQueue.configure(modelContainer: modelContainer)
                storeKit.start()
                try? await Task.sleep(for: .seconds(3.0))
                withAnimation(.easeOut(duration: 0.35)) {
                    showSplash = false
                }
            }
        }
        .modelContainer(modelContainer)
    }
}
