import CookedHTML
import UIKit

/// Computes the height of a `PostNativeCell`'s content stack without going
/// through UIKit's autolayout solver. Lets `heightForRowAt` (or
/// `systemLayoutSizeFitting`) short-circuit the slow Core Text + autolayout
/// path that otherwise dominates first-display cost on complex posts.
///
/// Coverage is intentionally partial: each block type is opt-in and unsupported
/// types return `nil`, signalling the caller to fall back to autosizing. As
/// renderers are migrated, more cells gain the fast path.
enum BlockHeightCalculator {
    /// Total content stack height for `annotatedBlocks` at `config.contentWidth`,
    /// including the inter-block spacing. Returns `nil` if any block type
    /// doesn't yet support height precomputation.
    ///
    /// `spacing` defaults to `NativeContentRenderer.contentStackSpacing` for the
    /// top-level cell stack. Nested stacks (blockquote, list, discourseQuote)
    /// use smaller values and pass them explicitly.
    static func contentStackHeight(
        for annotatedBlocks: [AnnotatedBlock],
        config: NativeRenderConfig,
        spacing: CGFloat = NativeContentRenderer.contentStackSpacing
    ) -> CGFloat? {
        guard let heights = perBlockHeights(annotatedBlocks: annotatedBlocks, config: config) else {
            return nil
        }
        if heights.isEmpty { return 0 }
        return heights.reduce(0, +) + CGFloat(heights.count - 1) * spacing
    }

    /// Total height of a nested block stack (blockquote, discourseQuote inner
    /// content, list complex item, etc.). Inputs are plain `ContentBlock`s —
    /// these paths skip the consecutive-paragraph merge that the top-level
    /// `AnnotatedBlock` path uses, mirroring `NativeContentRenderer.renderBlockList`.
    static func nestedStackHeight(
        for blocks: [ContentBlock],
        config: NativeRenderConfig,
        spacing: CGFloat
    ) -> CGFloat? {
        if blocks.isEmpty { return 0 }
        var total: CGFloat = 0
        for block in blocks {
            guard let h = height(for: block, config: config) else { return nil }
            total += h
        }
        return total + CGFloat(blocks.count - 1) * spacing
    }

    /// Per-block heights aligned with the view sequence produced by
    /// `NativeContentRenderer.renderBlocks(_:config:delegate:pollProvider:)`.
    /// Returns `nil` if any block type is unsupported.
    ///
    /// Note: matches the consecutive-paragraph merge — N adjacent paragraphs
    /// collapse into a single merged height entry, not N entries.
    static func perBlockHeights(
        annotatedBlocks: [AnnotatedBlock],
        config: NativeRenderConfig
    ) -> [CGFloat]? {
        var result: [CGFloat] = []
        var i = 0
        while i < annotatedBlocks.count {
            let annotated = annotatedBlocks[i]

            // Mirror NativeContentRenderer's consecutive-paragraph merge.
            if case .paragraph = annotated.block {
                var j = i + 1
                while j < annotatedBlocks.count, case .paragraph = annotatedBlocks[j].block {
                    j += 1
                }
                guard let h = mergedParagraphHeight(annotatedBlocks[i..<j], config: config) else {
                    return nil
                }
                result.append(h)
                i = j
                continue
            }

            guard let h = height(for: annotated.block, config: config) else {
                return nil
            }
            result.append(h)
            i += 1
        }
        return result
    }

