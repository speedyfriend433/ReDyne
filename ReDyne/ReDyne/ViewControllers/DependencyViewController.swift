import UIKit

class DependencyViewController: UIViewController {
    
    // MARK: - UI Elements
    
    private let segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["All", "System", "Custom", "Frameworks"])
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = 0
        return control
    }()
    
    private let statsView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.1
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 4
        return view
    }()
    
    private let totalLibsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 2
        return label
    }()
    
    private let systemLibsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 2
        return label
    }()
    
    private let customLibsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 2
        return label
    }()
    
    private let searchBar: UISearchBar = {
        let search = UISearchBar()
        search.translatesAutoresizingMaskIntoConstraints = false
        search.placeholder = "Search dependencies..."
        search.searchBarStyle = .minimal
        return search
    }()
    
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = Constants.Colors.primaryBackground
        table.register(DependencyCell.self, forCellReuseIdentifier: "Cell")
        return table
    }()
    
    // MARK: - Properties
    
    private let dependencyAnalysis: DependencyAnalysis
    private var displayedLibraries: [LinkedLibrary] = []
    private var searchText: String = ""
    
    // MARK: - Initialization
    
    init(dependencyAnalysis: DependencyAnalysis) {
        self.dependencyAnalysis = dependencyAnalysis
        self.displayedLibraries = dependencyAnalysis.libraries.sortedByName()
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Dependencies"
        view.backgroundColor = Constants.Colors.primaryBackground
        
        setupUI()
        setupActions()
        setupTableView()
        updateStats()
        filterLibraries()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.addSubview(searchBar)
        view.addSubview(segmentedControl)
        view.addSubview(statsView)
        view.addSubview(tableView)
        
        let statsStackView = UIStackView(arrangedSubviews: [totalLibsLabel, systemLibsLabel, customLibsLabel])
        statsStackView.translatesAutoresizingMaskIntoConstraints = false
        statsStackView.axis = .horizontal
        statsStackView.distribution = .fillEqually
        statsStackView.spacing = 8
        statsView.addSubview(statsStackView)
        
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            segmentedControl.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            statsView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 12),
            statsView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statsView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statsView.heightAnchor.constraint(equalToConstant: 70),
            
            statsStackView.topAnchor.constraint(equalTo: statsView.topAnchor, constant: 12),
            statsStackView.leadingAnchor.constraint(equalTo: statsView.leadingAnchor, constant: 12),
            statsStackView.trailingAnchor.constraint(equalTo: statsView.trailingAnchor, constant: -12),
            statsStackView.bottomAnchor.constraint(equalTo: statsView.bottomAnchor, constant: -12),
            
            tableView.topAnchor.constraint(equalTo: statsView.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupActions() {
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        searchBar.delegate = self
    }
    
    // MARK: - Data Management
    
    private func updateStats() {
        let totalAttr = NSMutableAttributedString()
        totalAttr.append(NSAttributedString(string: "\(dependencyAnalysis.totalLibraries)\n", attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 24, weight: .bold),
            .foregroundColor: Constants.Colors.accentColor
        ]))
        totalAttr.append(NSAttributedString(string: "Total", attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]))
        totalLibsLabel.attributedText = totalAttr
        
        let systemAttr = NSMutableAttributedString()
        systemAttr.append(NSAttributedString(string: "\(dependencyAnalysis.systemLibraries.count)\n", attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor.systemBlue
        ]))
        systemAttr.append(NSAttributedString(string: "System", attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]))
        systemLibsLabel.attributedText = systemAttr
        
        let customAttr = NSMutableAttributedString()
        customAttr.append(NSAttributedString(string: "\(dependencyAnalysis.customLibraries.count)\n", attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor.systemPurple
        ]))
        customAttr.append(NSAttributedString(string: "Custom", attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]))
        customLibsLabel.attributedText = customAttr
    }
    
    @objc private func segmentChanged() {
        filterLibraries()
    }
    
    private func filterLibraries() {
        var filtered: [LinkedLibrary]
        
        switch segmentedControl.selectedSegmentIndex {
        case 1:
            filtered = dependencyAnalysis.systemLibraries
        case 2:
            filtered = dependencyAnalysis.customLibraries
        case 3:
            filtered = dependencyAnalysis.frameworks
        default:
            filtered = dependencyAnalysis.libraries
        }
        
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.path.lowercased().contains(searchText.lowercased()) ||
                $0.name.lowercased().contains(searchText.lowercased())
            }
        }
        
        displayedLibraries = filtered.sortedByName()
        tableView.reloadData()
    }
}

// MARK: - UITableViewDataSource

extension DependencyViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return displayedLibraries.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! DependencyCell
        let library = displayedLibraries[indexPath.row]
        cell.configure(with: library)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension DependencyViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let library = displayedLibraries[indexPath.row]
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let copyPath = UIAction(title: "Copy Path", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.string = library.path
            }
            
            let copyName = UIAction(title: "Copy Name", image: UIImage(systemName: "textformat")) { _ in
                UIPasteboard.general.string = library.name
            }
            
            let copyVersion = UIAction(title: "Copy Version", image: UIImage(systemName: "number")) { _ in
                UIPasteboard.general.string = library.currentVersionString
            }
            
            return UIMenu(title: library.name, children: [copyPath, copyName, copyVersion])
        }
    }
}

// MARK: - UISearchBarDelegate

extension DependencyViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.searchText = searchText
        filterLibraries()
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - Dependency Cell

class DependencyCell: UITableViewCell {
    
    private let iconLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 24)
        return label
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.numberOfLines = 0
        return label
    }()
    
    private let pathLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()
    
    private let versionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .systemGreen
        return label
    }()
    
    private let timestampLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11, weight: .regular)
        label.textColor = .tertiaryLabel
        return label
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        contentView.addSubview(iconLabel)
        contentView.addSubview(nameLabel)
        contentView.addSubview(pathLabel)
        contentView.addSubview(versionLabel)
        contentView.addSubview(timestampLabel)
        
        NSLayoutConstraint.activate([
            iconLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            iconLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            iconLabel.widthAnchor.constraint(equalToConstant: 28),
            
            nameLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 8),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            
            pathLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            pathLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            pathLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            
            versionLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            versionLabel.topAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 6),
            
            timestampLabel.leadingAnchor.constraint(equalTo: versionLabel.trailingAnchor, constant: 12),
            timestampLabel.centerYAnchor.constraint(equalTo: versionLabel.centerYAnchor),
            timestampLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12),
            timestampLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }
    
    func configure(with library: LinkedLibrary) {
        if library.framework != nil {
            iconLabel.text = "📦"
        } else if library.isSystemLibrary {
            iconLabel.text = "⚙️"
        } else {
            iconLabel.text = "📚"
        }
        
        if let framework = library.framework {
            nameLabel.text = "\(framework).framework"
        } else {
            nameLabel.text = library.name
        }
        
        pathLabel.text = library.path
        
        let compatStr = library.compatibilityVersion > 0 ? " (compat: \(library.compatibilityVersionString))" : ""
        versionLabel.text = "v\(library.currentVersionString)\(compatStr)"
        
        if library.timestamp > 0 {
            timestampLabel.text = "🕐 \(library.timestampString)"
        } else {
            timestampLabel.text = ""
        }
        
        if library.isWeak {
            nameLabel.textColor = .systemOrange
        } else if library.isReexport {
            nameLabel.textColor = .systemPurple
        } else {
            nameLabel.textColor = .label
        }
    }
}

