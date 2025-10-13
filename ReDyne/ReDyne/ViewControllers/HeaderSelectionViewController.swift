//
//  HeaderSelectionViewController.swift
//  ReDyne
//
//  Created by Assistant on 2024.
//

import UIKit

// MARK: - Header File Model
struct HeaderFile: Hashable {
    let name: String
    let category: HeaderCategory
    let content: String
    let lineCount: Int
}

protocol HeaderSelectionViewControllerDelegate: AnyObject {
    func headerSelectionViewController(_ controller: HeaderSelectionViewController, didSelectHeader header: HeaderFile)
    func headerSelectionViewController(_ controller: HeaderSelectionViewController, didSelectHeaders headers: [HeaderFile])
}

enum HeaderCategory: String, CaseIterable {
    case classes = "Classes"
    case categories = "Categories"
    case protocols = "Protocols"
    case structs = "Structs"
    case enums = "Enums"
    case interfaces = "Interfaces"
    case unknown = "Other"
    
    var icon: String {
        switch self {
        case .classes: return "⚙️"
        case .categories: return "🔗"
        case .protocols: return "📋"
        case .structs: return "🏗️"
        case .enums: return "🔢"
        case .interfaces: return "🔌"
        case .unknown: return "📄"
        }
    }
    
    var color: UIColor {
        switch self {
        case .classes: return .systemBlue
        case .categories: return .systemGreen
        case .protocols: return .systemOrange
        case .structs: return .systemPurple
        case .enums: return .systemRed
        case .interfaces: return .systemTeal
        case .unknown: return .systemGray
        }
    }
}

class HeaderSelectionViewController: UIViewController {
    
    // MARK: - Properties
    
    private let headerContent: String
    private var headerFiles: [HeaderFile] = []
    private var filteredHeaders: [HeaderFile] = []
    private var categorizedHeaders: [HeaderCategory: [HeaderFile]] = [:]
    private var selectedHeaders: Set<HeaderFile> = []

    weak var delegate: HeaderSelectionViewControllerDelegate?
    
    // MARK: - UI Components
    
