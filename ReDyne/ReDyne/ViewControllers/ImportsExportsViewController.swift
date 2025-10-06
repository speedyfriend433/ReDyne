import UIKit

class ImportsExportsViewController: UIViewController {
    
    // MARK: - UI Elements
    
    private let segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Imports", "Exports", "Libraries"])
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
    
    private let statsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 14, weight: .medium)
        return label
    }()
    
    private let searchBar: UISearchBar = {
        let search = UISearchBar()
        search.translatesAutoresizingMaskIntoConstraints = false
        search.placeholder = "Search symbols..."
        search.searchBarStyle = .minimal
        return search
    }()
    
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = Constants.Colors.primaryBackground
        table.register(ImportExportCell.self, forCellReuseIdentifier: "Cell")
        return table
    }()
    
    // MARK: - Properties
    
    private let analysis: ImportExportAnalysis
    private var displayedImports: [ImportedSymbol] = []
    private var displayedExports: [ExportedSymbol] = []
    private var displayedLibraries: [String] = []
    private var searchText: String = ""
    
    // MARK: - Initialization
    
    init(analysis: ImportExportAnalysis) {
        self.analysis = analysis
        self.displayedImports = analysis.imports.sortedByName()
        self.displayedExports = analysis.exports.sortedByName()
        self.displayedLibraries = analysis.linkedLibraries.sorted()
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Imports & Exports"
        view.backgroundColor = Constants.Colors.primaryBackground
        
        setupUI()
        setupActions()
        setupTableView()
        updateStats()
        filterData()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.addSubview(searchBar)
        view.addSubview(segmentedControl)
        view.addSubview(statsView)
        view.addSubview(tableView)
        
        statsView.addSubview(statsLabel)
        
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
            statsView.heightAnchor.constraint(equalToConstant: 60),
            
            statsLabel.centerXAnchor.constraint(equalTo: statsView.centerXAnchor),
            statsLabel.centerYAnchor.constraint(equalTo: statsView.centerYAnchor),
            statsLabel.leadingAnchor.constraint(equalTo: statsView.leadingAnchor, constant: 16),
            statsLabel.trailingAnchor.constraint(equalTo: statsView.trailingAnchor, constant: -16),
            
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
        let attr = NSMutableAttributedString()
        
        switch segmentedControl.selectedSegmentIndex {
        case 0:
            attr.append(NSAttributedString(string: "\(displayedImports.count) imports", attributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: UIColor.label
            ]))
            if !searchText.isEmpty {
                attr.append(NSAttributedString(string: " (filtered from \(analysis.totalImports))", attributes: [
                    .font: UIFont.systemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: UIColor.secondaryLabel
                ]))
            }
            
        case 1:
            attr.append(NSAttributedString(string: "\(displayedExports.count) exports", attributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: UIColor.label
            ]))
            if !searchText.isEmpty {
                attr.append(NSAttributedString(string: " (filtered from \(analysis.totalExports))", attributes: [
                    .font: UIFont.systemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: UIColor.secondaryLabel
                ]))
            }
            
        case 2:
            attr.append(NSAttributedString(string: "\(displayedLibraries.count) linked libraries", attributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: UIColor.label
            ]))
            
        default:
            break
        }
        
        statsLabel.attributedText = attr
    }
    
    @objc private func segmentChanged() {
        filterData()
    }
    
    private func filterData() {
        switch segmentedControl.selectedSegmentIndex {
        case 0:
            if searchText.isEmpty {
                displayedImports = analysis.imports.sortedByName()
            } else {
                displayedImports = analysis.imports.filter {
                    $0.name.lowercased().contains(searchText.lowercased())
                }.sortedByName()
            }
            
        case 1:
            displayedExports = analysis.exports(matching: searchText)
            
        case 2:
            if searchText.isEmpty {
                displayedLibraries = analysis.linkedLibraries.sorted()
            } else {
                displayedLibraries = analysis.linkedLibraries.filter {
                    $0.lowercased().contains(searchText.lowercased())
                }.sorted()
            }
            
        default:
            break
        }
        
        updateStats()
        tableView.reloadData()
    }
}

// MARK: - UITableViewDataSource

extension ImportsExportsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch segmentedControl.selectedSegmentIndex {
        case 0: return displayedImports.count
        case 1: return displayedExports.count
        case 2: return displayedLibraries.count
        default: return 0
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! ImportExportCell
        
        switch segmentedControl.selectedSegmentIndex {
        case 0:
            let importSym = displayedImports[indexPath.row]
            cell.configure(withImport: importSym)
            
        case 1:
            let exportSym = displayedExports[indexPath.row]
            cell.configure(withExport: exportSym)
            
        case 2:
            let library = displayedLibraries[indexPath.row]
            cell.configure(withLibrary: library, importCount: analysis.imports(from: library).count)
            
        default:
            break
        }
        
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ImportsExportsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            var actions: [UIAction] = []
            
            switch self.segmentedControl.selectedSegmentIndex {
            case 0:
                let importSym = self.displayedImports[indexPath.row]
                actions.append(UIAction(title: "Copy Symbol Name", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = importSym.name
                })
                actions.append(UIAction(title: "Copy Address", image: UIImage(systemName: "number")) { _ in
                    UIPasteboard.general.string = String(format: "0x%llX", importSym.address)
                })
                
            case 1:
                let exportSym = self.displayedExports[indexPath.row]
                actions.append(UIAction(title: "Copy Symbol Name", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = exportSym.name
                })
                actions.append(UIAction(title: "Copy Address", image: UIImage(systemName: "number")) { _ in
                    UIPasteboard.general.string = String(format: "0x%llX", exportSym.address)
                })
                
            case 2: 
                let library = self.displayedLibraries[indexPath.row]
                actions.append(UIAction(title: "Copy Library Path", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = library
                })
                
            default:
                break
            }
            
            return UIMenu(children: actions)
        }
    }
}

// MARK: - UISearchBarDelegate

extension ImportsExportsViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.searchText = searchText
        filterData()
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - Import/Export Cell

class ImportExportCell: UITableViewCell {
    
    private let iconLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 20)
        return label
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        label.numberOfLines = 0
        return label
    }()
    
    private let detailLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
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
        contentView.addSubview(detailLabel)
        
        NSLayoutConstraint.activate([
            iconLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            iconLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            iconLabel.widthAnchor.constraint(equalToConstant: 24),
            
            nameLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 8),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            
            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            detailLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            detailLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }
    
    func configure(withImport importSym: ImportedSymbol) {
        iconLabel.text = "📥"
        nameLabel.text = importSym.displayName
        detailLabel.text = "0x\(String(format: "%llX", importSym.address)) • \(importSym.libraryName)\(importSym.weakIndicator)"
    }
    
    func configure(withExport exportSym: ExportedSymbol) {
        iconLabel.text = "📤"
        nameLabel.text = exportSym.displayName
        
        if exportSym.isReexport {
            detailLabel.text = "Re-export → \(exportSym.reexportLibraryName)"
        } else {
            detailLabel.text = "0x\(String(format: "%llX", exportSym.address)) • \(exportSym.exportType)"
        }
    }
    
    func configure(withLibrary library: String, importCount: Int) {
        iconLabel.text = "📚"
        nameLabel.text = library.components(separatedBy: "/").last ?? library
        detailLabel.text = "\(library)\n\(importCount) imports"
    }
}

