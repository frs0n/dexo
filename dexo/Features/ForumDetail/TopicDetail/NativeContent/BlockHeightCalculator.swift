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
    /// including the inter-block spacing that mirrors
    /// `NativeContentRenderer.contentStackSpacing`. Returns `nil` if any block
    /// type doesn't yet support height precomputation.
    static func contentStackHeight(
        for annotatedBlocks: [AnnotatedBlock],
        config: NativeRenderConfig
    ) -> CGFloat? {
        guard let heights = perBlockHeights(annotatedBlocks: annotatedBlocks, config: config) else {
            return nil
        }
        if heights.isEmpty { return 0 }
        let spacing = NativeContentRenderer.contentStackSpacing
        return heights.reduce(0, +) + CGFloat(heights.count - 1) * spacing
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

        // Everything else: not yet supported. Caller falls back to autosize.
        case .heading,
             .codeBlock,
             .blockquote,
             .discourseQuote,
             .image,
             .onebox,
             .video,
             .list,
             .table,
             .details,
             .spoiler,
             .poll,
             .divider,
             .rawHTML:
            return nil
        }
    }

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