    private lazy var searchController: UISearchController = {
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search headers..."
        searchController.searchBar.delegate = self
        return searchController
    }()
    
    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(HeaderFileCell.self, forCellReuseIdentifier: HeaderFileCell.reuseIdentifier)
        tableView.register(HeaderCategoryHeader.self, forHeaderFooterViewReuseIdentifier: HeaderCategoryHeader.reuseIdentifier)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        return tableView
    }()
    
    private lazy var doneButton: UIBarButtonItem = {
        return UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneButtonTapped)
        )
    }()
    
    private lazy var selectAllButton: UIBarButtonItem = {
        return UIBarButtonItem(
            title: "Select All",
            style: .plain,
            target: self,
            action: #selector(selectAllButtonTapped)
        )
    }()
    
    private var isSearchActive: Bool {
        return searchController.isActive && !(searchController.searchBar.text?.isEmpty ?? true)
    }
    
    // MARK: - Initialization
    
    init(headerFiles: [HeaderFile]) {
        self.headerContent = ""
        self.headerFiles = headerFiles
        super.init(nibName: nil, bundle: nil)
    }
    
    init(headerContent: String) {
        self.headerContent = headerContent
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        
        if headerFiles.isEmpty && !headerContent.isEmpty {
            parseHeaderContent()
        } else if !headerFiles.isEmpty {
            // Use provided header files
            filteredHeaders = headerFiles
            // Build categorizedHeaders from headerFiles
            for header in headerFiles {
                if categorizedHeaders[header.category] == nil {
                    categorizedHeaders[header.category] = []
                }
                categorizedHeaders[header.category]?.append(header)
            }
        }
        
        updateUI()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        title = "Header Files"
        view.backgroundColor = .systemBackground
        
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.leftBarButtonItem = doneButton
        navigationItem.rightBarButtonItem = selectAllButton
        
        view.addSubview(tableView)
        tableView.allowsMultipleSelection = true

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - Header Parsing
    
    private func parseHeaderContent() {
        print("[HeaderSelectionViewController] Parsing header content of length: \(headerContent.count)")
        
        let lines = headerContent.components(separatedBy: .newlines)
        var currentHeader: String?
        var currentContent: [String] = []
        var currentCategory: HeaderCategory = .unknown
        
        func finalizeCurrentHeader() {
            guard let headerName = currentHeader, !currentContent.isEmpty else { return }
            
            let content = currentContent.joined(separator: "\n")
            let headerFile = HeaderFile(
                name: headerName,
                category: currentCategory,
                content: content,
                lineCount: currentContent.count
            )
            
            headerFiles.append(headerFile)
            
            if categorizedHeaders[currentCategory] == nil {
                categorizedHeaders[currentCategory] = []
            }
            categorizedHeaders[currentCategory]?.append(headerFile)
        }
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Check for class declarations
            if trimmedLine.hasPrefix("@interface ") || trimmedLine.hasPrefix("@implementation ") {
                finalizeCurrentHeader()
                
                // Extract class name
                let components = trimmedLine.components(separatedBy: .whitespaces)
                if components.count >= 2 {
                    currentHeader = components[1]
                    currentCategory = .classes
                } else {
                    currentHeader = "UnknownClass"
                    currentCategory = .classes
                }
                currentContent = [line]
            }
            // Check for category declarations
            else if trimmedLine.hasPrefix("@interface ") && trimmedLine.contains("(") {
                finalizeCurrentHeader()
                
                let components = trimmedLine.components(separatedBy: "(")
                if components.count >= 2 {
                    currentHeader = components[0].replacingOccurrences(of: "@interface ", with: "") + "("
                    currentCategory = .categories
                } else {
                    currentHeader = "UnknownCategory"
                    currentCategory = .categories
                }
                currentContent = [line]
            }
            // Check for protocol declarations
            else if trimmedLine.hasPrefix("@protocol ") {
                finalizeCurrentHeader()
                
                let components = trimmedLine.components(separatedBy: .whitespaces)
                if components.count >= 2 {
                    currentHeader = components[1]
                    currentCategory = .protocols
                } else {
                    currentHeader = "UnknownProtocol"
                    currentCategory = .protocols
                }
                currentContent = [line]
            }
            // Check for struct declarations (Swift)
            else if trimmedLine.hasPrefix("struct ") {
                finalizeCurrentHeader()
                
                let components = trimmedLine.components(separatedBy: .whitespaces)
                if components.count >= 2 {
                    currentHeader = components[1]
                    currentCategory = .structs
                } else {
                    currentHeader = "UnknownStruct"
                    currentCategory = .structs
                }
                currentContent = [line]
            }
            // Check for enum declarations
            else if trimmedLine.hasPrefix("enum ") || trimmedLine.hasPrefix("typedef NS_ENUM") {
                finalizeCurrentHeader()
                
                if trimmedLine.hasPrefix("enum ") {
                    let components = trimmedLine.components(separatedBy: .whitespaces)
                    if components.count >= 2 {
                        currentHeader = components[1]
                    } else {
                        currentHeader = "UnknownEnum"
                    }
                } else {
                    currentHeader = "NS_ENUM"
                }
                currentCategory = .enums
                currentContent = [line]
            }
            // Continue building current header content
            else if currentHeader != nil {
                currentContent.append(line)
                
                // Check for end of interface/implementation
                if trimmedLine == "@end" {
                    finalizeCurrentHeader()
                    currentHeader = nil
                    currentContent = []
                }
            }
        }
        
        // Finalize any remaining header
        finalizeCurrentHeader()
        
        // Sort headers within each category
        for category in categorizedHeaders.keys {
            categorizedHeaders[category]?.sort { $0.name < $1.name }
        }
        
        print("[HeaderSelectionViewController] Parsed \(headerFiles.count) header files")
        print("[HeaderSelectionViewController] Categories: \(categorizedHeaders.keys.map { $0.rawValue }.joined(separator: ", "))")
        
        filteredHeaders = headerFiles
    }
    
    private func updateUI() {
        tableView.reloadData()
        
        let totalHeaders = headerFiles.count
        let categories = categorizedHeaders.keys.count
        
        if totalHeaders == 0 {
            navigationItem.prompt = "No headers found"
        } else {
            navigationItem.prompt = "\(totalHeaders) headers in \(categories) categories"
        }
    }
    
    // MARK: - Actions
    
    @objc private func doneButtonTapped() {
        if !selectedHeaders.isEmpty {
            delegate?.headerSelectionViewController(self, didSelectHeaders: Array(selectedHeaders))
        }
        dismiss(animated: true)
    }
    
    @objc private func selectAllButtonTapped() {
        let currentHeaders = getCurrentHeaders()
        selectedHeaders = Set(currentHeaders)

        // Select all rows
        for section in 0..<tableView.numberOfSections {
            for row in 0..<tableView.numberOfRows(inSection: section) {
                let indexPath = IndexPath(row: row, section: section)
                tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
            }
        }

        // Update button title to indicate selection
        selectAllButton.title = "Deselect All"
        selectAllButton.action = #selector(deselectAllButtonTapped)
    }

    @objc private func deselectAllButtonTapped() {
        selectedHeaders.removeAll()

        // Deselect all rows
        for section in 0..<tableView.numberOfSections {
            for row in 0..<tableView.numberOfRows(inSection: section) {
                let indexPath = IndexPath(row: row, section: section)
                tableView.deselectRow(at: indexPath, animated: true)
            }
        }

        selectAllButton.title = "Select All"
        selectAllButton.action = #selector(selectAllButtonTapped)
    }
    
    // MARK: - Helper Methods
    
    private func getCurrentHeaders() -> [HeaderFile] {
        return isSearchActive ? filteredHeaders : headerFiles
    }
    
    private func getCurrentCategories() -> [HeaderCategory] {
        if isSearchActive {
            let categories = Set(filteredHeaders.map { $0.category })
            return HeaderCategory.allCases.filter { categories.contains($0) }
        } else {
            let categoriesWithContent = categorizedHeaders.filter { !$0.value.isEmpty }.keys
            return HeaderCategory.allCases.filter { categoriesWithContent.contains($0) }
        }
    }
    
    private func getHeadersForCategory(_ category: HeaderCategory) -> [HeaderFile] {
        if isSearchActive {
            return filteredHeaders.filter { $0.category == category }
        } else {
            return categorizedHeaders[category] ?? []
        }
    }
}

