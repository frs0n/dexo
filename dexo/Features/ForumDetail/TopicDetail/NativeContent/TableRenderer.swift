import CookedHTML
import UIKit

enum TableRenderer: BlockRenderer {
    static func canRender(_ block: ContentBlock) -> Bool {
        if case .table = block { return true }
        return false
    }

    static func render(_ block: ContentBlock, config: NativeRenderConfig, delegate: PostCellDelegate?) -> UIView {
        guard case .table(let headers, let rows) = block else { return UIView() }

        let columnCount = max(
            headers.count,
            rows.map(\.count).max() ?? 0
        )
        guard columnCount > 0 else { return UIView() }

        let cellPaddingV: CGFloat = 8
        let cellPaddingH: CGFloat = 12
        let separatorColor = UIColor.separator

        // MARK: - Measure natural column widths

        func makeAttrString(for inlines: [InlineNode], bold: Bool) -> NSAttributedString {
            if bold {
                let boldConfig = AttributedStringConfig(
                    baseFont: config.baseFont.withTraits(.traitBold),
                    baseColor: config.baseColor,
                    linkColor: config.linkColor,
                    codeFont: config.codeFont,
                    codeBackgroundColor: config.codeBackgroundColor
                )
                return inlines.attributedString(config: boldConfig)
            } else {
                return inlines.attributedString(config: config.attributedStringConfig)
            }
        }

        // Build attributed strings, inline nodes, and measure natural widths per column
        var attrGrid: [[NSAttributedString]] = []
        var inlinesGrid: [[[InlineNode]]] = []
        var columnMaxWidths: [CGFloat] = Array(repeating: 0, count: columnCount)

        func appendRow(cells: [[InlineNode]], bold: Bool) {
            var attrRow: [NSAttributedString] = []
            var inlinesRow: [[InlineNode]] = []
            for col in 0..<columnCount {
                let inlines = col < cells.count ? cells[col] : []
                let attr = makeAttrString(for: inlines, bold: bold)
                let imageInfo = findPrimaryImage(in: inlines)

                let naturalWidth: CGFloat
                if let img = imageInfo, let w = img.width, w > 0 {
                    naturalWidth = CGFloat(w) + cellPaddingH * 2
                } else {
                    let textWidth = ceil(attr.boundingRect(
                        with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin],
                        context: nil
                    ).width)
                    naturalWidth = textWidth + cellPaddingH * 2
                }

                columnMaxWidths[col] = max(columnMaxWidths[col], naturalWidth)
                attrRow.append(attr)
                inlinesRow.append(inlines)
            }
            attrGrid.append(attrRow)
            inlinesGrid.append(inlinesRow)
        }

        if !headers.isEmpty {
            appendRow(cells: headers, bold: true)
        }
        for row in rows {
            appendRow(cells: row, bold: false)
        }

        // MARK: - Water-filling column width allocation

        let availableWidth = max(config.contentWidth, CGFloat(columnCount) * 40)
        var columnWidths = Array(repeating: CGFloat(0), count: columnCount)
        var flexibleCols = Set(0..<columnCount)
        var remainingWidth = availableWidth

        var changed = true
        while changed {
            changed = false
            guard !flexibleCols.isEmpty else { break }
            let fairShare = remainingWidth / CGFloat(flexibleCols.count)
            for col in flexibleCols {
                if columnMaxWidths[col] <= fairShare {
                    columnWidths[col] = columnMaxWidths[col]
                    remainingWidth -= columnMaxWidths[col]
                    flexibleCols.remove(col)
                    changed = true
                }
            }
        }

        if !flexibleCols.isEmpty {
            let flexTotal = flexibleCols.map({ columnMaxWidths[$0] }).reduce(0, +)
            for col in flexibleCols {
                if flexTotal > 0 {
                    columnWidths[col] = remainingWidth * (columnMaxWidths[col] / flexTotal)
                } else {
                    columnWidths[col] = remainingWidth / CGFloat(flexibleCols.count)
                }
            }
        }

        // Convert to multipliers; last column has no multiplier — it fills remaining space.
        let totalAssigned = columnWidths.reduce(0, +)
        let ratios: [CGFloat] = columnWidths.map {
            totalAssigned > 0 ? $0 / totalAssigned : 1 / CGFloat(columnCount)
        }

        // Compute actual column widths in points for image sizing
        let columnWidthsPx = ratios.map { $0 * availableWidth }

        // MARK: - Cell factories