    /// Height of a single block at `config.contentWidth`. Returns `nil` for
    /// block types that haven't been migrated yet.
    static func height(for block: ContentBlock, config: NativeRenderConfig) -> CGFloat? {
        switch block {
        case .paragraph(let inlines):
            return paragraphHeight(inlines, config: config)

        case .heading(let level, let inlines):
            return headingHeight(level: level, inlines: inlines, config: config)

        case .image(let src, _, let width, let height, _):
            return imageHeight(width: width, height: height, src: src, containerWidth: config.contentWidth)

        case .divider:
            return Self.dividerHeight

        case .codeBlock(_, let code):
            return codeBlockHeight(code: code, config: config)

        case .blockquote(let inner):
            return blockquoteHeight(inner: inner, config: config)

        case .discourseQuote(_, _, _, _, let categoryName, _, let content):
            return discourseQuoteHeight(
                hasCategory: !(categoryName ?? "").isEmpty,
                content: content,
                config: config
            )

        case .list(let ordered, let items):
            return listHeight(ordered: ordered, items: items, config: config)

        // Everything else: not yet supported. Caller falls back to autosize.
        case .onebox,
             .video,
             .table,
             .details,
             .spoiler,
             .poll,
             .rawHTML:
            return nil
        }
    }

    // MARK: - Constants matching renderer layouts

    /// Mirrors `DividerRenderer` — the inner line is 1px but the container is 16pt tall.
    private static let dividerHeight: CGFloat = 16

    /// Mirrors `TappableImageContainer.referenceWidth` — Discourse's reference width
    /// at which `<img width=...>` translates to full container width.
    private static let imageReferenceWidth: CGFloat = 690

    // MARK: - Paragraph

    private static func paragraphHeight(
        _ inlines: [InlineNode],
        config: NativeRenderConfig
    ) -> CGFloat {
        let attr = inlines.attributedString(config: config.attributedStringConfig)
        return attributedTextHeight(attr, width: config.contentWidth)
    }

