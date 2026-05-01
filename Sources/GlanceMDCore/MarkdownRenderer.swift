import Foundation

public struct MarkdownRenderer: Sendable {
    public struct Options: Sendable {
        public var allowRemoteImages: Bool
        public var allowRawHTML: Bool

        public init(allowRemoteImages: Bool = false, allowRawHTML: Bool = false) {
            self.allowRemoteImages = allowRemoteImages
            self.allowRawHTML = allowRawHTML
        }
    }

    private let options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    public func renderDocument(_ markdown: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: file:; style-src 'unsafe-inline';">
        <style>
        :root {
          color-scheme: light dark;
          --bg: transparent;
          --fg: #111111;
          --muted: rgba(60, 60, 67, 0.68);
          --border: rgba(60, 60, 67, 0.18);
          --code-bg: rgba(118, 118, 128, 0.14);
          --table-head: rgba(118, 118, 128, 0.11);
          --mark-bg: rgba(255, 214, 10, 0.42);
          --mark-ring: rgba(255, 159, 10, 0.38);
          --link: #006adc;
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --bg: transparent;
            --fg: rgba(245, 245, 247, 0.92);
            --muted: rgba(235, 235, 245, 0.62);
            --border: rgba(235, 235, 245, 0.17);
            --code-bg: rgba(235, 235, 245, 0.12);
            --table-head: rgba(235, 235, 245, 0.09);
            --mark-bg: rgba(255, 214, 10, 0.32);
            --mark-ring: rgba(255, 159, 10, 0.34);
            --link: #64a8ff;
          }
        }
        :root[data-theme="light"] {
          color-scheme: light;
          --bg: transparent;
          --fg: #111111;
          --muted: rgba(60, 60, 67, 0.68);
          --border: rgba(60, 60, 67, 0.18);
          --code-bg: rgba(118, 118, 128, 0.14);
          --table-head: rgba(118, 118, 128, 0.11);
          --mark-bg: rgba(255, 214, 10, 0.42);
          --mark-ring: rgba(255, 159, 10, 0.38);
          --link: #006adc;
        }
        :root[data-theme="dark"] {
          color-scheme: dark;
          --bg: transparent;
          --fg: rgba(245, 245, 247, 0.92);
          --muted: rgba(235, 235, 245, 0.62);
          --border: rgba(235, 235, 245, 0.17);
          --code-bg: rgba(235, 235, 245, 0.12);
          --table-head: rgba(235, 235, 245, 0.09);
          --mark-bg: rgba(255, 214, 10, 0.32);
          --mark-ring: rgba(255, 159, 10, 0.34);
          --link: #64a8ff;
        }
        * { box-sizing: border-box; }
        html, body { background: var(--bg); }
        body {
          margin: 0;
          padding: 34px 16px 14px 38px;
          color: var(--fg);
          font: 13px/1.47 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
          overflow-wrap: anywhere;
          -webkit-font-smoothing: antialiased;
        }
        body > :first-child { margin-top: 0; }
        body > :last-child { margin-bottom: 0; }
        h1, h2, h3, h4, h5, h6 { margin: 0.75em 0 0.35em; line-height: 1.15; }
        h1 { font-size: 1.45em; }
        h2 { font-size: 1.25em; }
        h3 { font-size: 1.12em; }
        p, ul, ol, blockquote, pre, table, .qm-table-wrap, .qm-code-block, .qm-mermaid { margin: 0.55em 0; }
        ul, ol { padding-left: 1.45em; }
        li > ul, li > ol { margin: 0.18em 0 0.18em; padding-left: 1.45em; }
        li { margin: 0.18em 0; }
        code {
          padding: 0.1em 0.28em;
          border-radius: 5px;
          background: var(--code-bg);
          font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
          font-size: 0.92em;
        }
        pre {
          padding: 10px 11px;
          border: 1px solid var(--border);
          border-radius: 9px;
          background: var(--code-bg);
          overflow: auto;
        }
        pre code { padding: 0; background: transparent; }
        .qm-code-block {
          position: relative;
        }
        .qm-code-block pre {
          margin: 0;
          padding-top: 30px;
        }
        .qm-code-lang {
          position: absolute;
          top: 7px;
          left: 8px;
          z-index: 1;
          max-width: calc(100% - 16px);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          padding: 2px 7px;
          border: 1px solid var(--border);
          border-radius: 6px;
          background: var(--code-bg);
          color: var(--muted);
          font: 10px/1.3 ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
        }
        .qm-mermaid {
          position: relative;
          padding: 34px 12px 12px;
          border: 1px solid var(--border);
          border-radius: 9px;
          background: var(--code-bg);
          overflow: auto;
        }
        .qm-mermaid-preview svg {
          display: block;
          max-width: 100%;
          height: auto;
          margin: 0 auto;
        }
        .qm-mermaid-source {
          display: none;
        }
        .qm-mermaid-code {
          display: none;
          margin: 0;
          padding: 0;
          border: 0;
          background: transparent;
        }
        .qm-mermaid[data-qm-mode="code"] .qm-mermaid-preview,
        .qm-mermaid[data-qm-mode="code"] .qm-mermaid-loading,
        .qm-mermaid[data-qm-mode="code"] .qm-mermaid-error-message {
          display: none;
        }
        .qm-mermaid[data-qm-mode="code"] .qm-mermaid-code {
          display: block;
        }
        .qm-mermaid-mode-toggle {
          position: absolute;
          top: 7px;
          right: 8px;
          z-index: 1;
          display: inline-flex;
          gap: 2px;
          padding: 1px;
          border: 1px solid var(--border);
          border-radius: 6px;
          background: var(--code-bg);
        }
        .qm-mermaid-mode-button {
          width: 23px;
          height: 17px;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          gap: 4px;
          border: 0;
          border-radius: 4px;
          background: transparent;
          color: var(--muted);
          cursor: pointer;
          font: 10px/1.3 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
        }
        .qm-mermaid-mode-button:hover {
          color: var(--fg);
        }
        .qm-mermaid-mode-button svg {
          width: 11px;
          height: 11px;
          stroke: currentColor;
          stroke-width: 2;
          stroke-linecap: round;
          stroke-linejoin: round;
          fill: none;
        }
        .qm-mermaid-mode-text {
          position: absolute;
          width: 1px;
          height: 1px;
          overflow: hidden;
          clip: rect(0 0 0 0);
          white-space: nowrap;
        }
        .qm-mermaid[data-qm-mode="preview"] .qm-mermaid-mode-button[data-qm-target-mode="preview"],
        .qm-mermaid[data-qm-mode="code"] .qm-mermaid-mode-button[data-qm-target-mode="code"] {
          background: var(--border);
          color: var(--fg);
        }
        .qm-mermaid-loading,
        .qm-mermaid-error {
          margin: 0;
          padding: 0;
          border: 0;
          background: transparent;
        }
        .qm-mermaid-error-message {
          margin: 0 0 8px;
          color: var(--muted);
          font-weight: 600;
        }
        blockquote {
          padding-left: 0.85em;
          color: var(--muted);
          border-left: 3px solid var(--border);
        }
        .qm-table-wrap {
          overflow-x: auto;
        }
        .qm-table-wrap table {
          margin: 0;
        }
        table {
          width: 100%;
          border-collapse: collapse;
          table-layout: auto;
          font-size: 0.96em;
        }
        th, td {
          padding: 6px 8px;
          border: 1px solid var(--border);
          vertical-align: top;
          white-space: nowrap;
        }
        th {
          background: var(--table-head);
          text-align: left;
          font-weight: 600;
        }
        a { color: var(--link); text-decoration: none; }
        mark[data-qm-hit] {
          border-radius: 4px;
          background: var(--mark-bg);
          box-shadow: inset 0 0 0 1px var(--mark-ring);
          color: inherit;
        }
        mark[data-qm-hit].qm-active-hit {
          background: rgba(255, 159, 10, 0.48);
          box-shadow: inset 0 0 0 1px rgba(255, 149, 0, 0.75);
        }
        input[type="checkbox"] { margin: 0 0.35em 0 0; vertical-align: -0.12em; }
        </style>
        </head>
        <body>\(renderBody(markdown))</body>
        </html>
        """
    }

    public func renderBody(_ markdown: String) -> String {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var blocks: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let fence = fenceInfo(trimmed) {
                let start = index
                index += 1
                var codeLines: [String] = []
                while index < lines.count {
                    if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence.marker) {
                        index += 1
                        break
                    }
                    codeLines.append(lines[index])
                    index += 1
                }
                blocks.append(renderCodeBlock(codeLines.joined(separator: "\n"), language: fence.language, closed: index > start + 1))
                continue
            }

            if isTableHeader(at: index, lines: lines) {
                let table = collectTable(from: index, lines: lines)
                blocks.append(renderTable(table.rows))
                index = table.nextIndex
                continue
            }

            if let heading = headingInfo(trimmed) {
                blocks.append("<h\(heading.level)>\(renderInline(heading.text))</h\(heading.level)>")
                index += 1
                continue
            }

            if horizontalRule(trimmed) {
                blocks.append("<hr>")
                index += 1
                continue
            }

            if listMarker(line) != nil {
                let list = collectList(from: index, lines: lines)
                blocks.append(renderList(list.items, ordered: list.ordered))
                index = list.nextIndex
                continue
            }

            if trimmed.hasPrefix(">") {
                let quote = collectBlockquote(from: index, lines: lines)
                blocks.append("<blockquote>\(renderBody(quote.text))</blockquote>")
                index = quote.nextIndex
                continue
            }

            let paragraph = collectParagraph(from: index, lines: lines)
            blocks.append("<p>\(renderInline(paragraph.text))</p>")
            index = paragraph.nextIndex
        }

        return blocks.joined(separator: "\n")
    }

    private func renderInline(_ text: String) -> String {
        var placeholders: [String] = []
        var escaped = HTML.escape(text)

        escaped = replaceCodeSpans(in: escaped, placeholders: &placeholders)
        escaped = replaceImages(in: escaped, placeholders: &placeholders)
        escaped = replaceLinks(in: escaped, placeholders: &placeholders)
        escaped = replaceAutoLinks(in: escaped, placeholders: &placeholders)
        escaped = replaceStrikethrough(in: escaped)
        escaped = replaceStrongAndEmphasis(in: escaped)

        for (offset, value) in placeholders.enumerated() {
            escaped = escaped.replacingOccurrences(of: placeholder(offset), with: value)
        }

        return escaped.replacingOccurrences(of: "  \n", with: "<br>")
    }

    private func replaceCodeSpans(in text: String, placeholders: inout [String]) -> String {
        replacePattern("`([^`]+)`", in: text) { match, source in
            let code = source.substring(with: match.range(at: 1))
            let token = placeholder(placeholders.count)
            placeholders.append("<code>\(code)</code>")
            return token
        }
    }

    private func replaceImages(in text: String, placeholders: inout [String]) -> String {
        replacePattern("!\\[([^\\]]*)\\]\\(([^\\)\\s]+)(?:\\s+&quot;([^&]*)&quot;)?\\)", in: text) { match, source in
            let alt = source.substring(with: match.range(at: 1))
            let url = source.substring(with: match.range(at: 2))
            let title = match.range(at: 3).location == NSNotFound ? "" : source.substring(with: match.range(at: 3))
            let token = placeholder(placeholders.count)

            if options.allowRemoteImages || isLocalImageURL(url) {
                let titleAttribute = title.isEmpty ? "" : " title=\"\(HTML.attribute(title))\""
                placeholders.append("<img src=\"\(HTML.attribute(url))\" alt=\"\(HTML.attribute(alt))\"\(titleAttribute)>")
            } else {
                placeholders.append("<span>\(alt.isEmpty ? "image omitted" : alt)</span>")
            }

            return token
        }
    }

    private func replaceLinks(in text: String, placeholders: inout [String]) -> String {
        replacePattern("(?<!!)\\[([^\\]]+)\\]\\(([^\\)\\s]+)(?:\\s+&quot;([^&]*)&quot;)?\\)", in: text) { match, source in
            let label = source.substring(with: match.range(at: 1))
            let url = source.substring(with: match.range(at: 2))
            let title = match.range(at: 3).location == NSNotFound ? "" : source.substring(with: match.range(at: 3))
            let token = placeholder(placeholders.count)
            guard isSafeExternalLinkURL(url) else {
                placeholders.append(label)
                return token
            }
            let titleAttribute = title.isEmpty ? "" : " title=\"\(HTML.attribute(title))\""
            placeholders.append("<a href=\"\(HTML.attribute(url))\"\(titleAttribute)>\(label)</a>")
            return token
        }
    }

    private func replaceAutoLinks(in text: String, placeholders: inout [String]) -> String {
        replacePattern("&lt;(https?://[^\\s&]+)&gt;", in: text) { match, source in
            let url = source.substring(with: match.range(at: 1))
            let token = placeholder(placeholders.count)
            placeholders.append("<a href=\"\(HTML.attribute(url))\">\(url)</a>")
            return token
        }
    }

    private func replaceStrikethrough(in text: String) -> String {
        replacePattern("~~(.+?)~~", in: text) { match, source in
            "<del>\(source.substring(with: match.range(at: 1)))</del>"
        }
    }

    private func replaceStrongAndEmphasis(in text: String) -> String {
        var output = replacePattern("\\*\\*(.+?)\\*\\*", in: text) { match, source in
            "<strong>\(source.substring(with: match.range(at: 1)))</strong>"
        }
        output = replacePattern("__(.+?)__", in: output) { match, source in
            "<strong>\(source.substring(with: match.range(at: 1)))</strong>"
        }
        output = replacePattern("(?<!\\*)\\*([^\\*]+)\\*(?!\\*)", in: output) { match, source in
            "<em>\(source.substring(with: match.range(at: 1)))</em>"
        }
        output = replacePattern("(?<!_)_([^_]+)_(?!_)", in: output) { match, source in
            "<em>\(source.substring(with: match.range(at: 1)))</em>"
        }
        return output
    }

    private func renderCodeBlock(_ code: String, language: String?, closed _: Bool) -> String {
        guard let language = normalizedFenceLanguage(language) else {
            return "<pre><code>\(HTML.escape(code))</code></pre>"
        }

        if language.lowercased() == "mermaid" {
            let escapedCode = HTML.escape(code)
            return """
            <div class="qm-mermaid" data-qm-mermaid data-qm-mode="preview">
            <span class="qm-code-lang">mermaid</span>
            <div class="qm-mermaid-mode-toggle" role="group" aria-label="Mermaid display mode">
            <button type="button" class="qm-mermaid-mode-button" data-qm-target-mode="preview" aria-label="Show Mermaid preview">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg><span class="qm-mermaid-mode-text">Preview</span>
            </button>
            <button type="button" class="qm-mermaid-mode-button" data-qm-target-mode="code" aria-label="Show Mermaid code">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m16 18 6-6-6-6"/><path d="m8 6-6 6 6 6"/></svg><span class="qm-mermaid-mode-text">Code</span>
            </button>
            </div>
            <template class="qm-mermaid-source">\(escapedCode)</template>
            <div class="qm-mermaid-preview"></div>
            <pre class="qm-mermaid-loading"><code>\(escapedCode)</code></pre>
            <pre class="qm-mermaid-code"><code>\(escapedCode)</code></pre>
            </div>
            """
        }

        let languageAttribute = HTML.attribute(language)
        return """
        <div class="qm-code-block">
        <span class="qm-code-lang">\(HTML.escape(language))</span>
        <pre><code class="language-\(languageAttribute)">\(HTML.escape(code))</code></pre>
        </div>
        """
    }

    private func normalizedFenceLanguage(_ language: String?) -> String? {
        guard let firstToken = language?.split(whereSeparator: { $0.isWhitespace }).first else {
            return nil
        }

        let normalized = String(firstToken).trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func renderTable(_ rows: [[String]]) -> String {
        guard let header = rows.first else {
            return ""
        }

        let headerHTML = header.map { "<th>\(renderInline($0))</th>" }.joined()
        let bodyHTML = rows.dropFirst().map { row in
            "<tr>\(row.map { "<td>\(renderInline($0))</td>" }.joined())</tr>"
        }.joined()

        return """
        <div class="qm-table-wrap">
        <table><thead><tr>\(headerHTML)</tr></thead><tbody>\(bodyHTML)</tbody></table>
        </div>
        """
    }

    private func renderList(_ items: [ListItem], ordered: Bool) -> String {
        let tag = ordered ? "ol" : "ul"
        let body = items.map { item -> String in
            let checkbox: String
            if let checked = item.checked {
                checkbox = "<input type=\"checkbox\" disabled\(checked ? " checked" : "")>"
            } else {
                checkbox = ""
            }
            return "<li>\(checkbox)\(renderInline(item.text))\(item.children.map(renderListNode).joined())</li>"
        }.joined()
        return "<\(tag)>\(body)</\(tag)>"
    }

    private func renderListNode(_ node: ListNode) -> String {
        renderList(node.items, ordered: node.ordered)
    }

    private func collectParagraph(from start: Int, lines: [String]) -> (text: String, nextIndex: Int) {
        var collected: [String] = []
        var index = start

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || headingInfo(trimmed) != nil || fenceInfo(trimmed) != nil || listMarker(lines[index]) != nil || trimmed.hasPrefix(">") || horizontalRule(trimmed) {
                break
            }
            if index + 1 < lines.count && isTableHeader(at: index, lines: lines) {
                break
            }
            collected.append(trimmed)
            index += 1
        }

        return (collected.joined(separator: " "), index)
    }

    private func collectBlockquote(from start: Int, lines: [String]) -> (text: String, nextIndex: Int) {
        var collected: [String] = []
        var index = start

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else {
                break
            }
            let content = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            collected.append(String(content))
            index += 1
        }

        return (collected.joined(separator: "\n"), index)
    }

    private func collectList(from start: Int, lines: [String]) -> (items: [ListItem], ordered: Bool, nextIndex: Int) {
        var flattenedItems: [(indent: Int, item: ListItem, ordered: Bool)] = []
        var index = start
        let ordered = listMarker(lines[start])?.ordered ?? false

        while index < lines.count {
            guard let marker = listMarker(lines[index]) else {
                break
            }

            var text = marker.text.trimmingCharacters(in: .whitespaces)
            var checked: Bool?

            if text.hasPrefix("[ ] ") {
                checked = false
                text.removeFirst(4)
            } else if text.lowercased().hasPrefix("[x] ") {
                checked = true
                text.removeFirst(4)
            }

            flattenedItems.append((
                indent: marker.indent,
                item: ListItem(text: text, checked: checked),
                ordered: marker.ordered
            ))
            index += 1
        }

        let rootIndent = flattenedItems.first?.indent ?? 0
        var cursor = 0
        let items = buildListItems(from: flattenedItems, cursor: &cursor, indent: rootIndent, ordered: ordered)
        return (items, ordered, start + cursor)
    }

    private func buildListItems(
        from flattenedItems: [(indent: Int, item: ListItem, ordered: Bool)],
        cursor: inout Int,
        indent: Int,
        ordered: Bool
    ) -> [ListItem] {
        var items: [ListItem] = []

        while cursor < flattenedItems.count {
            let current = flattenedItems[cursor]

            if current.indent < indent {
                break
            }

            if current.indent > indent {
                guard !items.isEmpty else {
                    break
                }

                let childOrdered = current.ordered
                let childItems = buildListItems(
                    from: flattenedItems,
                    cursor: &cursor,
                    indent: current.indent,
                    ordered: childOrdered
                )
                items[items.count - 1].children.append(ListNode(ordered: childOrdered, items: childItems))
                continue
            }

            guard current.ordered == ordered else {
                break
            }

            items.append(current.item)
            cursor += 1
        }

        return items
    }

    private func collectTable(from start: Int, lines: [String]) -> (rows: [[String]], nextIndex: Int) {
        var rows = [splitTableRow(lines[start])]
        var index = start + 2

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("|"), !trimmed.isEmpty else {
                break
            }
            rows.append(splitTableRow(lines[index]))
            index += 1
        }

        let width = rows.first?.count ?? 0
        rows = rows.map { row in
            if row.count < width {
                return row + Array(repeating: "", count: width - row.count)
            }
            return Array(row.prefix(width))
        }

        return (rows, index)
    }

    private func splitTableRow(_ line: String) -> [String] {
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

    private func isTableHeader(at index: Int, lines: [String]) -> Bool {
        guard index + 1 < lines.count else {
            return false
        }

        let header = lines[index].trimmingCharacters(in: .whitespaces)
        let separator = lines[index + 1].trimmingCharacters(in: .whitespaces)

        guard header.contains("|"), separator.contains("|") else {
            return false
        }

        return splitTableRow(separator).allSatisfy { cell in
            let stripped = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":- "))
            return stripped.isEmpty && cell.contains("-")
        }
    }

    private func fenceInfo(_ line: String) -> (marker: String, language: String?)? {
        guard line.hasPrefix("```") || line.hasPrefix("~~~") else {
            return nil
        }

        let marker = String(line.prefix(3))
        let language = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
        return (marker, language.isEmpty ? nil : language)
    }

    private func headingInfo(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard hashes > 0, hashes <= 6 else {
            return nil
        }

        let remainder = line.dropFirst(hashes)
        guard remainder.first == " " else {
            return nil
        }

        return (hashes, remainder.trimmingCharacters(in: .whitespaces))
    }

    private func horizontalRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        return compact.count >= 3 && (Set(compact) == ["-"] || Set(compact) == ["*"] || Set(compact) == ["_"])
    }

    private func listMarker(_ line: String) -> (ordered: Bool, text: String, indent: Int)? {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        let patterns = [
            #"^(\s*)[-+*]\s+(.+)$"#,
            #"^(\s*)\d+[.)]\s+(.+)$"#
        ]

        for (offset, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: range),
                  match.range(at: 1).location != NSNotFound,
                  match.range(at: 2).location != NSNotFound else {
                continue
            }

            let indent = nsLine.substring(with: match.range(at: 1))
                .reduce(0) { count, character in
                    count + (character == "\t" ? 4 : 1)
                }

            return (offset == 1, nsLine.substring(with: match.range(at: 2)), indent)
        }

        return nil
    }

    private func isLocalImageURL(_ url: String) -> Bool {
        url.hasPrefix("data:image/") || url.hasPrefix("file://")
    }

    private func isSafeExternalLinkURL(_ url: String) -> Bool {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    private func placeholder(_ index: Int) -> String {
        "\u{E000}QM\(index)\u{E001}"
    }

    private func replacePattern(_ pattern: String, in text: String, transform: (NSTextCheckingResult, NSString) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }

        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed()
        var output = text

        for match in matches {
            let replacement = transform(match, source)
            if let range = Range(match.range, in: output) {
                output.replaceSubrange(range, with: replacement)
            }
        }

        return output
    }
}

private struct ListItem {
    var text: String
    var checked: Bool?
    var children: [ListNode] = []
}

private struct ListNode {
    var ordered: Bool
    var items: [ListItem]
}
