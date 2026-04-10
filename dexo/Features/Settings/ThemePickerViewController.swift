import UIKit

final class ThemePickerViewController: ObservableViewController {
    override var backgroundStyle: BackgroundStyle { .grouped }

    private let themeManager = ThemeManager.shared
    private let settings = AppSettings.shared

    private lazy var tableView: UITableView = {
        let tv = ThemedTableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.dataSource = self
        tv.delegate = self
        tv.register(ThemePresetCell.self, forCellReuseIdentifier: ThemePresetCell.reuseId)
        return tv
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "settings.theme")

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func updateUI() {
        tableView.backgroundColor = themeManager.backgroundColor
        tableView.reloadData()
    }

    // MARK: - Sections

    private enum Section: Int, CaseIterable {
        case presets
        case custom
    }

    private var customSchemes: [CustomThemeScheme] {
        settings.customThemeSchemes
    }
}

// MARK: - UITableViewDataSource

extension ThemePickerViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .presets: return ThemeDefinition.presets.count
        case .custom: return customSchemes.count + 1 // +1 for "Add Custom Theme"
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .presets: return String(localized: "theme.section.presets")
        case .custom: return String(localized: "theme.section.custom")
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .presets:
            let cell = tableView.dequeueReusableCell(withIdentifier: ThemePresetCell.reuseId, for: indexPath) as! ThemePresetCell
            let theme = ThemeDefinition.presets[indexPath.row]
            let isSelected = settings.selectedThemeId == theme.id
            cell.configure(with: theme, isSelected: isSelected)
            return cell

        case .custom:
            let schemes = customSchemes
            if indexPath.row < schemes.count {
                let cell = tableView.dequeueReusableCell(withIdentifier: ThemePresetCell.reuseId, for: indexPath) as! ThemePresetCell
                let scheme = schemes[indexPath.row]
                let themeDef = scheme.toThemeDefinition()
                let isSelected = settings.selectedThemeId == themeDef.id
                cell.configure(with: themeDef, isSelected: isSelected)
                return cell
            } else {
                let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                cell.textLabel?.text = String(localized: "theme.add_custom")
                cell.textLabel?.textColor = themeManager.accentColor
                cell.imageView?.image = UIImage(systemName: "plus.circle.fill")
                cell.imageView?.tintColor = themeManager.accentColor
                cell.backgroundColor = themeManager.cardBackgroundColor
                return cell
            }
        }
    }
}

// MARK: - UITableViewDelegate

extension ThemePickerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Section(rawValue: indexPath.section)! {
        case .presets:
            let theme = ThemeDefinition.presets[indexPath.row]
            themeManager.selectTheme(id: theme.id)

        case .custom:
            let schemes = customSchemes
            if indexPath.row < schemes.count {
                let scheme = schemes[indexPath.row]
                themeManager.selectTheme(id: "custom_\(scheme.id)")
            } else {
                let vc = CustomThemeViewController(scheme: nil)
                navigationController?.pushViewController(vc, animated: true)
            }
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard Section(rawValue: indexPath.section) == .custom else { return nil }
        let schemes = customSchemes
        guard indexPath.row < schemes.count else { return nil }

        let scheme = schemes[indexPath.row]

        let edit = UIContextualAction(style: .normal, title: String(localized: "theme.action.edit")) { [weak self] _, _, completion in
            let vc = CustomThemeViewController(scheme: scheme)
            self?.navigationController?.pushViewController(vc, animated: true)
            completion(true)
        }
        edit.backgroundColor = .systemBlue

        let delete = UIContextualAction(style: .destructive, title: String(localized: "theme.action.delete")) { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            self.settings.deleteCustomThemeScheme(id: scheme.id)
            if self.settings.selectedThemeId == "custom_\(scheme.id)" {
                self.themeManager.selectTheme(id: "default")
            }
            self.themeManager.notifyChange()
            completion(true)
        }

        return UISwipeActionsConfiguration(actions: [delete, edit])
    }
}

// MARK: - Preset Cell

private final class ThemePresetCell: UITableViewCell {
    static let reuseId = "ThemePresetCell"

    private let nameLabel = UILabel()
    private let colorsStack = UIStackView()
    private let lightAccentDot = UIView()
    private let darkAccentDot = UIView()
    private let lightBgDot = UIView()
    private let darkBgDot = UIView()
    private let lightCardDot = UIView()
    private let darkCardDot = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        let dots = [lightAccentDot, darkAccentDot, lightBgDot, darkBgDot, lightCardDot, darkCardDot]
        for dot in dots {
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.layer.cornerRadius = 12
            dot.layer.borderWidth = 1
            dot.layer.borderColor = UIColor.separator.cgColor
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 24),
                dot.heightAnchor.constraint(equalToConstant: 24),
            ])
        }

        colorsStack.axis = .horizontal
        colorsStack.spacing = 6
        colorsStack.translatesAutoresizingMaskIntoConstraints = false
        for dot in dots { colorsStack.addArrangedSubview(dot) }

        nameLabel.font = .systemFont(ofSize: 16)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(nameLabel)
        contentView.addSubview(colorsStack)

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            colorsStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),
            colorsStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
        ])
    }

    func configure(with theme: ThemeDefinition, isSelected: Bool) {
        nameLabel.text = theme.name
        lightAccentDot.backgroundColor = UIColor(hex: theme.lightAccentHex)
        darkAccentDot.backgroundColor = UIColor(hex: theme.darkAccentHex)
        lightBgDot.backgroundColor = UIColor(hex: theme.lightBackgroundHex)
        darkBgDot.backgroundColor = UIColor(hex: theme.darkBackgroundHex)
        lightCardDot.backgroundColor = UIColor(hex: theme.lightCardBackgroundHex)
        darkCardDot.backgroundColor = UIColor(hex: theme.darkCardBackgroundHex)
        accessoryType = isSelected ? .checkmark : .none
    }
}

