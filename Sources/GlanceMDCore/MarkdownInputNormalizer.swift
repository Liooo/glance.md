import Foundation

public enum MarkdownInputNormalizer {
    public static func normalize(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var result: [String] = []
        var index = 0
        var fenceMarker: String?

        while index < lines.count {
            let line = lines[index]
            if let marker = fenceMarker {
                result.append(line)
                if line.trimmingCharacters(in: .whitespaces).hasPrefix(marker) {
                    fenceMarker = nil
                }
                index += 1
                continue
            }

            if let marker = fenceMarkerStart(line) {
                fenceMarker = marker
                result.append(line)
                index += 1
                continue
            }

            if let table = repairedTable(from: lines, start: index) {
                result.append(contentsOf: table.lines)
                index = table.nextIndex
                continue
            }

            result.append(line)
            index += 1
        }

        return result.joined(separator: "\n")
    }

    private static func repairedTable(from lines: [String], start: Int) -> (lines: [String], nextIndex: Int)? {
        guard start + 1 < lines.count, lines[start].contains("|") else {
            return nil
        }

        let headerStart = start
        let maxHeaderFragments = 4
        let maxSeparatorFragments = 3
        let headerLimit = min(lines.count, headerStart + maxHeaderFragments)

        for separatorStart in (headerStart + 1)..<headerLimit {
            let headerFragments = Array(lines[headerStart..<separatorStart])

            guard !headerFragments.contains(where: isBlockBoundary) else {
                break
            }

            let separatorLimit = min(lines.count, separatorStart + maxSeparatorFragments)
            for separatorEnd in separatorStart..<separatorLimit {
                let separatorFragments = Array(lines[separatorStart...separatorEnd])

                guard !separatorFragments.contains(where: isBlockBoundary) else {
                    break
                }

                let separator = joinedRow(separatorFragments)
                guard isSeparatorRow(separator) else {
                    continue
                }

                let width = splitTableRow(separator).count
                guard width >= 2 else {
                    continue
                }

                let style = TableStyle(separator: separator)
                let header = joinedRow(headerFragments)
                guard isCompleteTableRow(header, width: width, style: style),
                      !isSeparatorRow(header) else {
                    continue
                }

                var repairedLines: [String] = [
                    headerFragments.count == 1 ? headerFragments[0] : header,
                    separatorFragments.count == 1 ? separatorFragments[0] : separator
                ]
                var cursor = separatorEnd + 1

                while let row = repairedBodyRow(from: lines, start: cursor, width: width, style: style) {
                    repairedLines.append(row.line)
                    cursor = row.nextIndex
                }

                return (repairedLines, cursor)
            }
        }

        return nil
    }

    private static func repairedBodyRow(from lines: [String], start: Int, width: Int, style: TableStyle) -> (line: String, nextIndex: Int)? {
        guard start < lines.count, lines[start].contains("|"), !isBlockBoundary(lines[start]) else {
            return nil
        }

        let maxFragments = 6
        let limit = min(lines.count, start + maxFragments)
        var fragments: [String] = []

        for end in start..<limit {
            guard !isBlockBoundary(lines[end]) else {
                break
            }

            fragments.append(lines[end])
            let candidate = joinedRow(fragments)
            if isCompleteTableRow(candidate, width: width, style: style) {
                return (fragments.count == 1 ? fragments[0] : candidate, end + 1)
            }
        }

        return nil
    }

    private static func isCompleteTableRow(_ line: String, width: Int, style: TableStyle) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else {
            return false
        }

        if style.hasLeadingAndTrailingPipe {
            return trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && pipeCount(in: trimmed) >= width + 1
        }

        return splitTableRow(trimmed).count >= width
    }

    private static func isSeparatorRow(_ line: String) -> Bool {
        let cells = splitTableRow(line)
        guard cells.count >= 2 else {
            return false
        }

        return cells.allSatisfy { cell in
            let stripped = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":- "))
            return stripped.isEmpty && cell.contains("-")
        }
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }
        return trimmed.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func joinedRow(_ fragments: [String]) -> String {
        fragments
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
    }

    private static func isBlockBoundary(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || fenceMarkerStart(trimmed) != nil
    }

    private static func fenceMarkerStart(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") {
            return "```"
        }
        if trimmed.hasPrefix("~~~") {
            return "~~~"
        }
        return nil
    }

    private static func pipeCount(in line: String) -> Int {
        line.reduce(0) { count, character in
            character == "|" ? count + 1 : count
        }
    }

    private struct TableStyle {
        let hasLeadingAndTrailingPipe: Bool

        init(separator: String) {
            let trimmed = separator.trimmingCharacters(in: .whitespaces)
            hasLeadingAndTrailingPipe = trimmed.hasPrefix("|") && trimmed.hasSuffix("|")
        }
    }
}
