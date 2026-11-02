import Foundation

public enum DurationParser {
    /// "5", "5m", "90s", "1h30", "1:30", "25 min" → seconds. Nil for anything else.
    public static func seconds(_ text: String) -> TimeInterval? {
        let text = text.lowercased().replacingOccurrences(of: " ", with: "")
        guard !text.isEmpty else { return nil }
        if text.contains(":") {
            let parts = text.split(separator: ":").compactMap { Double($0) }
            guard parts.count == 2 else { return nil }
            return parts[0] * 60 + parts[1]
        }
        if let minutes = Double(text) { return minutes * 60 }
        var total = 0.0
        var number = ""
        var matched = false
        var lastUnit: Character = "m"
        for character in text {
            if character.isNumber || character == "." || character == "," {
                number.append(character == "," ? "." : character)
                continue
            }
            guard let value = Double(number) else { if "inuteseconds".contains(character) { continue } else { return nil } }
            switch character {
            case "h", "u": total += value * 3600; lastUnit = "h"
            case "m": total += value * 60; lastUnit = "m"
            case "s": total += value; lastUnit = "s"
            default: return nil
            }
            number = ""
            matched = true
        }
        if let value = Double(number) {
            // "1h30" means 1 h 30 min.
            total += lastUnit == "h" ? value * 60 : lastUnit == "m" && matched ? value : value * 60
            matched = true
        }
        return matched && total > 0 ? total : nil
    }
}
