import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StoreKitManager.self) private var storeKit

    @State private var selectedPlan: PlanOption = .annual

    enum PlanOption {
        case annual
        case monthly
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    valuePropsSection
                    planSelectorSection
                    ctaSection
                    footerSection
                }
                .padding(20)
            }
            .background(DesignSystem.Colors.surfacePrimary)
            .navigationTitle(Text(verbatim: "FieldInspect Pro"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: storeKit.isProActive) { _, isActive in
                // e.g. an Ask to Buy approval arriving via Transaction.updates while the paywall is open
                if isActive { dismiss() }
            }
            .task {
                if storeKit.products.isEmpty {
                    await storeKit.loadProducts()
                }
            }
            .alert("Subscription Notice", isPresented: Binding(
                get: { storeKit.errorMessage != nil },
                set: { if !$0 { storeKit.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(storeKit.errorMessage ?? "")
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 10) {
            BrandLogoView()
                .frame(maxWidth: 220, maxHeight: 68)

            Text("Unlimited AI Inspection Reports")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(
                storeKit.lifetimeInspectionsCreated >= AppConfig.StoreKit.freeInspectionLimit
                ? "You've used your \(AppConfig.StoreKit.freeInspectionLimit) free trial inspections. Upgrade to FieldInspect Pro to unlock unlimited property inspections, multimodal AI narratives, and client-ready PDF exports."
                : "Includes \(AppConfig.StoreKit.freeInspectionLimit) free full inspections. Upgrade to FieldInspect Pro for unlimited property inspections, multimodal AI narratives, and client-ready PDF exports."
            )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var valuePropsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            benefitRow(icon: "sparkles", title: "InterNACHI & ASHI AI Synthesis", subtitle: "Cross-verifies site photos and voice memos into defensible narratives.")
            benefitRow(icon: "wifi.slash", title: "Offline Basement & Crawlspace Queue", subtitle: "Capture findings anywhere; auto-syncs when signal returns.")
            benefitRow(icon: "doc.richtext.fill", title: "Instant Illustrated PDF Reports", subtitle: "Executive Summary + Building System sections ready for buyers & agents.")
        }
        .padding(16)
        .background(DesignSystem.Colors.surfaceSecondary, in: RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius))
    }

    private func benefitRow(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(DesignSystem.Colors.brandAccent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var planSelectorSection: some View {
        VStack(spacing: 12) {
            // Prices and the savings badge come only from StoreKit, localized to the user's storefront.
            // Hard-coded "$349.99"/"Save 42%" fallbacks showed wrong prices outside the US and when
            // products failed to load, which App Review treats as misleading pricing (3.1.2).
            planCard(
                option: .annual,
                title: "Annual Pro",
                price: storeKit.annualProduct?.displayPrice ?? "—",
                period: "per year",
                badge: storeKit.annualSavingsPercent.map { String(localized: "Save \($0)%") }
            )

            planCard(
                option: .monthly,
                title: "Monthly Pro",
                price: storeKit.monthlyProduct?.displayPrice ?? "—",
                period: "per month",
                badge: nil
            )

            if storeKit.products.isEmpty {
                HStack(spacing: 8) {
                    if storeKit.isLoadingProducts {
                        ProgressView()
                        Text("Loading subscription options…")
                    } else {
                        Button("Retry loading prices") {
                            Task { await storeKit.loadProducts() }
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func planCard(option: PlanOption, title: LocalizedStringKey, price: String, period: LocalizedStringKey, badge: String?) -> some View {
        let isSelected = selectedPlan == option
        return Button {
            selectedPlan = option
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let badge {
                            Text(badge)
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(DesignSystem.Colors.severitySatisfactory, in: Capsule())
                        }
                    }
                    Text("Unlimited properties, AI findings & PDF exports")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(price)
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(.primary)
                    Text(period)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(DesignSystem.Colors.surfaceSecondary, in: RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius)
                    .stroke(isSelected ? DesignSystem.Colors.brandAccent : DesignSystem.Colors.cardBorder, lineWidth: isSelected ? 2.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var ctaSection: some View {
        Button {
            Task {
                if storeKit.products.isEmpty {
                    await storeKit.loadProducts()
                }
                let targetProduct = selectedPlan == .annual ? storeKit.annualProduct : storeKit.monthlyProduct
                guard let product = targetProduct else {
                    storeKit.errorMessage = String(localized: "Subscription products are not available yet. Please verify your network connection or App Store Connect product configuration.")
                    return
                }
                let outcome = await storeKit.purchase(product)
                if outcome == .purchased {
                    dismiss()
                }
            }
        } label: {
            HStack {
                if storeKit.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Subscribe to FieldInspect Pro")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(.white)
            .background(DesignSystem.Colors.brandPrimary, in: RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius))
        }
        .disabled(storeKit.isLoading || storeKit.isLoadingProducts)
    }

    private var footerSection: some View {
        VStack(spacing: 10) {
            Button("Restore Purchases") {
                Task {
                    await storeKit.restorePurchases()
                    if storeKit.isProActive {
                        dismiss()
                    }
                }
            }
            .font(.footnote.bold())
            .foregroundStyle(DesignSystem.Colors.brandAccent)
            .disabled(storeKit.isLoading)

            HStack(spacing: 16) {
                Link("Privacy Policy", destination: AppConfig.Legal.privacyPolicyURL)
                Text("•")
                    .foregroundStyle(.tertiary)
                Link("Terms of Use (EULA)", destination: AppConfig.Legal.termsOfUseURL)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)

            Text("Payment is charged to your Apple ID account at confirmation of purchase. Subscriptions automatically renew unless canceled at least 24 hours before the end of the current period. Manage or cancel anytime in Apple ID Account Settings.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
