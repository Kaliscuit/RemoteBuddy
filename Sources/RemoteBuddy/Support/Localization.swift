import Foundation

enum L10n {
    // Bundle selection follows the system's preferred languages, including
    // macOS per-app language preferences. English is the development fallback.
    static func tr(_ key: String, bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: tr(key), locale: Locale.current, arguments: arguments)
    }
}
