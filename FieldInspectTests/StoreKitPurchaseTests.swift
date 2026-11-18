import StoreKit
import StoreKitTest
import XCTest
@testable import FieldInspect

/// End-to-end subscription tests against the local FieldInspect.storekit configuration (no App Store needed).
@MainActor
final class StoreKitPurchaseTests: XCTestCase {
    private var session: SKTestSession!
    private var defaults: UserDefaults!
    private let suiteName = "StoreKitPurchaseTests"

    override func setUp() async throws {
        // The simulator can read the host file system, so load the shared .storekit file from the repo.
        let storeKitURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FieldInspect.storekit")
        session = try SKTestSession(contentsOf: storeKitURL)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.askToBuyEnabled = false

        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        session = nil
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    func testProductsLoadWithLocalizedPricesAndRealSavings() async throws {
        let manager = StoreKitManager(defaults: defaults)
        await manager.loadProducts()

        let monthly = try XCTUnwrap(manager.monthlyProduct)
        let annual = try XCTUnwrap(manager.annualProduct)
        XCTAssertEqual(monthly.price, Decimal(string: "49.99"))
        XCTAssertEqual(annual.price, Decimal(string: "349.99"))
        // 349.99 / (49.99 * 12) ≈ 0.5834 -> 42% savings
        XCTAssertEqual(manager.annualSavingsPercent, 42)
        XCTAssertNil(manager.errorMessage)
    }

    func testFreeTrialAllowsTwoInspectionsThenRequiresPro() {
        let manager = StoreKitManager(defaults: defaults)
        XCTAssertTrue(manager.canExportOrCreateInspection(existingProjectCount: 0))
        manager.recordInspectionCreated()
        XCTAssertTrue(manager.canExportOrCreateInspection(existingProjectCount: 1))
        manager.recordInspectionCreated()
        XCTAssertFalse(manager.canExportOrCreateInspection(existingProjectCount: 2))
        // Deleting inspections must not give the trial back.
        XCTAssertFalse(manager.canExportOrCreateInspection(existingProjectCount: 0))

        // Counter survives relaunch.
        let relaunched = StoreKitManager(defaults: defaults)
        XCTAssertEqual(relaunched.lifetimeInspectionsCreated, 2)
        XCTAssertFalse(relaunched.canExportOrCreateInspection(existingProjectCount: 0))
    }

    func testMonthlyPurchaseUnlocksProAndBypassesTrialLimit() async throws {
        let manager = StoreKitManager(defaults: defaults)
        manager.recordInspectionCreated()
        manager.recordInspectionCreated()
        XCTAssertFalse(manager.canExportOrCreateInspection(existingProjectCount: 2))

        await manager.loadProducts()
        let monthly = try XCTUnwrap(manager.monthlyProduct)
        let outcome = await manager.purchase(monthly)

        XCTAssertEqual(outcome, .purchased)
        XCTAssertTrue(manager.isProActive)
        XCTAssertTrue(manager.canExportOrCreateInspection(existingProjectCount: 2))
        XCTAssertFalse(manager.isLoading)
    }

    func testAnnualPurchaseUnlocksPro() async throws {
        let manager = StoreKitManager(defaults: defaults)
        await manager.loadProducts()
        let annual = try XCTUnwrap(manager.annualProduct)
        let outcome = await manager.purchase(annual)
        XCTAssertEqual(outcome, .purchased)
        XCTAssertTrue(manager.isProActive)
    }

    func testEntitlementsRestoredOnRelaunch() async throws {
        let first = StoreKitManager(defaults: defaults)
        await first.loadProducts()
        _ = await first.purchase(try XCTUnwrap(first.monthlyProduct))

        let relaunched = StoreKitManager(defaults: defaults)
        XCTAssertFalse(relaunched.isProActive)
        await relaunched.refreshEntitlements()
        XCTAssertTrue(relaunched.isProActive)
    }

    func testExpiredSubscriptionRemovesPro() async throws {
        let manager = StoreKitManager(defaults: defaults)
        await manager.loadProducts()
        _ = await manager.purchase(try XCTUnwrap(manager.monthlyProduct))
        XCTAssertTrue(manager.isProActive)

        try session.expireSubscription(productIdentifier: AppConfig.StoreKit.monthlyProductID)
        // The local test server records the expiry at once, but the on-device entitlement cache
        // (Transaction.currentEntitlements) takes ~10–20 s to sync, so poll instead of checking once.
        let deadline = Date().addingTimeInterval(30)
        repeat {
            await manager.refreshEntitlements()
            if !manager.isProActive { break }
            try await Task.sleep(for: .seconds(1))
        } while Date() < deadline
        XCTAssertFalse(manager.isProActive)
    }

    func testAskToBuyPurchaseIsPendingAndDoesNotUnlock() async throws {
        session.askToBuyEnabled = true
        let manager = StoreKitManager(defaults: defaults)
        await manager.loadProducts()
        let outcome = await manager.purchase(try XCTUnwrap(manager.monthlyProduct))

        XCTAssertEqual(outcome, .pending)
        XCTAssertFalse(manager.isProActive)
        XCTAssertNotNil(manager.errorMessage) // user is told the purchase awaits approval
    }
}
