import Testing
@testable import GlanceMDCore

@Suite("MarkdownRenderer")
struct MarkdownRendererTests {
    private let renderer = MarkdownRenderer()

    @Test("renders headings and emphasis")
    func headingsAndEmphasis() {
        let html = renderer.renderBody("# Title\n\nA **bold** and *em* word.")

        #expect(html.contains("<h1>Title</h1>"))
        #expect(html.contains("<strong>bold</strong>"))
        #expect(html.contains("<em>em</em>"))
    }

    @Test("renders fenced code without interpreting markdown")
    func fencedCode() {
        let html = renderer.renderBody("```swift\nlet x = \"<tag>\"\n```")

        #expect(html.contains("<span class=\"qm-code-lang\">swift</span>"))
        #expect(html.contains("<pre><code class=\"language-swift\">"))
        #expect(html.contains("let x = &quot;&lt;tag&gt;&quot;"))
    }

    @Test("renders fenced code language badges with escaped language")
    func fencedCodeLanguageBadgeEscapesLanguage() {
        let html = renderer.renderBody("```swift<script>\nlet x = 1\n```")

        #expect(html.contains("<span class=\"qm-code-lang\">swift&lt;script&gt;</span>"))
        #expect(html.contains("class=\"language-swift&lt;script&gt;\""))
    }

    @Test("renders fenced code without language without a badge")
    func fencedCodeWithoutLanguageHasNoBadge() {
        let html = renderer.renderBody("```\nplain\n```")

        #expect(html.contains("<pre><code>plain</code></pre>"))
        #expect(!html.contains("qm-code-lang"))
    }

    @Test("renders mermaid fences as diagram containers")
    func mermaidFence() {
        let html = renderer.renderBody("""
        ```mermaid
        graph TD
          A --> B
        ```
        """)

        #expect(html.contains("class=\"qm-mermaid\""))
        #expect(html.contains("data-qm-mermaid"))
        #expect(html.contains("data-qm-mode=\"preview\""))
        #expect(html.contains("<span class=\"qm-code-lang\">mermaid</span>"))
        #expect(html.contains("class=\"qm-mermaid-mode-toggle\""))
        #expect(html.contains("data-qm-target-mode=\"preview\""))
        #expect(html.contains("data-qm-target-mode=\"code\""))
        #expect(html.contains("<span class=\"qm-mermaid-mode-text\">Preview</span>"))
        #expect(html.contains("<span class=\"qm-mermaid-mode-text\">Code</span>"))
        #expect(html.contains("<template class=\"qm-mermaid-source\">graph TD"))
        #expect(html.contains("<div class=\"qm-mermaid-preview\"></div>"))
        #expect(html.contains("<pre class=\"qm-mermaid-code\"><code>graph TD"))
        #expect(!html.contains("language-mermaid"))
    }

    @Test("escapes mermaid source")
    func mermaidFenceEscapesSource() {
        let html = renderer.renderBody("""
        ```mermaid
        graph TD
          A["<script>"] --> B
        ```
        """)

        #expect(html.contains("&lt;script&gt;"))
        #expect(!html.contains("<script>"))
    }

    @Test("renders GFM tables")
    func tables() {
        let html = renderer.renderBody("""
        | Name | Value |
        | --- | --- |
        | A | **1** |
        """)

        #expect(html.contains("<div class=\"qm-table-wrap\">"))
        #expect(html.contains("<table>"))
        #expect(html.contains("<th>Name</th>"))
        #expect(html.contains("<td><strong>1</strong></td>"))
    }

    @Test("document CSS keeps tables horizontally scrollable")
    func tableCSS() {
        let html = renderer.renderDocument("""
        | Name | Value |
        | --- | --- |
        | A | B |
        """)

        #expect(html.contains(".qm-table-wrap {"))
        #expect(html.contains("overflow-x: auto;"))
        #expect(html.contains("white-space: nowrap;"))
    }

    @Test("renders task lists")
    func taskLists() {
        let html = renderer.renderBody("""
        - [x] Done
        - [ ] Todo
        """)

        #expect(html.contains("<input type=\"checkbox\" disabled checked>Done"))
        #expect(html.contains("<input type=\"checkbox\" disabled>Todo"))
    }

    @Test("renders indented nested lists")
    func nestedLists() {
        let html = renderer.renderBody("""
        - Parent
          - Child
            1. Ordered grandchild
          - Sibling child
        - Next parent
        """)

        #expect(html.contains("<li>Parent<ul><li>Child<ol><li>Ordered grandchild</li></ol></li><li>Sibling child</li></ul></li>"))
        #expect(html.contains("<li>Next parent</li>"))
    }

    @Test("document CSS indents nested lists")
    func nestedListCSS() {
        let html = renderer.renderDocument("""
        - Parent
          - Child
        """)

        #expect(html.contains("ul, ol { padding-left: 1.45em; }"))
        #expect(html.contains("li > ul, li > ol { margin: 0.18em 0 0.18em; padding-left: 1.45em; }"))
        #expect(html.contains("<li>Parent<ul><li>Child</li></ul></li>"))
    }

    @Test("same-indent unordered and ordered lists remain separate")
    func mixedTopLevelLists() {
        let html = renderer.renderBody("""
        - Unordered
        1. Ordered
        """)

        #expect(html.contains("<ul><li>Unordered</li></ul>"))
        #expect(html.contains("<ol><li>Ordered</li></ol>"))
    }

    @Test("escapes raw HTML by default")
    func escapesHTML() {
        let html = renderer.renderBody("<script>alert(1)</script>")

        #expect(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        #expect(!html.contains("<script>"))
    }

    @Test("omits remote images by default")
    func omitsRemoteImages() {
        let html = renderer.renderBody("![alt](https://example.com/a.png)")

        #expect(html.contains("alt"))
        #expect(!html.contains("<img"))
    }

    @Test("renders links and autolinks")
    func links() {
        let html = renderer.renderBody("[OpenAI](https://openai.com) and <https://example.com>")

        #expect(html.contains("<a href=\"https://openai.com\">OpenAI</a>"))
        #expect(html.contains("<a href=\"https://example.com\">https://example.com</a>"))
    }

    @Test("does not render non-web links")
    func nonWebLinks() {
        let html = renderer.renderBody("[Local](file:///Applications/Calculator.app) [Settings](x-apple.systempreferences:com.apple.preference.security)")

        #expect(html.contains("Local"))
        #expect(html.contains("Settings"))
        #expect(!html.contains("<a href=\"file://"))
        #expect(!html.contains("<a href=\"x-apple.systempreferences:"))
    }
}