// MARK: - Custom Theme ViewController

final class CustomThemeViewController: ObservableViewController {
    override var backgroundStyle: BackgroundStyle { .grouped }

    private let themeManager = ThemeManager.shared
    private let settings = AppSettings.shared
    private var scheme: CustomThemeScheme
    private let isNewScheme: Bool

    init(scheme: CustomThemeScheme?) {
        if let scheme {
            self.scheme = scheme
            self.isNewScheme = false
        } else {
            self.scheme = CustomThemeScheme()
            self.isNewScheme = true
        }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private lazy var tableView: UITableView = {
        let tv = ThemedTableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.dataSource = self
        tv.delegate = self
        return tv
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = isNewScheme
            ? String(localized: "theme.add_custom")
            : String(localized: "theme.edit_custom")

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "theme.save"),
            style: .done,
            target: self,
            action: #selector(saveTapped)
        )
    }

    override func loadView() {
        super.loadView()
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func updateUI() {
        tableView.backgroundColor = themeManager.backgroundColor
        tableView.reloadData()
    }

    @objc private func saveTapped() {
        if scheme.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scheme.name = String(localized: "theme.custom")
        }
        settings.saveCustomThemeScheme(scheme)
        themeManager.selectTheme(id: "custom_\(scheme.id)")
        navigationController?.popViewController(animated: true)
    }

    // MARK: - Data

    private enum Section: Int, CaseIterable {
        case name
        case light
        case dark
    }

    private enum ColorRow: Int, CaseIterable {
        case accent
        case background
        case cardBackground
    }

    private func rowTitle(_ row: ColorRow) -> String {
        switch row {
        case .accent: return String(localized: "theme.color.accent")
        case .background: return String(localized: "theme.color.background")
        case .cardBackground: return String(localized: "theme.color.card_background")
        }
    }

    private func currentHex(section: Section, row: ColorRow) -> String {
        switch (section, row) {
        case (.light, .accent): return scheme.lightAccentHex
        case (.light, .background): return scheme.lightBackgroundHex
        case (.light, .cardBackground): return scheme.lightCardBackgroundHex
        case (.dark, .accent): return scheme.darkAccentHex
        case (.dark, .background): return scheme.darkBackgroundHex
        case (.dark, .cardBackground): return scheme.darkCardBackgroundHex
        default: return "007AFF"
        }
    }

    private func setHex(_ hex: String, section: Section, row: ColorRow) {
        switch (section, row) {
        case (.light, .accent): scheme.lightAccentHex = hex
        case (.light, .background): scheme.lightBackgroundHex = hex
        case (.light, .cardBackground): scheme.lightCardBackgroundHex = hex
        case (.dark, .accent): scheme.darkAccentHex = hex
        case (.dark, .background): scheme.darkBackgroundHex = hex
        case (.dark, .cardBackground): scheme.darkCardBackgroundHex = hex
        default: break
        }
        tableView.reloadData()
    }
}

// MARK: - UITableViewDataSource

extension CustomThemeViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .name: return 1
        case .light, .dark: return ColorRow.allCases.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .name: return String(localized: "theme.section.name")
        case .light: return String(localized: "theme.section.light")
        case .dark: return String(localized: "theme.section.dark")
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = Section(rawValue: indexPath.section)!

        if section == .name {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.backgroundColor = themeManager.cardBackgroundColor

            let textField = UITextField()
            textField.placeholder = String(localized: "theme.name_placeholder")
            textField.text = scheme.name
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.clearButtonMode = .whileEditing
            textField.addAction(UIAction { [weak self] action in
                let tf = action.sender as! UITextField
                self?.scheme.name = tf.text ?? ""
            }, for: .editingChanged)

            cell.contentView.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                textField.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
                textField.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
                textField.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8),
                textField.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
            ])
            cell.selectionStyle = .none
            return cell
        }

        let row = ColorRow(rawValue: indexPath.row)!
        let hex = currentHex(section: section, row: row)

        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = rowTitle(row)
        cell.detailTextLabel?.text = "#\(hex)"
        cell.detailTextLabel?.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        cell.backgroundColor = themeManager.cardBackgroundColor

        let colorView = UIView(frame: CGRect(x: 0, y: 0, width: 28, height: 28))
        colorView.backgroundColor = UIColor(hex: hex)
        colorView.layer.cornerRadius = 14
        colorView.layer.borderWidth = 1
        colorView.layer.borderColor = UIColor.separator.cgColor
        cell.accessoryView = colorView

        return cell
    }
}

// MARK: - UITableViewDelegate

extension CustomThemeViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let section = Section(rawValue: indexPath.section)!
        guard section != .name else { return }

        let row = ColorRow(rawValue: indexPath.row)!
        let hex = currentHex(section: section, row: row)

        let picker = UIColorPickerViewController()
        picker.selectedColor = UIColor(hex: hex) ?? .systemBlue
        picker.supportsAlpha = true
        picker.title = rowTitle(row)
        picker.delegate = self
        picker.view.tag = indexPath.section * 100 + indexPath.row
        present(picker, animated: true)
    }
}

// MARK: - UIColorPickerViewControllerDelegate

extension CustomThemeViewController: UIColorPickerViewControllerDelegate {
    func colorPickerViewController(_ viewController: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
        guard !continuously else { return }
        let tag = viewController.view.tag
        let section = Section(rawValue: tag / 100)!
        let row = ColorRow(rawValue: tag % 100)!

        setHex(color.hexString, section: section, row: row)
    }
}
