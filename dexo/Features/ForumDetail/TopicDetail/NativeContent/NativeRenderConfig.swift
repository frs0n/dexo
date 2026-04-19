import CookedHTML
import UIKit

struct NativeRenderConfig {
    let baseFont: UIFont
    let baseColor: UIColor
    let linkColor: UIColor
    let codeFont: UIFont
    let codeBackgroundColor: UIColor
    let contentWidth: CGFloat
    let baseURL: String?

    var attributedStringConfig: AttributedStringConfig {
        AttributedStringConfig(
            baseFont: baseFont,
            baseColor: baseColor,
            linkColor: linkColor,
            codeFont: codeFont,
            codeBackgroundColor: codeBackgroundColor,
            lineSpacing: baseFont.pointSize * 0.35
        )
    }

    static func `default`(contentWidth: CGFloat, baseURL: String? = nil) -> NativeRenderConfig {
        let fm = FontManager.shared
        return NativeRenderConfig(
            baseFont: fm.font(size: 16),
            baseColor: .label,
            linkColor: .link,
            codeFont: fm.monospacedFont(size: 15),
            codeBackgroundColor: ThemeManager.shared.codeBackgroundColor,
            contentWidth: contentWidth,
            baseURL: baseURL
        )
    }
}

// MARK: - BlockRenderer Protocol

protocol BlockRenderer {
    static func canRender(_ block: ContentBlock) -> Bool
    static func render(_ block: ContentBlock, config: NativeRenderConfig, delegate: PostCellDelegate?) -> UIView
}

// MARK: - NativeContentRenderer

enum NativeContentRenderer {
    /// Vertical spacing between blocks in `PostNativeCell.contentStackView`.
    /// Mirror this in any precomputed-height calculator so summed heights
    /// match the rendered layout.
    static let contentStackSpacing: CGFloat = 8

    static let renderers: [BlockRenderer.Type] = [
        ParagraphRenderer.self,
        HeadingRenderer.self,
        DividerRenderer.self,
        ListRenderer.self,
        BlockquoteRenderer.self,
        ImageRenderer.self,
        CodeBlockRenderer.self,
        DiscourseQuoteRenderer.self,
        DetailsRenderer.self,
        SpoilerRenderer.self,
        OneboxRenderer.self,
        VideoRenderer.self,
        TableRenderer.self,
        PollRenderer.self,
    ]

    static func renderBlocks(
        _ blocks: [ContentBlock],
        config: NativeRenderConfig,
        delegate: PostCellDelegate?
    ) -> [UIView] {
        renderBlockList(blocks, config: config, delegate: delegate)
    }

    static func renderBlocks(
        _ annotatedBlocks: [AnnotatedBlock],
        config: NativeRenderConfig,
        delegate: PostCellDelegate?,
        pollProvider: ((String) -> (poll: DiscourseTopicDetail.Poll, votedOptionIds: Set<String>, post: DiscourseTopicDetail.Post)?)? = nil,
        precomputedBlockHeights: [CGFloat]? = nil
    ) -> [UIView] {
        _ = annotatedBlocks.map { annotated -> ContentBlock? in
            if case .poll(_) = annotated.block, pollProvider != nil {
                return annotated.block // handled separately below
            }
            return annotated.block
        }

        var views: [UIView] = []
        var i = 0
        while i < annotatedBlocks.count {
            let annotated = annotatedBlocks[i]

            // Poll blocks need extra data from the Post model
            if case .poll(let name) = annotated.block,
               let pollData = pollProvider?(name)
            {
                views.append(PollRenderer.render(
                    poll: pollData.poll,
                    votedOptionIds: pollData.votedOptionIds,
                    post: pollData.post,
                    containerWidth: config.contentWidth,
                    delegate: delegate
                ))
                i += 1
                continue
            }

            // Combine consecutive paragraphs into a single view.
            // When the paragraph run contains no link / mention / hashtag / spoiler /
            // inline-image, we can use a plain UILabel instead of a LinkTextView —
            // UILabel is ~5–10× cheaper to instantiate than UITextView.
            if case .paragraph(let firstInlines) = annotated.block {
                var j = i + 1
                while j < annotatedBlocks.count, case .paragraph = annotatedBlocks[j].block {
                    j += 1
                }

                var needsInteractive = inlinesNeedTextView(firstInlines)
                if !needsInteractive, j > i + 1 {
                    for k in (i + 1)..<j {
                        if case .paragraph(let inl) = annotatedBlocks[k].block,
                           inlinesNeedTextView(inl)
                        {
                            needsInteractive = true
                            break
                        }
                    }
                }

                let attr: NSAttributedString
                if j > i + 1 {
                    attr = mergeParagraphs(annotatedBlocks[i..<j], config: config)
                } else {
                    attr = firstInlines.attributedString(config: config.attributedStringConfig)
                }

                if needsInteractive {
                    views.append(ParagraphRenderer.makeTextView(attributedText: attr, config: config))
                } else {
                    views.append(makeContentLabel(attributedText: attr))
                }
                i = j
                continue
            }

            for renderer in renderers where renderer.canRender(annotated.block) {
                views.append(renderer.render(annotated.block, config: config, delegate: delegate))
                break
            }
            i += 1
        }

        // Pin each block view to its precomputed height. Lets PostNativeCell
        // skip the systemLayoutSizeFitting → Core Text typesetting cascade
        // when measuring the cell — the contentStackView sums known heights
        // instead of asking each label/textView for its intrinsic content size.
        //
        // Length must match the view sequence (paragraph merging considered).
        // Mismatched lengths fall through to autosizing rather than crash.
        if let heights = precomputedBlockHeights, heights.count == views.count {
            for (view, h) in zip(views, heights) {
                let c = view.heightAnchor.constraint(equalToConstant: h)
                c.priority = .required
                c.isActive = true
            }
        }

        return views
    }

