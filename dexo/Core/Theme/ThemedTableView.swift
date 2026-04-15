import UIKit

/// A UITableView subclass that automatically applies the current theme's
/// background color to itself and all visible cells on every layout pass.
class ThemedTableView: UITableView {
    override func layoutSubviews() {
        super.layoutSubviews()
        let theme = ThemeManager.shared
        let isGrouped = style == .insetGrouped || style == .grouped
        let newBG = isGrouped ? theme.backgroundColor : theme.cardBackgroundColor
        if backgroundColor != newBG { backgroundColor = newBG }
        let cellColor = theme.cardBackgroundColor
        let selectionColor = theme.accentColor.withAlphaComponent(0.15)
        for cell in visibleCells {
            if cell.backgroundColor != cellColor {
                cell.backgroundColor = cellColor
            }
            if cell.selectionStyle != .none, cell.selectedBackgroundView == nil {
                let bg = UIView()
                bg.backgroundColor = selectionColor
                cell.selectedBackgroundView = bg
            }
        }
    }
}
