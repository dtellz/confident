import SwiftUI

/// Lightweight Markdown renderer for assistant messages. Handles the block-level
/// syntax models emit constantly — headings, bullet/numbered lists, code fences,
/// blockquotes, horizontal rules — and defers inline styling (**bold**,
/// *italic*, `code`, [links](url)) to `AttributedString`.
///
/// Streaming-safe: it re-parses cheaply on every token, and malformed or partial
/// Markdown (e.g. an unclosed `**` mid-stream) falls back to literal text rather
/// than throwing or disappearing.
struct MarkdownText: View {
    let text: String
    var baseFont: Font = .system(.body, design: .rounded)
    var textColor: Color = .white.opacity(0.94)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(MarkdownParser.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Block rendering

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(headingFont(level))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)

        case .paragraph(let text):
            inline(text)
                .font(baseFont)
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .bullet(let indent, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "•").foregroundStyle(textColor.opacity(0.6))
                inline(text).foregroundStyle(textColor)
                Spacer(minLength: 0)
            }
            .font(baseFont)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, CGFloat(indent) * 16)

        case .ordered(let indent, let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "\(number).").foregroundStyle(textColor.opacity(0.6)).monospacedDigit()
                inline(text).foregroundStyle(textColor)
                Spacer(minLength: 0)
            }
            .font(baseFont)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, CGFloat(indent) * 16)

        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(textColor.opacity(0.35))
                    .frame(width: 3)
                inline(text)
                    .font(baseFont)
                    .italic()
                    .foregroundStyle(textColor.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .code(let code):
            Text(verbatim: code)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))

        case .rule:
            Rectangle()
                .fill(textColor.opacity(0.18))
                .frame(height: 1)
                .padding(.vertical, 2)
        }
    }

    /// Render one span of inline Markdown. Falls back to the raw string when the
    /// (possibly partial) Markdown can't be parsed.
    private func inline(_ string: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let attributed = try? AttributedString(markdown: string, options: options) {
            return Text(attributed)
        }
        return Text(verbatim: string)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .system(.title2, design: .rounded, weight: .bold)
        case 2: .system(.title3, design: .rounded, weight: .bold)
        default: .system(.headline, design: .rounded, weight: .bold)
        }
    }
}

/// A parsed block-level Markdown element.
enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(indent: Int, text: String)
    case ordered(indent: Int, number: String, text: String)
    case quote(text: String)
    case code(String)
    case rule
}

/// Splits a Markdown string into block-level elements. Inline syntax is left
/// untouched for `AttributedString` to interpret during rendering.
enum MarkdownParser {

    static func parse(_ raw: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }

        let lines = raw.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block — capture verbatim until the closing fence.
            if trimmed.hasPrefix("```") {
                flushParagraph()
                var code: [String] = []
                i += 1
                while i < lines.count,
                      !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                blocks.append(.code(code.joined(separator: "\n")))
                i += 1 // consume the closing fence (no-op if we hit the end)
                continue
            }

            // Blank line ends the current paragraph.
            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            // Horizontal rule.
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.rule)
                i += 1
                continue
            }

            // ATX heading (#, ##, … up to ######, requires a trailing space).
            if let heading = headingMatch(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                i += 1
                continue
            }

            // Blockquote.
            if trimmed.hasPrefix(">") {
                flushParagraph()
                let text = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                blocks.append(.quote(text: text))
                i += 1
                continue
            }

            // Unordered list item: -, *, or + followed by a space.
            if let bullet = bulletMatch(line) {
                flushParagraph()
                blocks.append(.bullet(indent: bullet.indent, text: bullet.text))
                i += 1
                continue
            }

            // Ordered list item: "N. ".
            if let ordered = orderedMatch(line) {
                flushParagraph()
                blocks.append(.ordered(indent: ordered.indent, number: ordered.number, text: ordered.text))
                i += 1
                continue
            }

            paragraph.append(line)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    // MARK: - Line classifiers

    private static func headingMatch(_ s: String) -> (level: Int, text: String)? {
        guard s.first == "#" else { return nil }
        var level = 0
        var idx = s.startIndex
        while idx < s.endIndex, s[idx] == "#", level < 6 {
            level += 1
            idx = s.index(after: idx)
        }
        // Require a space after the hashes to avoid matching "#hashtag".
        guard idx < s.endIndex, s[idx] == " " else { return nil }
        let text = String(s[idx...]).trimmingCharacters(in: .whitespaces)
        return (level, text)
    }

    private static func bulletMatch(_ line: String) -> (indent: Int, text: String)? {
        let indent = leadingIndent(line)
        let body = line.drop { $0 == " " || $0 == "\t" }
        guard let marker = body.first, "-*+".contains(marker) else { return nil }
        let afterMarker = body.dropFirst()
        guard afterMarker.first == " " else { return nil }
        return (indent, String(afterMarker.dropFirst()))
    }

    private static func orderedMatch(_ line: String) -> (indent: Int, number: String, text: String)? {
        let indent = leadingIndent(line)
        let body = line.drop { $0 == " " || $0 == "\t" }
        var digits = ""
        var idx = body.startIndex
        while idx < body.endIndex, body[idx].isNumber {
            digits.append(body[idx])
            idx = body.index(after: idx)
        }
        guard !digits.isEmpty, idx < body.endIndex, body[idx] == "." else { return nil }
        idx = body.index(after: idx)
        guard idx < body.endIndex, body[idx] == " " else { return nil }
        return (indent, digits, String(body[body.index(after: idx)...]))
    }

    /// Indentation level (one level per 2 spaces, tab = one level), capped so
    /// deeply nested lists don't run off the bubble.
    private static func leadingIndent(_ s: String) -> Int {
        var spaces = 0
        for c in s {
            if c == " " { spaces += 1 }
            else if c == "\t" { spaces += 2 }
            else { break }
        }
        return min(spaces / 2, 4)
    }
}
