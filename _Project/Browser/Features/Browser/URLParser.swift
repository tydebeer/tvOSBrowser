import Foundation

enum URLParser {

    static func parse(_ input: String) -> URL? {
        let trimmed = VoiceInputSanitizer.sanitize(input)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }

        if !trimmed.contains(" "), trimmed.contains(".") {
            return URL(string: "https://\(trimmed)")
        }

        return URL(string: SettingsManager.shared.searchURL(forQuery: trimmed))
    }
}