    /// Shared implementation for plain ContentBlock arrays (used by quote/details renderers).
    private static func renderBlockList(
        _ blocks: [ContentBlock],
        config: NativeRenderConfig,
        delegate: PostCellDelegate?
    ) -> [UIView] {
        blocks.compactMap { block in
            for renderer in renderers where renderer.canRender(block) {
                return renderer.render(block, config: config, delegate: delegate)
            }
            return nil
        }
    }

    /// Cheap UILabel for non-interactive attributed text (paragraphs/headings/table
    /// cells without links, mentions, hashtags, or spoilers). Inline `.image` attachments
    /// (emojis) are OK — `PostNativeCell.loadInlineImagesBatched` refreshes them after
    /// async loading by re-assigning `attributedText`.
    /// When `insets` is non-zero a `PaddedContentLabel` is used so callers can skip an
    /// extra wrapping `UIView` + layout constraints.
    static func makeContentLabel(attributedText: NSAttributedString, insets: UIEdgeInsets = .zero) -> UILabel {
        let label: UILabel
        if insets == .zero {
            label = UILabel()
        } else {
            let padded = PaddedContentLabel()
            padded.contentInsets = insets
            label = padded
        }
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = attributedText
        return label
    }

    /// True when inlines contain anything that requires a UITextView:
    /// - `.link`/`.mention`/`.mentionGroup`/`.hashtag` → need tap handling
    /// - `.spoiler` → need blur overlay + tap to reveal
    /// - `.image` → inline emoji attachments; UILabel's Core Text path doesn't render
    ///   `NSTextAttachment.bounds` reliably (especially with a negative baseline
    ///   offset), and async-loaded attachment images don't redraw cleanly on UILabel.
    ///   Keep these on UITextView so `textStorage.edited(.editedAttributes, …)` can
    ///   refresh the attachment in place.
    static func inlinesNeedTextView(_ inlines: [InlineNode]) -> Bool {
        for inline in inlines {
            switch inline {
            case .link, .mention, .mentionGroup, .hashtag, .spoiler, .image:
                return true
            case .text, .styledText, .code, .lineBreak:
                continue
            }
        }
        return false
    }

    /// Merge consecutive paragraph blocks into a single NSAttributedString with paragraph spacing.
    private static func mergeParagraphs<C: Collection>(
        _ blocks: C, config: NativeRenderConfig
    ) -> NSAttributedString where C.Element == AnnotatedBlock {
        let result = NSMutableAttributedString()
        for (offset, annotated) in blocks.enumerated() {
            guard case .paragraph(let inlines) = annotated.block else { continue }
            if offset > 0 {
                // Paragraph separator — gives visual spacing similar to stackView spacing
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: config.baseFont.withSize(8), // small font → ~8pt gap between paragraphs
                ]))
            }
            result.append(inlines.attributedString(config: config.attributedStringConfig))
        }
        return result
    }
}

// MARK: - PaddedContentLabel

/// UILabel with a configurable content inset — avoids having to wrap the label in a
/// container UIView + 4 layout constraints just to provide padding.
final class PaddedContentLabel: UILabel {
    var contentInsets: UIEdgeInsets = .zero

    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        size.width += contentInsets.left + contentInsets.right
        size.height += contentInsets.top + contentInsets.bottom
        return size
    }

    override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        let inner = bounds.inset(by: contentInsets)
        let fit = super.textRect(forBounds: inner, limitedToNumberOfLines: numberOfLines)
        // Reverse the inset so the label's overall size includes the padding.
        return fit.inset(by: UIEdgeInsets(
            top: -contentInsets.top,
            left: -contentInsets.left,
            bottom: -contentInsets.bottom,
            right: -contentInsets.right
        ))
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }
}
