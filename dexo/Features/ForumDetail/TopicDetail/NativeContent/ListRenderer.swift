import CookedHTML
import UIKit

enum ListRenderer: BlockRenderer {
    static func canRender(_ block: ContentBlock) -> Bool {
        if case .list = block { return true }
        return false
    }

    static func render(_ block: ContentBlock, config: NativeRenderConfig, delegate: PostCellDelegate?) -> UIView {
        guard case .list(let ordered, let items) = block else { return UIView() }

        let result = NSMutableAttributedString()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 4
        paragraphStyle.headIndent = 12
        paragraphStyle.firstLineHeadIndent = 0

        if ordered {
            paragraphStyle.headIndent = 20
            let tabStop = NSTextTab(textAlignment: .left, location: 20, options: [:])
            paragraphStyle.tabStops = [tabStop]
            paragraphStyle.defaultTabInterval = 20
        } else {
            paragraphStyle.headIndent = 12
            let tabStop = NSTextTab(textAlignment: .left, location: 12, options: [:])
            paragraphStyle.tabStops = [tabStop]
            paragraphStyle.defaultTabInterval = 12
        }

        for (index, item) in items.enumerated() {
            let bullet: String
            if ordered {
                bullet = "\(index + 1).\t"
            } else {
                bullet = "\u{2022}\t"
            }
            let itemStart = result.length

            let bulletAttr = NSAttributedString(string: bullet, attributes: [
                .font: config.baseFont,
                .foregroundColor: config.baseColor,
                .paragraphStyle: paragraphStyle,
            ])
            result.append(bulletAttr)

            let itemAttr = item.content.attributedString(config: config.attributedStringConfig)
            result.append(itemAttr)

            if index < items.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }

            let itemEnd = result.length
            result.addAttribute(
                .paragraphStyle,
                value: paragraphStyle,
                range: NSRange(location: itemStart, length: itemEnd - itemStart)
            )
        }

        let textView = LinkTextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.backgroundColor = .clear
        textView.dataDetectorTypes = []
        textView.attributedText = result
        textView.linkTextAttributes = [
            .foregroundColor: config.linkColor,
        ]
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }
}
