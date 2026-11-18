import Foundation
import Observation
import StoreKit

@Observable
@MainActor
final class StoreKitManager {
    private(set) var products: [Product] = []
    private(set) var isProActive: Bool = false
    /// True while a purchase or restore is in flight (drives the paywall CTA spinner).
    private(set) var isLoading: Bool = false
    /// Separate from `isLoading` so a background product fetch can't flip the purchase spinner off mid-purchase.
    private(set) var isLoadingProducts: Bool = false
    var errorMessage: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.lifetimeInspectionsCreated = defaults.integer(forKey: Self.lifetimeCreatedKey)
    }

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

    /// Real savings of the annual plan vs. 12 × monthly in the user's storefront currency,
    /// e.g. 42 for "Save 42%". Nil until both products are loaded.
    var annualSavingsPercent: Int? {
        guard let monthly = monthlyProduct, let annual = annualProduct else { return nil }
        let yearlyAtMonthlyPrice = monthly.price * 12
        guard yearlyAtMonthlyPrice > 0 else { return nil }
        let ratio = NSDecimalNumber(decimal: annual.price / yearlyAtMonthlyPrice).doubleValue
        let percent = Int(((1 - ratio) * 100).rounded())
        return percent > 0 ? percent : nil
    }

    /// Lifetime count of inspections created on this device. Counting only the *current* projects let
    /// free users bypass the 2-inspection trial by deleting old inspections.
    private static let lifetimeCreatedKey = "lifetimeInspectionsCreated"
    private(set) var lifetimeInspectionsCreated: Int

    func recordInspectionCreated() {
        lifetimeInspectionsCreated += 1
        defaults.set(lifetimeInspectionsCreated, forKey: Self.lifetimeCreatedKey)
    }

    func canExportOrCreateInspection(existingProjectCount: Int) -> Bool {
        if isProActive { return true }
        let used = max(existingProjectCount, lifetimeInspectionsCreated)
        return used < AppConfig.StoreKit.freeInspectionLimit
    }

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let ids = [
                AppConfig.StoreKit.monthlyProductID,
                AppConfig.StoreKit.annualProductID
            ]
            products = try await Product.products(for: ids)
                .sorted { $0.price < $1.price }
            if products.isEmpty {
                errorMessage = String(localized: "Subscription options are unavailable right now. Please try again later.")
            }
        } catch {
            errorMessage = String(localized: "Unable to load subscription options: \(error.localizedDescription)")
        }
    }

    enum PurchaseOutcome: Equatable {
        case purchased
        case pending
        case cancelled
        case failed
    }

    @discardableResult
    func purchase(_ product: Product) async -> PurchaseOutcome {
        guard !isLoading else { return .failed } // ignore double taps while a purchase sheet is up
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
                return .purchased
            case .pending:
                // Ask to Buy / SCA: the purchase completes later and arrives through Transaction.updates.
                errorMessage = String(localized: "Your purchase is pending approval. FieldInspect Pro will unlock automatically once it's approved.")
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed
            }
        } catch {
            errorMessage = String(localized: "Purchase failed: \(error.localizedDescription)")
            return .failed
        }
    }

    func restorePurchases() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isProActive {
                errorMessage = String(localized: "No active FieldInspect Pro subscription was found for this Apple ID.")
            }
        } catch {
            errorMessage = String(localized: "Restore failed: \(error.localizedDescription)")
        }
    }

    /// Recomputes Pro access from the current entitlements. Call on launch and whenever the app returns
    /// to the foreground: an expiry or a refund while the app sits in the background doesn't always arrive
    /// through `Transaction.updates`, so without this a lapsed subscriber kept Pro until the next cold launch.
    func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil,
                  transaction.productID == AppConfig.StoreKit.monthlyProductID ||
                  transaction.productID == AppConfig.StoreKit.annualProductID
            else { continue }
            if let expiration = transaction.expirationDate, expiration < Date() {
                continue
            }
            active = true
        }
        isProActive = active
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                // Refresh for unverified/revoked updates too, so access is removed when it should be.
                await self?.refreshEntitlements()
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
