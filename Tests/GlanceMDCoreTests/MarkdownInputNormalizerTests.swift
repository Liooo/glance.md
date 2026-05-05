import Testing
@testable import GlanceMDCore

@Suite("MarkdownInputNormalizer")
struct MarkdownInputNormalizerTests {
    @Test("leaves valid tables unchanged")
    func validTableUnchanged() {
        let markdown = """
        | Name | Value |
        | --- | --- |
        | App | Glance.md |
        """

        #expect(MarkdownInputNormalizer.normalize(markdown) == markdown)
    }

    @Test("repairs wrapped header rows")
    func wrappedHeaderRow() {
        let markdown = """
        | Long column
        name | Value |
        | --- | --- |
        | App | Glance.md |
        """

        let normalized = MarkdownInputNormalizer.normalize(markdown)

        #expect(normalized.contains("| Long column name | Value |"))
        #expect(MarkdownRenderer().renderBody(normalized).contains("<table>"))
    }

    @Test("repairs wrapped separator rows")
    func wrappedSeparatorRow() {
        let markdown = """
        | Name | Value |
        | --- |
        --- |
        | App | Glance.md |
        """

        let normalized = MarkdownInputNormalizer.normalize(markdown)

        #expect(normalized.contains("| --- | --- |"))
        #expect(MarkdownRenderer().renderBody(normalized).contains("<table>"))
    }

    @Test("repairs wrapped body rows")
    func wrappedBodyRow() {
        let markdown = """
        | Name | Value |
        | --- | --- |
        | App | The preview wraps a long
        Codex terminal table cell |
        """

        let normalized = MarkdownInputNormalizer.normalize(markdown)

        #expect(normalized.contains("| App | The preview wraps a long Codex terminal table cell |"))
        #expect(MarkdownRenderer().renderBody(normalized).contains("<td>The preview wraps a long Codex terminal table cell</td>"))
    }

    @Test("repairs multiple wrapped table rows")
    func multipleWrappedRows() {
        let markdown = """
        | Name | Notes |
        | --- | --- |
        | First | A long terminal
        wrapped note |
        | Second | Another long terminal
        wrapped note |
        """

        let normalized = MarkdownInputNormalizer.normalize(markdown)

        #expect(normalized.contains("| First | A long terminal wrapped note |"))
        #expect(normalized.contains("| Second | Another long terminal wrapped note |"))
    }

    @Test("repairs wrapped markdown link destinations in table cells")
    func wrappedLinkDestinationInTableCell() {
        let markdown = """
        | Version | Item | Impact |
        | --- | --- | --- |
        | [`v1.13.0`](https://github.com/inngest/inngest/releases/tag/v1.13.0) | [Cron rewritten on queues](https://github.com/inngest/inngest/releases/tag/
        v1.13.0) | Internal scheduling architecture change. |
        """

        let normalized = MarkdownInputNormalizer.normalize(markdown)

        #expect(normalized.contains("[Cron rewritten on queues](https://github.com/inngest/inngest/releases/tag/v1.13.0)"))
        #expect(MarkdownRenderer().renderBody(normalized).contains("<a href=\"https://github.com/inngest/inngest/releases/tag/v1.13.0\">Cron rewritten on queues</a>"))
    }

    @Test("repairs wrapped markdown link label and destination boundary")
    func wrappedLinkBoundaryInTableCell() {
        let markdown = """
        | Version | Item | Impact |
        | --- | --- | --- |
        | [`v1.17.6`](https://github.com/inngest/inngest/releases/tag/v1.17.6) | [Connect panic, graceful shutdown, race, and silent message-loss fixes]
        (https://github.com/inngest/inngest/releases/tag/v1.17.6) | Reliability improvement. |
        """

        let normalized = MarkdownInputNormalizer.normalize(markdown)

        #expect(normalized.contains("[Connect panic, graceful shutdown, race, and silent message-loss fixes](https://github.com/inngest/inngest/releases/tag/v1.17.6)"))
        #expect(MarkdownRenderer().renderBody(normalized).contains("<a href=\"https://github.com/inngest/inngest/releases/tag/v1.17.6\">Connect panic, graceful shutdown, race, and silent message-loss fixes</a>"))
    }

    @Test("preserves table-looking text inside fences")
    func fencedTableUnchanged() {
        let markdown = """
        ```md
        | Name |
        | --- |
        wrapped |
        ```
        """

        #expect(MarkdownInputNormalizer.normalize(markdown) == markdown)
    }

    @Test("leaves non-table prose with pipes unchanged")
    func proseWithPipesUnchanged() {
        let markdown = "Use `a | b` in prose without a table separator."

        #expect(MarkdownInputNormalizer.normalize(markdown) == markdown)
    }

    @Test("leaves lists and blockquotes unchanged")
    func listsAndBlockquotesUnchanged() {
        let markdown = """
        - Item with | pipe
        > Quote with | pipe
        """

        #expect(MarkdownInputNormalizer.normalize(markdown) == markdown)
    }

    @Test("normalizes CRLF")
    func normalizesCRLF() {
        let markdown = "| Name | Value |\r\n| --- | --- |\r\n| App | Glance.md |"

        #expect(MarkdownInputNormalizer.normalize(markdown) == "| Name | Value |\n| --- | --- |\n| App | Glance.md |")
    }
}
