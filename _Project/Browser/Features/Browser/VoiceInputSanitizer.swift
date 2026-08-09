import Foundation

/// Strips Voice Control command tokens that sometimes land in UITextField as literal text.
enum VoiceInputSanitizer {

    static func sanitize(_ input: String) -> String {
        var s = input

        // "w\letter" → "w", "4\number" → "4"
        s = replace(s, pattern: #"([A-Za-z])\\letter"#, template: "$1")
        s = replace(s, pattern: #"(\d)\\number"#, template: "$1")

        // ".\dot" / "\dot" → "."
        s = replace(s, pattern: #"\.?\\dot"#, template: ".")

        // "\next" → "next" (spoken word left with a backslash prefix)
        s = replace(s, pattern: #"\\next"#, template: "next")

        // Collapse whitespace
        s = replace(s, pattern: #"\s+"#, template: " ")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // Host-like results: drop remaining spaces between tokens (www. next4 .com → www.next4.com)
        if s.contains("."), !s.contains("://") {
            var compact = s.replacingOccurrences(of: " ", with: "")
            compact = replace(compact, pattern: #"\.{2,}"#, template: ".")
            if compact.contains(".") {
                return compact
            }
        }

        return s
    }

    private static func replace(_ input: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return input
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: template)
    }
}
