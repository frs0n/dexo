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
            codeBackgroundColor: codeBackgroundColor
        )
    }

    static func `default`(contentWidth: CGFloat, baseURL: String? = nil) -> NativeRenderConfig {
        NativeRenderConfig(
            baseFont: .systemFont(ofSize: 16),
            baseColor: .label,
            linkColor: .link,
            codeFont: .monospacedSystemFont(ofSize: 15, weight: .regular),
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
        pollProvider: ((String) -> (poll: DiscourseTopicDetail.Poll, votedOptionIds: Set<String>, post: DiscourseTopicDetail.Post)?)? = nil
    ) -> [UIView] {
        let blocks = annotatedBlocks.map { annotated -> ContentBlock? in
            if case .poll(let name) = annotated.block, pollProvider != nil {
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
               let pollData = pollProvider?(name) {
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

            // Combine consecutive paragraphs into a single UITextView
            if case .paragraph(let firstInlines) = annotated.block {
                var j = i + 1
                while j < annotatedBlocks.count, case .paragraph = annotatedBlocks[j].block {
                    j += 1
                }
                if j > i + 1 {
                    // Multiple consecutive paragraphs — merge into one view
                    let merged = mergeParagraphs(annotatedBlocks[i..<j], config: config)
                    views.append(ParagraphRenderer.makeTextView(attributedText: merged, config: config))
                } else {
                    views.append(ParagraphRenderer.render(annotated.block, config: config, delegate: delegate))
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
