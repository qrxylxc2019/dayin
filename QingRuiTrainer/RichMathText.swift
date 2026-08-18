import SwiftUI
import SwiftMath

// MARK: - 富文本解析：纯文本 / LaTeX 公式 / base64 图片

enum MathToken {
    case text(String)
    case latex(String)
    case image(Data)
}

enum RichMathParser {
    /// 把题目文本拆成 [文本 / $公式$ / <img base64>] 序列
    static func parse(_ raw: String) -> [MathToken] {
        var tokens: [MathToken] = []
        var pending = raw

        // 1) 提取所有 <img src="data:image/...;base64,...">
        let imgPattern = try? NSRegularExpression(
            pattern: #"<img[^>]*src="data:image/[a-zA-Z+]+;base64,([A-Za-z0-9+/=\s]+)""#)

        while let img = imgPattern {
            let ns = pending as NSString
            guard let m = img.firstMatch(in: pending, range: NSRange(location: 0, length: ns.length)) else { break }
            let before = ns.substring(to: m.range.location)
            appendTextAndMath(before, into: &tokens)
            let b64 = ns.substring(with: m.range(at: 1))
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "\n", with: "")
            tokens.append(.image(Data(base64Encoded: b64) ?? Data()))
            pending = ns.substring(from: m.range.location + m.range.length)
        }
        appendTextAndMath(pending, into: &tokens)
        return tokens
    }

    /// 2) 文本段内提取常见的行内与块级 LaTeX 公式
    private static func appendTextAndMath(_ text: String, into tokens: inout [MathToken]) {
        guard !text.isEmpty else { return }
        let pattern = #"(?s)\$\$(.+?)\$\$|\\\[(.+?)\\\]|\\\((.+?)\\\)|(?<![$\\])\$(?!\$)(.+?)(?<!\\)\$(?!\$)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            appendPlain(text, into: &tokens)
            return
        }

        let source = text as NSString
        let matches = expression.matches(
            in: text,
            range: NSRange(location: 0, length: source.length)
        )
        guard !matches.isEmpty else {
            appendPlain(text, into: &tokens)
            return
        }

        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                appendPlain(
                    source.substring(with: NSRange(location: cursor,
                                                   length: match.range.location - cursor)),
                    into: &tokens
                )
            }

            for group in 1..<match.numberOfRanges where match.range(at: group).location != NSNotFound {
                tokens.append(.latex(clean(source.substring(with: match.range(at: group)))))
                break
            }
            cursor = match.range.location + match.range.length
        }

        if cursor < source.length {
            appendPlain(source.substring(from: cursor), into: &tokens)
        }
    }

    private static func appendPlain(_ s: String, into tokens: inout [MathToken]) {
        guard !s.isEmpty else { return }
        tokens.append(.text(s))
    }

    /// SwiftMath 不支持的命令降级处理
    private static func clean(_ latex: String) -> String {
        latex
            .replacingOccurrences(of: "\\displaystyle", with: "")
            .replacingOccurrences(of: "\\bigg", with: "")
            .replacingOccurrences(of: "\\big", with: "")
            .replacingOccurrences(of: "\\,", with: " ")
            .replacingOccurrences(of: "\\(", with: "")
            .replacingOccurrences(of: "\\)", with: "")
            .replacingOccurrences(of: "\\[", with: "")
            .replacingOccurrences(of: "\\]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 混排视图（流式换行）

struct RichMathText: View {
    let raw: String
    var fontSize: CGFloat = 20
    var parsesMarkdown = false
    var lineSpacing: CGFloat = 0

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(Array(RichMathParser.parse(raw).enumerated()),
                    id: \.offset) { _, token in
                tokenView(token)
            }
        }
    }

    @ViewBuilder
    private func tokenView(_ token: MathToken) -> some View {
        switch token {
        case .text(let s):
            if parsesMarkdown,
               let attributed = try? AttributedString(
                   markdown: s,
                   options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
               ) {
                Text(attributed)
                    .font(.system(size: fontSize))
                    .lineSpacing(lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(s)
                    .font(.system(size: fontSize))
                    .lineSpacing(lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .latex(let latex):
            MathImageView(latex: latex, fontSize: fontSize)
        case .image(let data):
            if let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .cornerRadius(6)
            }
        }
    }
}

// MARK: - Markdown / LaTeX 混排

private enum MarkdownMathBlock {
    case paragraph(String)
    case heading(level: Int, text: String)
    case bullet(indent: Int, text: String)
    case ordered(indent: Int, marker: String, text: String)
    case quote(String)
    case code(String)
    case divider
}

private enum MarkdownMathParser {
    static func parse(_ raw: String) -> [MarkdownMathBlock] {
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var blocks: [MarkdownMathBlock] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var inCodeBlock = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll(keepingCapacity: true)
                } else {
                    flushParagraph()
                }
                inCodeBlock.toggle()
                continue
            }
            if inCodeBlock {
                codeLines.append(line)
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            if ["---", "***", "___"].contains(trimmed) {
                flushParagraph()
                blocks.append(.divider)
                continue
            }
            if let heading = heading(from: trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }
            if let item = listItem(from: line) {
                flushParagraph()
                blocks.append(item)
                continue
            }
            if trimmed.hasPrefix(">") {
                flushParagraph()
                let text = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                blocks.append(.quote(text))
                continue
            }
            paragraph.append(line)
        }

        if inCodeBlock, !codeLines.isEmpty {
            blocks.append(.code(codeLines.joined(separator: "\n")))
        }
        flushParagraph()
        return blocks
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let level = line.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }
        let index = line.index(line.startIndex, offsetBy: level)
        guard index < line.endIndex, line[index] == " " else { return nil }
        return (level, String(line[line.index(after: index)...]))
    }

    private static func listItem(from line: String) -> MarkdownMathBlock? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }.count
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            return .bullet(indent: indent,
                           text: String(trimmed.dropFirst(marker.count)))
        }

        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let remainder = trimmed.dropFirst(digits.count)
        guard remainder.hasPrefix(". ") || remainder.hasPrefix(") ") else { return nil }
        return .ordered(indent: indent,
                        marker: "\(digits).",
                        text: String(remainder.dropFirst(2)))
    }
}