    /// Mirrors `NativeContentRenderer.mergeParagraphs` — joins paragraphs with a
    /// small (8pt) font separator so the rendered height matches what the cell
    /// will actually display.
    private static func mergedParagraphHeight<C: Collection>(
        _ blocks: C,
        config: NativeRenderConfig
    ) -> CGFloat? where C.Element == AnnotatedBlock {
        let result = NSMutableAttributedString()
        for (offset, annotated) in blocks.enumerated() {
            guard case .paragraph(let inlines) = annotated.block else { return nil }
            if offset > 0 {
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: config.baseFont.withSize(8),
                ]))
            }
            result.append(inlines.attributedString(config: config.attributedStringConfig))
        }
        return attributedTextHeight(result, width: config.contentWidth)
    }

    // MARK: - Heading

    /// Mirrors `HeadingRenderer.render` — picks the same per-level font and
    /// rebuilds the attributed string with that as the base font so the
    /// computed height matches what the rendered label / textView produces.
    private static func headingHeight(
        level: Int,
        inlines: [InlineNode],
        config: NativeRenderConfig
    ) -> CGFloat {
        let (size, weight) = headingFontParams(level: level)
        let headingConfig = NativeRenderConfig(
            baseFont: FontManager.shared.font(size: size, weight: weight),
            baseColor: config.baseColor,
            linkColor: config.linkColor,
            codeFont: config.codeFont,
            codeBackgroundColor: config.codeBackgroundColor,
            contentWidth: config.contentWidth,
            baseURL: config.baseURL
        )
        let attr = inlines.attributedString(config: headingConfig.attributedStringConfig)
        return attributedTextHeight(attr, width: config.contentWidth)
    }

    private static func headingFontParams(level: Int) -> (CGFloat, UIFont.Weight) {
        switch level {
        case 1: return (28, .bold)
        case 2: return (24, .bold)
        case 3: return (20, .semibold)
        case 4: return (18, .semibold)
        case 5: return (16, .semibold)
        default: return (16, .medium)
        }
    }

    // MARK: - Image

    /// Mirrors `TappableImageContainer.init`'s height formula. Consults
    /// `ImageDimensionCache` when HTML didn't provide both dimensions; falls
    /// back to the 16:9 placeholder ratio when nothing is known yet.
    private static func imageHeight(
        width: Int?,
        height: Int?,
        src: String?,
        containerWidth: CGFloat
    ) -> CGFloat {
        let resolvedW: Int?
        let resolvedH: Int?
        if let w = width, let h = height, w > 0, h > 0 {
            resolvedW = w
            resolvedH = h
        } else if let src, let url = URL(string: src),
                  let cached = ImageDimensionCache.shared.size(for: url),
                  cached.width > 0, cached.height > 0
        {
            resolvedW = Int(cached.width)
            resolvedH = Int(cached.height)
        } else {
            resolvedW = nil
            resolvedH = nil
        }

        if let w = resolvedW, let h = resolvedH {
            let fraction = min(CGFloat(w) / Self.imageReferenceWidth, 1)
            let displayWidth = containerWidth * fraction
            return CGFloat(h) * (displayWidth / CGFloat(w))
        }
        return containerWidth * 9.0 / 16.0
    }

    // MARK: - Code Block

    /// Mirrors `CodeBlockRenderer`. The code view height is clamped to
    /// `maxVisibleLines` lines of `codeFont.lineHeight`. Fixed chrome around
    /// the code view: top 4 + header 26 + 2 + (codeHeight) + bottom 12.
    private static func codeBlockHeight(code: String, config: NativeRenderConfig) -> CGFloat {
        var newlineCount = 0
        for ch in code.unicodeScalars where ch == "\n" { newlineCount += 1 }
        let lineCount = newlineCount + 1
        let visibleLines = min(lineCount, Self.codeMaxVisibleLines)
        let codeHeight = ceil(config.codeFont.lineHeight * CGFloat(visibleLines)) + 6
        return Self.codeChromeHeight + codeHeight
    }

    /// 4 (top) + 26 (header copy button) + 2 (gap to code) + 12 (bottom) = 44
    private static let codeChromeHeight: CGFloat = 44
    private static let codeMaxVisibleLines = 20

    // MARK: - Blockquote

    /// Mirrors `BlockquoteRenderer`. Inner content uses spacing 6, width
    /// reduced by 15 (3 bar + 12 gap to content); outer container has 4pt
    /// top + 4pt bottom padding.
    private static func blockquoteHeight(inner: [ContentBlock], config: NativeRenderConfig) -> CGFloat? {
        let innerConfig = NativeRenderConfig(
            baseFont: config.baseFont,
            baseColor: .secondaryLabel,
            linkColor: config.linkColor,
            codeFont: config.codeFont,
            codeBackgroundColor: config.codeBackgroundColor,
            contentWidth: config.contentWidth - 15,
            baseURL: config.baseURL
        )
        guard let innerH = nestedStackHeight(for: inner, config: innerConfig, spacing: 6) else { return nil }
        return innerH + Self.blockquoteVerticalPadding
    }

    /// 4 (top) + 4 (bottom)
    private static let blockquoteVerticalPadding: CGFloat = 8

    // MARK: - Discourse Quote

    /// Mirrors `DiscourseQuoteRenderer`. The renderer reduces the inner content
    /// width by 36pt (more than the constraint math demands — kept identical to
    /// match exact rendering). Header height is `max(avatarSize, textBaseline)`.
    private static func discourseQuoteHeight(
        hasCategory: Bool,
        content: [ContentBlock],
        config: NativeRenderConfig
    ) -> CGFloat? {
        let innerConfig = NativeRenderConfig(
            baseFont: config.baseFont.withSize(config.baseFont.pointSize - 1),
            baseColor: .secondaryLabel,
            linkColor: config.linkColor,
            codeFont: config.codeFont,
            codeBackgroundColor: config.codeBackgroundColor,
            contentWidth: config.contentWidth - 36,
            baseURL: config.baseURL
        )
        guard let innerH = nestedStackHeight(for: content, config: innerConfig, spacing: 6) else { return nil }

        let avatarSize = FontManager.shared.scaled(20)
        // Header text intrinsic height — title uses 13pt semibold (one line),
        // username uses 13pt semibold (one line), category badge uses 11pt
        // semibold + 2+2 padding (~16pt). Center-aligned stack → take the max.
        let titleLineHeight = FontManager.shared.font(size: 13, weight: .semibold).lineHeight
        let badgeHeight: CGFloat = hasCategory ? 18 : 0
        let headerTextHeight = max(titleLineHeight, badgeHeight)
        let headerHeight = max(avatarSize, headerTextHeight)

        return Self.discourseQuoteTopPadding
            + headerHeight
            + Self.discourseQuoteHeaderToContent
            + innerH
            + Self.discourseQuoteBottomPadding
    }

    /// 10 (top of container to header)
    private static let discourseQuoteTopPadding: CGFloat = 10
    /// 8 (header bottom to content top)
    private static let discourseQuoteHeaderToContent: CGFloat = 8
    /// 10 (content bottom to container bottom)
    private static let discourseQuoteBottomPadding: CGFloat = 10

    // MARK: - List

    /// Mirrors `ListRenderer`. Currently only handles the "all flat items"
    /// fast path that produces a single combined view; lists with nested
    /// non-paragraph blocks return nil (caller falls back to autosize).
    private static func listHeight(
        ordered: Bool,
        items: [CookedHTML.ListItem],
        config: NativeRenderConfig
    ) -> CGFloat? {
        // Match canRenderFlat from ListRenderer.
        let allFlat = items.allSatisfy { item in
            item.blocks.allSatisfy { block in
                if case .paragraph = block { return true }
                return false
            }
        }
        guard allFlat else { return nil }

        let indent: CGFloat = ordered ? 20 : 12
        let combined = NSMutableAttributedString()
        for (index, item) in items.enumerated() {
            if index > 0 { combined.append(NSAttributedString(string: "\n")) }
            var allInlines: [InlineNode] = []
            for (i, block) in item.blocks.enumerated() {
                if case .paragraph(let inlines) = block {
                    if i > 0 { allInlines.append(.lineBreak) }
                    allInlines.append(contentsOf: inlines)
                }
            }
            combined.append(makeListBulletAttributedString(
                inlines: allInlines,
                ordered: ordered,
                index: index,
                indent: indent,
                config: config
            ))
        }
        return attributedTextHeight(combined, width: config.contentWidth)
    }

    /// Mirrors `ListRenderer.makeBulletedAttributedString` so the height
    /// calculation accounts for the bullet prefix, indent, and per-line spacing.
    private static func makeListBulletAttributedString(
        inlines: [InlineNode],
        ordered: Bool,
        index: Int,
        indent: CGFloat,
        config: NativeRenderConfig
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 4
        paragraphStyle.lineSpacing = config.baseFont.pointSize * 0.2
        paragraphStyle.headIndent = indent
        paragraphStyle.firstLineHeadIndent = 0
        paragraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: indent, options: [:])]
        paragraphStyle.defaultTabInterval = indent

        let result = NSMutableAttributedString()
        let bullet = ordered ? "\(index + 1).\t" : "\u{2022}\t"
        result.append(NSAttributedString(string: bullet, attributes: [
            .font: config.baseFont,
            .foregroundColor: config.baseColor,
            .paragraphStyle: paragraphStyle,
        ]))

        if !inlines.isEmpty {
            result.append(inlines.attributedString(config: config.attributedStringConfig))
        }

        result.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: result.length)
        )
        return result
    }

    // MARK: - TextKit Helpers

    /// Computes the rendered height of an attributed string at a fixed width.
    /// Uses `boundingRect`'s TextKit path which matches both `UILabel` and
    /// `LinkTextView` (the latter is configured with `lineFragmentPadding = 0`
    /// and `textContainerInset = .zero` in `ParagraphRenderer.makeTextView`).
    ///
    /// Safe to call from any thread — each invocation builds its own
    /// `NSStringDrawingContext`.
    private static func attributedTextHeight(_ attr: NSAttributedString, width: CGFloat) -> CGFloat {
        guard attr.length > 0, width > 0 else { return 0 }
        let bounds = attr.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(bounds.height)
    }
}
