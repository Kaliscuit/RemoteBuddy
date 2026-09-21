import Foundation
import XCTest
@testable import RemoteBuddy

final class LocalizationTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func catalog(_ language: String, table: String = "Localizable") throws -> [String: String] {
        let url = root.appendingPathComponent("Resources/\(language).lproj/\(table).strings")
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
    }

    func testBothCatalogsCoverInterfaceAndPreserveFormatArguments() throws {
        let english = try catalog("en")
        let chinese = try catalog("zh-Hans")
        XCTAssertEqual(Set(english.keys), Set(chinese.keys))
        let placeholders = try NSRegularExpression(pattern: #"%(?:\d+\$)?[-+0 #]*\d*(?:\.\d+)?(?:ll|l|z)?[@diufFeEgGxXoscp]"#)
        func formats(_ value: String) -> [String] {
            placeholders.matches(in: value, range: NSRange(value.startIndex..., in: value)).map {
                (value as NSString).substring(with: $0.range)
            }
        }
        for (key, translation) in english {
            XCTAssertFalse(translation.isEmpty, key)
            XCTAssertNil(translation.range(of: #"\p{Han}"#, options: .regularExpression), key)
            XCTAssertEqual(formats(translation), formats(try XCTUnwrap(chinese[key])), key)
        }
        let references = try NSRegularExpression(pattern: #"L10n\.(?:tr|format)\("([^"]+)""#)
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root.appendingPathComponent("Sources/RemoteBuddy"), includingPropertiesForKeys: nil))
        var usedKeys = Set<String>()
        for case let file as URL in files where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            for match in references.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                usedKeys.insert((source as NSString).substring(with: match.range(at: 1)))
            }
        }
        XCTAssertEqual(usedKeys, Set(english.keys))
        for language in ["en", "zh-Hans"] {
            XCTAssertFalse(try XCTUnwrap(catalog(language, table: "InfoPlist")["NSBluetoothAlwaysUsageDescription"]).isEmpty)
        }
    }

    func testSystemLanguageMatchingAndBundleLookup() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let info = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let languages = try XCTUnwrap(info["CFBundleLocalizations"] as? [String])
        XCTAssertEqual(info["CFBundleDevelopmentRegion"] as? String, "en")
        for preferences in [["en-US", "zh-Hans-CN"], ["en-GB"], ["en-AU"]] {
            XCTAssertEqual(Bundle.preferredLocalizations(from: languages, forPreferences: preferences).first, "en")
        }
        XCTAssertEqual(Bundle.preferredLocalizations(from: languages, forPreferences: ["zh-Hans-CN", "en-US"]).first, "zh-Hans")
        for (language, expected) in [("en", "Button Settings…"), ("zh-Hans", "按键设置…")] {
            let bundle = try XCTUnwrap(Bundle(path: root.appendingPathComponent("Resources/\(language).lproj").path))
            XCTAssertEqual(L10n.tr("按键设置…", bundle: bundle), expected)
        }
    }
}