// MARK: - UITableViewDataSource

extension HeaderSelectionViewController: UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return getCurrentCategories().count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let categories = getCurrentCategories()
        guard section < categories.count else { return 0 }
        return getHeadersForCategory(categories[section]).count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: HeaderFileCell.reuseIdentifier, for: indexPath) as! HeaderFileCell
        
        let categories = getCurrentCategories()
        guard indexPath.section < categories.count else { return cell }
        
        let headers = getHeadersForCategory(categories[indexPath.section])
        guard indexPath.row < headers.count else { return cell }
        
        let header = headers[indexPath.row]
        cell.configure(with: header)
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let categories = getCurrentCategories()
        guard section < categories.count else { return nil }
        
        let category = categories[section]
        let headers = getHeadersForCategory(category)
        return "\(category.icon) \(category.rawValue) (\(headers.count))"
    }
}

// MARK: - UITableViewDelegate

extension HeaderSelectionViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let categories = getCurrentCategories()
        guard indexPath.section < categories.count else { return }

        let headers = getHeadersForCategory(categories[indexPath.section])
        guard indexPath.row < headers.count else { return }

        let header = headers[indexPath.row]
        selectedHeaders.insert(header)
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        let categories = getCurrentCategories()
        guard indexPath.section < categories.count else { return }

        let headers = getHeadersForCategory(categories[indexPath.section])
        guard indexPath.row < headers.count else { return }

        let header = headers[indexPath.row]
        selectedHeaders.remove(header)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
}

// MARK: - UISearchResultsUpdating

extension HeaderSelectionViewController: UISearchResultsUpdating {
    
    func updateSearchResults(for searchController: UISearchController) {
        guard let searchText = searchController.searchBar.text?.lowercased(), !searchText.isEmpty else {
            filteredHeaders = headerFiles
            updateUI()
            return
        }
        
        filteredHeaders = headerFiles.filter { header in
            return header.name.lowercased().contains(searchText) ||
                   header.content.lowercased().contains(searchText)
        }
        
        updateUI()
    }
}

// MARK: - UISearchBarDelegate

extension HeaderSelectionViewController: UISearchBarDelegate {
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        filteredHeaders = headerFiles
        updateUI()
    }
}

// MARK: - Custom Cells

class HeaderFileCell: UITableViewCell {
    
    static let reuseIdentifier = "HeaderFileCell"
    
    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var detailLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var categoryBadge: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var categoryLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
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
        contentView.addSubview(nameLabel)
        contentView.addSubview(detailLabel)
        contentView.addSubview(categoryBadge)
        categoryBadge.addSubview(categoryLabel)
        
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(equalTo: categoryBadge.leadingAnchor, constant: -8),
            
            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            detailLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            detailLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            detailLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            
            categoryBadge.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            categoryBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            categoryBadge.heightAnchor.constraint(equalToConstant: 20),
            categoryBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
            
            categoryLabel.centerXAnchor.constraint(equalTo: categoryBadge.centerXAnchor),
            categoryLabel.centerYAnchor.constraint(equalTo: categoryBadge.centerYAnchor),
            categoryLabel.leadingAnchor.constraint(equalTo: categoryBadge.leadingAnchor, constant: 6),
            categoryLabel.trailingAnchor.constraint(equalTo: categoryBadge.trailingAnchor, constant: -6)
        ])
    }
    
    func configure(with header: HeaderFile) {
        nameLabel.text = header.name
        detailLabel.text = "\(header.lineCount) lines • \(header.category.rawValue)"
        categoryLabel.text = header.category.rawValue
        categoryBadge.backgroundColor = header.category.color
    }
}

class HeaderCategoryHeader: UITableViewHeaderFooterView {
    
    static let reuseIdentifier = "HeaderCategoryHeader"
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        contentView.backgroundColor = .systemGroupedBackground
        contentView.addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }
    
    func configure(with title: String) {
        titleLabel.text = title
    }
}

