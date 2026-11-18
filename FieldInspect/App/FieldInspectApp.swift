import SwiftData
import SwiftUI

@main
struct FieldInspectApp: App {
    @State private var syncQueue = OfflineSyncQueue()
    @State private var storeKit = StoreKitManager()
    @State private var showSplash = true
    @Environment(\.scenePhase) private var scenePhase

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
            // Format dates/numbers in the app's UI language (en / zh-Hans / zh-Hant / es) with the user's
            // region, so an unsupported device language (e.g. French) doesn't mix French dates into English UI.
            .environment(\.locale, AppLocale.locale)
            .task {
                syncQueue.configure(modelContainer: modelContainer)
                // When the app is only hosting unit tests, leave StoreKit to the tests' SKTestSession:
                // touching StoreKit before the session exists binds purchases to the Sandbox account.
                if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                    storeKit.start()
                }
                try? await Task.sleep(for: .seconds(3.0))
                withAnimation(.easeOut(duration: 0.35)) {
                    showSplash = false
                }
            }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, phase in
            // Re-check the subscription whenever the app comes back to the foreground so an expired
            // or refunded subscription stops unlocking Pro without needing a cold launch.
            if phase == .active {
                Task { await storeKit.refreshEntitlements() }
            }
        }
    }
}
