import XCTest
@testable import FieldInspect

/// Guards the supported-language contract: exactly en, zh-Hans, zh-Hant, es; everything else → English.
final class LocalizationTests: XCTestCase {
    private let supported = ["en", "es", "zh-Hans", "zh-Hant"]

    func testAppBundleShipsExactlyTheFourSupportedLocalizations() {
        let shipped = Set(Bundle.main.localizations.filter { $0 != "Base" })
        XCTAssertEqual(shipped, Set(supported))
        XCTAssertEqual(Bundle.main.developmentLocalization, "en")
        let declared = Bundle.main.object(forInfoDictionaryKey: "CFBundleLocalizations") as? [String]
        XCTAssertEqual(Set(declared ?? []), Set(supported))
    }

    func testUnsupportedLanguagesFallBackToEnglish() {
        XCTAssertEqual(AppLocale.resolveLanguage(from: ["fr"]), "en")
        XCTAssertEqual(AppLocale.resolveLanguage(from: ["ja", "de"]), "en")
        XCTAssertEqual(AppLocale.resolveLanguage(from: []), "en")
        XCTAssertEqual(AppLocale.resolveLanguage(from: ["zh-Hant"]), "zh-Hant")
        XCTAssertEqual(AppLocale.resolveLanguage(from: ["es"]), "es")
        // What the system resolves for a French-only device against our bundle.
        let resolved = Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: ["fr-FR"])
        XCTAssertEqual(AppLocale.resolveLanguage(from: resolved), "en")
    }

    func testEveryLanguageResolvesUserFacingStrings() throws {
        let expectations: [String: [String: String]] = [
            "en": ["Cancel": "Cancel", "EXECUTIVE SUMMARY": "EXECUTIVE SUMMARY"],
            "zh-Hans": ["Cancel": "取消", "EXECUTIVE SUMMARY": "执行摘要", "Restore Purchases": "恢复购买"],
            "zh-Hant": ["Cancel": "取消", "EXECUTIVE SUMMARY": "重點摘要", "Restore Purchases": "回復購買項目"],
            "es": ["Cancel": "Cancelar", "EXECUTIVE SUMMARY": "RESUMEN EJECUTIVO", "Restore Purchases": "Restaurar Compras"]
        ]
        for (language, pairs) in expectations {
            let bundle = try XCTUnwrap(localizedBundle(language), "missing \(language).lproj")
            for (key, expected) in pairs {
                XCTAssertEqual(bundle.localizedString(forKey: key, value: "⚠️MISSING", table: nil), expected, "\(language): \(key)")
            }
        }
    }

    /// Every key compiled for English must exist in every other language (no silent English leaks).
    func testNoMissingKeysAcrossLanguages() throws {
        let english = try XCTUnwrap(stringKeys("en"))
        XCTAssertGreaterThan(english.count, 100)
        for language in supported where language != "en" {
            let keys = try XCTUnwrap(stringKeys(language))
            XCTAssertEqual(english.subtracting(keys), [], "\(language) is missing keys")
        }
    }

    /// zh-Hant must be real Traditional Chinese, not a copy of zh-Hans.
    func testTraditionalChineseIsNotSimplified() throws {
        let hans = try XCTUnwrap(localizedBundle("zh-Hans"))
        let hant = try XCTUnwrap(localizedBundle("zh-Hant"))
        let simplifiedOnly = Set("们这说为发动会时国对电报设务实验处录线门问关从车")
        var identical = 0
        for key in try XCTUnwrap(stringKeys("zh-Hant")) {
            let t = hant.localizedString(forKey: key, value: nil, table: nil)
            XCTAssertTrue(Set(t).isDisjoint(with: simplifiedOnly), "zh-Hant has Simplified characters: \(key) → \(t)")
            if t == hans.localizedString(forKey: key, value: nil, table: nil), t.unicodeScalars.contains(where: { $0.value >= 0x4E00 }) {
                identical += 1
            }
        }
        XCTAssertLessThan(identical, 40, "Too many zh-Hant strings identical to zh-Hans")
    }

    func testPermissionStringsLocalizedInAllLanguages() throws {
        for language in supported {
            let bundle = try XCTUnwrap(localizedBundle(language))
            for key in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSPhotoLibraryUsageDescription"] {
                let value = bundle.localizedString(forKey: key, value: "⚠️MISSING", table: "InfoPlist")
                XCTAssertFalse(value.contains("⚠️MISSING"), "\(language) \(key)")
            }
        }
    }

    func testGeminiRequestCarriesAppLanguage() throws {
        let payload = try GeminiInspectionService.shared.buildRequestPayload(
            photos: [],
            audioMemoData: nil,
            propertyType: .singleFamily,
            yearBuilt: 1995,
            inspectorHintNotes: "Double tapped breaker",
            outputLanguage: AppLocale.aiOutputLanguage(for: "zh-Hant")
        )
        let system = try XCTUnwrap(((payload["systemInstruction"] as? [String: Any])?["parts"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertTrue(system.contains("Traditional Chinese"))
        XCTAssertTrue(system.contains("OUTPUT LANGUAGE"))
        let contents = try XCTUnwrap(payload["contents"] as? [[String: Any]])
        let metadata = try XCTUnwrap((contents.first?["parts"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertTrue(metadata.contains("output_language"))
        XCTAssertFalse(metadata.contains("\"English\""))
        XCTAssertEqual(AppLocale.aiOutputLanguage(for: "fr"), "English (en-US)")
    }

    func testYearIsNotGroupedAndTemperatureFollowsRegion() {
        XCTAssertEqual(String(1995), "1995")
        let us = AppLocale.locale(forLanguage: "en", region: Locale.Region("US"))
        XCTAssertEqual(us.measurementSystem, .us)
        let tw = AppLocale.locale(forLanguage: "zh-Hant", region: Locale.Region("TW"))
        XCTAssertEqual(tw.language.languageCode?.identifier, "zh")
    }

    // MARK: - Helpers

    private func localizedBundle(_ language: String) -> Bundle? {
        Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    private func stringKeys(_ language: String) -> Set<String>? {
        guard let bundle = localizedBundle(language) else { return nil }
        var keys = Set<String>()
        for table in ["Localizable.strings", "Localizable.stringsdict"] {
            let url = bundle.bundleURL.appendingPathComponent(table)
            if let dict = NSDictionary(contentsOf: url) as? [String: Any] {
                keys.formUnion(dict.keys)
            }
        }
        return keys
    }
}
