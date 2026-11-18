import Foundation
import Observation
import StoreKit

@Observable
@MainActor
final class StoreKitManager {
    private(set) var products: [Product] = []
    private(set) var isProActive: Bool = false
    private(set) var isLoading: Bool = false
    var errorMessage: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false

    init() {}

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        updatesTask = listenForTransactions()
        Task {
            await refreshEntitlements()
            await loadProducts()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    var monthlyProduct: Product? {
        products.first { $0.id == AppConfig.StoreKit.monthlyProductID }
    }

    var annualProduct: Product? {
        products.first { $0.id == AppConfig.StoreKit.annualProductID }
    }

    /// Lifetime count of inspections created on this device. Counting only the *current* projects let
    /// free users bypass the 2-inspection trial by deleting old inspections.
    private static let lifetimeCreatedKey = "lifetimeInspectionsCreated"
    private(set) var lifetimeInspectionsCreated: Int = UserDefaults.standard.integer(forKey: StoreKitManager.lifetimeCreatedKey)

    func recordInspectionCreated() {
        lifetimeInspectionsCreated += 1
        UserDefaults.standard.set(lifetimeInspectionsCreated, forKey: Self.lifetimeCreatedKey)
    }

    func canExportOrCreateInspection(existingProjectCount: Int) -> Bool {
        if isProActive { return true }
        let used = max(existingProjectCount, lifetimeInspectionsCreated)
        return used < AppConfig.StoreKit.freeInspectionLimit
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let ids = [
                AppConfig.StoreKit.monthlyProductID,
                AppConfig.StoreKit.annualProductID
            ]
            products = try await Product.products(for: ids)
                .sorted { $0.price < $1.price }
        } catch {
            errorMessage = "Unable to load subscription options: \(error.localizedDescription)"
        }
    }

    func purchase(_ product: Product) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
            return false
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.revocationDate == nil,
               (transaction.productID == AppConfig.StoreKit.monthlyProductID ||
                transaction.productID == AppConfig.StoreKit.annualProductID) {
                active = true
            }
        }
        isProActive = active
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}