struct MarkdownMathText: View {
    let raw: String
    var fontSize: CGFloat = 16
    var lineSpacing: CGFloat = 0
    var blockSpacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: blockSpacing) {
            ForEach(Array(MarkdownMathParser.parse(raw).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownMathBlock) -> some View {
        switch block {
        case .paragraph(let text):
            markdownLine(text, size: fontSize)
        case .heading(let level, let text):
            markdownLine(text, size: headingSize(level))
                .fontWeight(.semibold)
                .padding(.top, level <= 2 ? 4 : 0)
        case .bullet(let indent, let text):
            HStack(alignment: .top, spacing: 7) {
                Text("•")
                    .font(.system(size: fontSize, weight: .semibold))
                markdownLine(text, size: fontSize)
            }
            .padding(.leading, CGFloat(indent) * 6)
        case .ordered(let indent, let marker, let text):
            HStack(alignment: .top, spacing: 7) {
                Text(marker)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                markdownLine(text, size: fontSize)
            }
            .padding(.leading, CGFloat(indent) * 6)
        case .quote(let text):
            HStack(alignment: .top, spacing: 9) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 3)
                markdownLine(text, size: fontSize)
                    .foregroundStyle(.secondary)
            }
        case .code(let code):
            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(size: fontSize * 0.9, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        case .divider:
            Divider()
        }
    }

    private func markdownLine(_ text: String, size: CGFloat) -> some View {
        RichMathText(
            raw: text,
            fontSize: size,
            parsesMarkdown: true,
            lineSpacing: lineSpacing
        )
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: fontSize * 1.45
        case 2: fontSize * 1.3
        case 3: fontSize * 1.16
        default: fontSize
        }
    }
}

/// SwiftMath 公式渲染
struct MathImageView: View {
    let latex: String
    let fontSize: CGFloat

    var body: some View {
        if let ui = Self.render(latex: latex, fontSize: fontSize) {
            NaturalMathImageLayout(intrinsicSize: ui.size) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
            }
        } else {
            Text(latex).font(.system(size: fontSize * 0.8, design: .monospaced))
                .foregroundStyle(.red)
        }
    }

    /// MTImage → UIImage 渲染（失败时返回 nil，由调用方降级显示原文）
    static func render(latex: String, fontSize: CGFloat) -> UIImage? {
        var math = MathImage(latex: latex, fontSize: fontSize, textColor: .black)
        let (err, image, _) = math.asImage()
        guard err == nil, let mt = image else { return nil }
        #if canImport(UIKit)
        return mt as? UIImage
        #endif
    }
}

/// 保留公式的自然字号，仅在公式超过可用宽度时等比缩小。
private struct NaturalMathImageLayout: Layout {
    let intrinsicSize: CGSize

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        guard intrinsicSize.width > 0, intrinsicSize.height > 0 else { return .zero }
        let availableWidth = proposal.width ?? intrinsicSize.width
        let scale = min(1, availableWidth / intrinsicSize.width)
        return CGSize(width: intrinsicSize.width * scale,
                      height: intrinsicSize.height * scale)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        guard let subview = subviews.first else { return }
        subview.place(at: bounds.origin,
                      anchor: .topLeading,
                      proposal: ProposedViewSize(bounds.size))
    }
}

// MARK: - 简单流式布局（自动换行的 HStack 集合）

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        let maxWidth = proposal.width ?? .infinity
        for (i, sub) in subviews.enumerated() {
            guard i < result.positions.count else { break }
            sub.place(at: CGPoint(x: bounds.minX + result.positions[i].x,
                                  y: bounds.minY + result.positions[i].y),
                      proposal: ProposedViewSize(width: maxWidth.isFinite ? maxWidth : nil,
                                                 height: nil))
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews)
        -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, lineWidth: CGFloat = 0

        for sub in subviews {
            // 以面板宽度约束测量，防止内容按理想宽度超出右栏
            let size = sub.sizeThatFits(ProposedViewSize(width: maxWidth.isFinite ? maxWidth : nil,
                                                          height: nil))
            let w = min(size.width, maxWidth.isFinite ? maxWidth : size.width)
            let h = size.height
            if x > 0, x + w > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += w + spacing
            lineWidth = max(lineWidth, x)
            lineHeight = max(lineHeight, h)
        }
        return (positions, CGSize(width: lineWidth, height: y + lineHeight))
    }
}
