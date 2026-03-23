import UIKit

final class SettingsViewController: ObservableViewController {
    private let settings = AppSettings.shared

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.dataSource = self
        tv.delegate = self
        return tv
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = .systemGroupedBackground

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func updateUI() {
        tableView.reloadData()
    }

    // MARK: - Rows

    private enum Section: Int, CaseIterable {
        case appearance
        case network
    }

    private func networkRows() -> [NetworkRow] {
        var rows: [NetworkRow] = [.dohToggle]
        if settings.dohEnabled {
            rows.append(.dohProvider)
            if settings.dohProvider == .custom {
                rows.append(.dohCustomURL)
            }
        }
        return rows
    }

    private enum NetworkRow {
        case dohToggle
        case dohProvider
        case dohCustomURL
    }
}

// MARK: - UITableViewDataSource

extension SettingsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
//        Section.allCases.count
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .appearance: return 1
        case .network: return networkRows().count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .appearance: return "外观"
        case .network: return "网络"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .appearance:
            return makeAppearanceCell(tableView, indexPath: indexPath)
        case .network:
            let row = networkRows()[indexPath.row]
            switch row {
            case .dohToggle:
                return makeDohToggleCell(tableView, indexPath: indexPath)
            case .dohProvider:
                return makeDohProviderCell(tableView, indexPath: indexPath)
            case .dohCustomURL:
                return makeDohCustomURLCell(tableView, indexPath: indexPath)
            }
        }
    }

    // MARK: - Cell Factories

    private func makeAppearanceCell(_ tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = "深色模式"
        cell.detailTextLabel?.text = settings.appearanceMode.title
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private func makeDohToggleCell(_ tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = "DNS over HTTPS"
        cell.selectionStyle = .none
        let toggle = UISwitch()
        toggle.isOn = settings.dohEnabled
        toggle.addTarget(self, action: #selector(dohToggleChanged(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }

    private func makeDohProviderCell(_ tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = "提供商"
        cell.detailTextLabel?.text = settings.dohProvider.title
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private func makeDohCustomURLCell(_ tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = "自定义 URL"
        cell.detailTextLabel?.text = settings.dohCustomURL.isEmpty ? "未设置" : settings.dohCustomURL
        cell.detailTextLabel?.textColor = settings.dohCustomURL.isEmpty ? .placeholderText : .secondaryLabel
        cell.accessoryType = .disclosureIndicator
        return cell
    }
}

// MARK: - UITableViewDelegate

extension SettingsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Section(rawValue: indexPath.section)! {
        case .appearance:
            showAppearancePicker()
        case .network:
            let row = networkRows()[indexPath.row]
            switch row {
            case .dohProvider:
                showDohProviderPicker()
            case .dohCustomURL:
                showCustomURLInput()
            default:
                break
            }
        }
    }
}

// MARK: - Actions

extension SettingsViewController {
    @objc private func dohToggleChanged(_ sender: UISwitch) {
        settings.dohEnabled = sender.isOn
        if !sender.isOn {
            DoHResolver.shared.clearCache()
        }
        reloadNetworkSection()
    }

    private func reloadNetworkSection() {
        tableView.reloadSections(IndexSet(integer: Section.network.rawValue), with: .automatic)
    }

    private func showAppearancePicker() {
        let alert = UIAlertController(title: "深色模式", message: nil, preferredStyle: .actionSheet)
        for mode in AppSettings.AppearanceMode.allCases {
            let action = UIAlertAction(title: mode.title, style: .default) { [weak self] _ in
                self?.settings.appearanceMode = mode
                self?.tableView.reloadSections(IndexSet(integer: Section.appearance.rawValue), with: .none)
            }
            if mode == settings.appearanceMode {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func showDohProviderPicker() {
        let alert = UIAlertController(title: "DoH 提供商", message: nil, preferredStyle: .actionSheet)
        for provider in AppSettings.DoHProvider.allCases {
            let action = UIAlertAction(title: provider.title, style: .default) { [weak self] _ in
                self?.settings.dohProvider = provider
                DoHResolver.shared.clearCache()
                self?.reloadNetworkSection()
            }
            if provider == settings.dohProvider {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func showCustomURLInput() {
        let alert = UIAlertController(title: "自定义 DoH URL", message: "输入 DNS over HTTPS 服务器地址", preferredStyle: .alert)
        alert.addTextField { [weak self] textField in
            textField.text = self?.settings.dohCustomURL
            textField.placeholder = "https://example.com/dns-query"
            textField.keyboardType = .URL
            textField.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            if let url = alert.textFields?.first?.text {
                self?.settings.dohCustomURL = url
                DoHResolver.shared.clearCache()
                self?.reloadNetworkSection()
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
}
