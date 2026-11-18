# FieldInspect AI

Native iOS 17+ (SwiftUI + SwiftData) residential home inspection app built for InterNACHI / ASHI certified home inspectors.

## Architecture

- **iOS App (`FieldInspect/`)**
  - **Persistence:** `SwiftData` local-first storage with `@Attribute(.externalStorage)` for downsampled JPEG photos and `.m4a` voice memos, plus optional `CloudKit` private database sync (`AppConfig.isCloudKitProvisioned`).
  - **Media & Markup (`Core/ImageProcessor.swift`, `Core/AudioRecorderManager.swift`):**
    - Downsamples photos to `<= 1600px` longest edge, JPEG `0.75` (`< 300 KB` target) via `CGImageSource` to prevent PDF OOM crashes.
    - Interactive SwiftUI `Canvas` red callout overlay (freehand circle & arrow tools) baked directly onto exported JPEGs.
    - Hold-to-record `.m4a` voice memos with `AVAudioSession` interruption handling.
  - **AI Pipeline (`Services/GeminiInspectionService.swift`, `Core/OfflineSyncQueue.swift`):**
    - Sends multimodal JSON payloads (metadata + 1–4 JPEGs + `.m4a` audio) through a stateless Cloudflare Worker proxy to Gemini (`gemini-2.5-flash`), enforcing InterNACHI-compliant structured JSON output.
    - `NWPathMonitor` FIFO offline queue for basement/crawlspace inspections without cellular signal.
  - **PDF Report Engine (`Services/PDFReportGenerator.swift`, `Views/Export/ReportPreviewView.swift`):**
    - US Letter (`612 x 792 pt`, `40 pt` margins) two-pass `UIGraphicsPDFRenderer` generating Cover Page, Executive Summary with exact page references, Building System findings cards with strict page-break math, and `Page X of Y` footers.
  - **Monetization (`Services/StoreKitManager.swift`, `Views/Export/PaywallView.swift`):**
    - StoreKit 2 subscriptions (`$49.99/mo`, `$349.99/yr`) after 2 free trial property inspections.

- **Stateless Gemini Proxy (`Worker/`)**
  - Cloudflare Worker (`Worker/src/index.ts`) forwarding `/v1/analyze-defect` requests to Google Gemini API with server-side `GEMINI_API_KEY`.

## Setup & Deployment

### 1. Cloudflare Worker Proxy
```bash
cd Worker
npm install
npx wrangler secret put GEMINI_API_KEY
npx wrangler secret put APP_CLIENT_TOKEN   # optional but recommended: blocks other clients from using your Gemini key
npm run deploy
```
Update `AppConfig.geminiProxyEndpoint` in `FieldInspect/App/AppConfig.swift` with your deployed URL (`https://fieldinspect-gemini-proxy.<your-account-subdomain>.workers.dev/v1/analyze-defect`). If you set `APP_CLIENT_TOKEN`, put the same value in `AppConfig.geminiProxyClientToken`.

### 2. Xcode & iOS
1. Open `FieldInspect.xcodeproj` in Xcode.
2. Select your Apple Developer Team under **Signing & Capabilities**.
3. Once your iCloud container (`iCloud.com.fieldinspect.ai.app`) is provisioned, set `AppConfig.isCloudKitProvisioned = true` in `FieldInspect/App/AppConfig.swift`.
4. For local StoreKit 2 testing in Simulator, the shared scheme is pre-configured with `FieldInspect.storekit`.

## Testing
```bash
xcodebuild test -project FieldInspect.xcodeproj -scheme FieldInspect -destination 'platform=iOS Simulator,name=iPhone 17'
```