        func makeTextCell(attr: NSAttributedString) -> UIView {
            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false

            let textView = LinkTextView()
            textView.isEditable = false
            textView.isScrollEnabled = false
            textView.textContainerInset = .zero
            textView.textContainer.lineFragmentPadding = 0
            textView.backgroundColor = .clear
            textView.dataDetectorTypes = []
            textView.linkTextAttributes = [.foregroundColor: config.linkColor]
            textView.attributedText = attr
            textView.translatesAutoresizingMaskIntoConstraints = false

            container.addSubview(textView)
            NSLayoutConstraint.activate([
                textView.topAnchor.constraint(equalTo: container.topAnchor, constant: cellPaddingV),
                textView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: cellPaddingH),
                textView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -cellPaddingH),
                textView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -cellPaddingV),
            ])

            return container
        }

        func makeImageCell(imageInfo: CellImageInfo, columnWidth: CGFloat) -> UIView {
            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false

            guard let url = URL(string: imageInfo.src) else { return container }

            let innerWidth = columnWidth - cellPaddingH * 2
            let hrefURL = imageInfo.href.flatMap { URL(string: $0) }

            // Scale dimensions so the image fills the cell width.
            // TappableImageContainer uses a 690px reference width, so we scale
            // the original dimensions to match that reference.
            let scaledWidth: Int?
            let scaledHeight: Int?
            if let w = imageInfo.width, let h = imageInfo.height, w > 0 {
                scaledWidth = 690
                scaledHeight = Int(690.0 * CGFloat(h) / CGFloat(w))
            } else {
                scaledWidth = nil
                scaledHeight = nil
            }

            let imageContainer = TappableImageContainer(
                url: url,
                width: scaledWidth,
                height: scaledHeight,
                containerWidth: innerWidth,
                href: hrefURL
            )
            imageContainer.delegate = delegate

            container.addSubview(imageContainer)
            NSLayoutConstraint.activate([
                imageContainer.topAnchor.constraint(equalTo: container.topAnchor, constant: cellPaddingV),
                imageContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: cellPaddingH),
                imageContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -cellPaddingH),
                imageContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -cellPaddingV),
            ])

            return container
        }

        func makeSeparator() -> UIView {
            let sep = UIView()
            sep.translatesAutoresizingMaskIntoConstraints = false
            sep.backgroundColor = separatorColor
            sep.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
            return sep
        }

        // MARK: - Assemble table

        let tableStack = UIStackView()
        tableStack.axis = .vertical
        tableStack.spacing = 0
        tableStack.translatesAutoresizingMaskIntoConstraints = false

        for (rowIndex, attrRow) in attrGrid.enumerated() {
            let inlinesRow = inlinesGrid[rowIndex]

            let cells: [UIView] = (0..<attrRow.count).map { col in
                let inlines = inlinesRow[col]
                if let imageInfo = findPrimaryImage(in: inlines) {
                    return makeImageCell(imageInfo: imageInfo, columnWidth: columnWidthsPx[col])
                } else {
                    return makeTextCell(attr: attrRow[col])
                }
            }

            // Use plain UIView instead of UIStackView to avoid constraint conflicts
            let rowView = UIView()
            rowView.translatesAutoresizingMaskIntoConstraints = false

            for (col, cell) in cells.enumerated() {
                rowView.addSubview(cell)

                cell.topAnchor.constraint(equalTo: rowView.topAnchor).isActive = true
                cell.bottomAnchor.constraint(equalTo: rowView.bottomAnchor).isActive = true

                if col == 0 {
                    cell.leadingAnchor.constraint(equalTo: rowView.leadingAnchor).isActive = true
                } else {
                    cell.leadingAnchor.constraint(equalTo: cells[col - 1].trailingAnchor).isActive = true
                }

                if col < columnCount - 1 {
                    // Fixed ratio for all columns except the last
                    cell.widthAnchor.constraint(equalTo: rowView.widthAnchor, multiplier: ratios[col]).isActive = true
                } else {
                    // Last column fills remaining space — no floating-point sum mismatch
                    cell.trailingAnchor.constraint(equalTo: rowView.trailingAnchor).isActive = true
                }
            }

            if rowIndex == 0 && !headers.isEmpty {
                rowView.backgroundColor = .secondarySystemBackground
            }

            tableStack.addArrangedSubview(rowView)

            if rowIndex < attrGrid.count - 1 {
                tableStack.addArrangedSubview(makeSeparator())
            }
        }

        // MARK: - Bordered container

        let borderedContainer = UIView()
        borderedContainer.translatesAutoresizingMaskIntoConstraints = false
        borderedContainer.layer.borderWidth = 1 / UIScreen.main.scale
        borderedContainer.layer.borderColor = separatorColor.cgColor
        borderedContainer.layer.cornerRadius = 4
        borderedContainer.clipsToBounds = true

        borderedContainer.addSubview(tableStack)
        NSLayoutConstraint.activate([
            tableStack.topAnchor.constraint(equalTo: borderedContainer.topAnchor),
            tableStack.leadingAnchor.constraint(equalTo: borderedContainer.leadingAnchor),
            tableStack.trailingAnchor.constraint(equalTo: borderedContainer.trailingAnchor),
            tableStack.bottomAnchor.constraint(equalTo: borderedContainer.bottomAnchor),
        ])

        return borderedContainer
    }

    // MARK: - Image Detection

    private struct CellImageInfo {
        let src: String
        let width: Int?
        let height: Int?
        let href: String?
    }

    /// Find a non-emoji image in a cell's inline nodes.
    private static func findPrimaryImage(in nodes: [InlineNode]) -> CellImageInfo? {
        for node in nodes {
            switch node {
            case .image(let src, _, let w, let h, let isEmoji):
                if !isEmoji && ((w ?? 0) > 80 || (h ?? 0) > 80) {
                    return CellImageInfo(src: src, width: w, height: h, href: nil)
                }
            case .link(let href, let children):
                if let img = findPrimaryImage(in: children) {
                    return CellImageInfo(src: img.src, width: img.width, height: img.height, href: href)
                }
            default:
                continue
            }
        }
        return nil
    }
}

// MARK: - UIFont + Traits Helper

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits)) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
