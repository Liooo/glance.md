import Foundation

enum HTML {
    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)

        for character in text {
            switch character {
            case "&":
                result += "&amp;"
            case "<":
                result += "&lt;"
            case ">":
                result += "&gt;"
            case "\"":
                result += "&quot;"
            case "'":
                result += "&#39;"
            default:
                result.append(character)
            }
        }

        return result
    }

    static func attribute(_ text: String) -> String {
        escape(text)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}
