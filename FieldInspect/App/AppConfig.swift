import Foundation

/// Central configuration for FieldInspect AI.
/// Replace placeholder identifiers and endpoints before App Store submission.
enum AppConfig {
    static let appName = "FieldInspect"
    static let bundleIdentifier = "com.fieldinspect.ai.app"
    static let appGroupIdentifier = "group.com.fieldinspect.ai.app"
    static let cloudKitContainerIdentifier = "iCloud.com.fieldinspect.ai.app"

    /// Set to true only after provisioning the iCloud container in an Apple Developer account.
    /// Leaving false in local/Simulator builds prevents CloudKit from trapping on missing entitlements.
    static let isCloudKitProvisioned = false

    /// Stateless Cloudflare Worker proxy endpoint forwarding multimodal requests to Gemini.
    /// workers.dev URLs always include your account subdomain: https://<worker-name>.<account-subdomain>.workers.dev
    /// Deployed URL (Cloudflare account subdomain `eztsou`).
    static let geminiProxyEndpoint = URL(string: "https://fieldinspect-gemini-proxy.eztsou.workers.dev/v1/analyze-defect")!

    /// Optional shared token sent as `X-FieldInspect-Token`. Must match the Worker's `APP_CLIENT_TOKEN` secret
    /// when that secret is set (prevents the proxy from being an open relay for your Gemini key). Empty = not sent.
    /// Injected at build time from Config/Secrets.xcconfig (gitignored) via the Info.plist key `GeminiProxyClientToken`.
    static let geminiProxyClientToken: String = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "GeminiProxyClientToken") as? String ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    /// Gemini model identifier used by the proxy.
    static let geminiModel = "gemini-3.8-flash"

    /// StoreKit 2 Product Identifiers
    enum StoreKit {
        static let monthlyProductID = "com.fieldinspect.ai.pro.monthly"
        static let annualProductID = "com.fieldinspect.ai.pro.annual"
        static let freeInspectionLimit = 2
    }

    /// App Store Compliance & Legal URLs (hosted via GitHub Pages from docs/privacy.html)
    enum Legal {
        static let privacyPolicyURL = URL(string: "https://tzuwentsou-hash.github.io/fieldinspect/privacy.html")!
        static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    }

    /// Media & Compression Guardrails
    enum Media {
        static let maxPhotosPerDefect = 4
        static let maxImageDimension: CGFloat = 1600
        static let jpegCompressionQuality: CGFloat = 0.75
        static let targetMaxBytes = 300_000
    }
}
