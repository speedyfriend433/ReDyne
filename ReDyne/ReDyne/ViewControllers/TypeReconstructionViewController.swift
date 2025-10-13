import UIKit

/// Main view controller for browsing and managing reconstructed types
class TypeReconstructionViewController: UIViewController {
    
    // MARK: - Properties
    
    private let results: TypeReconstructionResults
    private let typeAnalyzer: TypeAnalyzer
    private let inferenceEngine: TypeInferenceEngine
    
    private var filteredTypes: [ReconstructedType] = []
    private var selectedCategory: TypeCategory?
    private var selectedSource: TypeSource?
    private var searchText: String = ""
    
    // MARK: - UI Components
    
    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = true
        return scrollView
    }()
    
    private lazy var contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var statisticsHeader: TypeStatisticsHeader = {
        let header = TypeStatisticsHeader()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.configure(with: results.statistics)
        return header
    }()
    
    private lazy var filterBar: TypeFilterBar = {
        let filterBar = TypeFilterBar()
        filterBar.translatesAutoresizingMaskIntoConstraints = false
        filterBar.delegate = self
        return filterBar
    }()
    
    private lazy var searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.placeholder = "Search types..."
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        return searchBar
    }()
    
    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(TypeCell.self, forCellReuseIdentifier: "TypeCell")
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorStyle = .singleLine
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        return tableView
    }()
    
    private lazy var emptyStateView: TypeEmptyStateView = {
        let view = TypeEmptyStateView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    // MARK: - Initialization
    
    init(results: TypeReconstructionResults, typeAnalyzer: TypeAnalyzer, inferenceEngine: TypeInferenceEngine) {
        self.results = results
        self.typeAnalyzer = typeAnalyzer
        self.inferenceEngine = inferenceEngine
        super.init(nibName: nil, bundle: nil)
        
        self.filteredTypes = results.types
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupNavigationBar()
        updateEmptyState()
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = .systemGroupedBackground
        title = "Type Reconstruction"
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(statisticsHeader)
        contentView.addSubview(filterBar)
        contentView.addSubview(searchBar)
        contentView.addSubview(tableView)
        contentView.addSubview(emptyStateView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            statisticsHeader.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            statisticsHeader.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            statisticsHeader.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            filterBar.topAnchor.constraint(equalTo: statisticsHeader.bottomAnchor, constant: 16),
            filterBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            filterBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            searchBar.topAnchor.constraint(equalTo: filterBar.bottomAnchor, constant: 8),
            searchBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            searchBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            tableView.heightAnchor.constraint(equalToConstant: 600), // Fixed height for scroll view
            
            emptyStateView.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            emptyStateView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 32),
            emptyStateView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -32)
        ])
    }
    
    private func setupNavigationBar() {
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                image: UIImage(systemName: "square.and.arrow.up"),
                style: .plain,
                target: self,
                action: #selector(exportTypes)
            ),
            UIBarButtonItem(
                image: UIImage(systemName: "slider.horizontal.3"),
                style: .plain,
                target: self,
                action: #selector(showAdvancedFilters)
            )
        ]
    }
    
    // MARK: - Filtering and Search
    
    private func applyFilters() {
        filteredTypes = results.types
        
        // Apply category filter
        if let category = selectedCategory {
            filteredTypes = filteredTypes.filter { $0.category == category }
        }
        
        // Apply source filter
        if let source = selectedSource {
            filteredTypes = filteredTypes.filter { $0.source == source }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            filteredTypes = filteredTypes.filter { type in
                type.name.localizedCaseInsensitiveContains(searchText) ||
                type.category.displayName.localizedCaseInsensitiveContains(searchText) ||
                type.source.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        tableView.reloadData()
        updateEmptyState()
    }
    
    private func updateEmptyState() {
        let isEmpty = filteredTypes.isEmpty
        emptyStateView.isHidden = !isEmpty
        
        if isEmpty {
            if results.types.isEmpty {
                emptyStateView.configure(
                    icon: "magnifyingglass",
                    title: "No Types Found",
                    message: "No types were reconstructed from this binary. Try analyzing a different binary or check the analysis settings."
                )
            } else {
                emptyStateView.configure(
                    icon: "line.3.horizontal.decrease.circle",
                    title: "No Matching Types",
                    message: "No types match the current filters. Try adjusting your search criteria."
                )
            }
        }
    }
    
    // MARK: - Actions
    
    @objc private func exportTypes() {
        let alert = UIAlertController(title: "Export Types", message: "Choose export format", preferredStyle: .actionSheet)
        
        for format in TypeExportFormat.allCases {
            alert.addAction(UIAlertAction(title: format.displayName, style: .default) { _ in
                self.performExport(format: format)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        
        present(alert, animated: true)
    }
    
    @objc private func showAdvancedFilters() {
        let filterVC = TypeAdvancedFilterViewController(
            selectedCategory: selectedCategory,
            selectedSource: selectedSource
        )
        filterVC.delegate = self
        
        let navController = UINavigationController(rootViewController: filterVC)
        present(navController, animated: true)
    }
    
    private func performExport(format: TypeExportFormat) {
        // Implementation would generate and export type definitions
        let alert = UIAlertController(
            title: "Export Complete",
            message: "Types exported to \(format.displayName) format",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension TypeReconstructionViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredTypes.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TypeCell", for: indexPath) as! TypeCell
        let type = filteredTypes[indexPath.row]
        cell.configure(with: type)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension TypeReconstructionViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let type = filteredTypes[indexPath.row]
        let detailVC = TypeDetailViewController(type: type, inferenceEngine: inferenceEngine)
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let type = filteredTypes[indexPath.row]
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let editAction = UIAction(title: "Edit Type", image: UIImage(systemName: "pencil")) { _ in
                self.editType(type)
            }
            
            let exportAction = UIAction(title: "Export Type", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                self.exportSingleType(type)
            }
            
            let deleteAction = UIAction(title: "Delete Type", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                self.deleteType(type)
            }
            
            return UIMenu(title: type.name, children: [editAction, exportAction, deleteAction])
        }
    }
    
    private func editType(_ type: ReconstructedType) {
        let editorVC = TypeEditorViewController(type: type, mode: .edit)
        let navController = UINavigationController(rootViewController: editorVC)
        present(navController, animated: true)
    }
    
    private func exportSingleType(_ type: ReconstructedType) {
        // Export single type
        let alert = UIAlertController(
            title: "Export \(type.name)",
            message: "Type exported successfully",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func deleteType(_ type: ReconstructedType) {
        let alert = UIAlertController(
            title: "Delete Type",
            message: "Are you sure you want to delete '\(type.name)'?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            // Remove from filtered types and reload
            if let index = self.filteredTypes.firstIndex(of: type) {
                self.filteredTypes.remove(at: index)
                self.tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .fade)
                self.updateEmptyState()
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - UISearchBarDelegate

extension TypeReconstructionViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.searchText = searchText
        applyFilters()
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - TypeFilterBarDelegate

extension TypeReconstructionViewController: TypeFilterBarDelegate {
    func filterBar(_ filterBar: TypeFilterBar, didSelectCategory category: TypeCategory?) {
        selectedCategory = category
        applyFilters()
    }
    
    func filterBar(_ filterBar: TypeFilterBar, didSelectSource source: TypeSource?) {
        selectedSource = source
        applyFilters()
    }
}

// MARK: - TypeAdvancedFilterDelegate

extension TypeReconstructionViewController: TypeAdvancedFilterDelegate {
    func advancedFilter(_ filter: TypeAdvancedFilterViewController, didUpdateCategory category: TypeCategory?) {
        selectedCategory = category
        applyFilters()
    }
    
    func advancedFilter(_ filter: TypeAdvancedFilterViewController, didUpdateSource source: TypeSource?) {
        selectedSource = source
        applyFilters()
    }
}

// MARK: - Supporting Views

class TypeStatisticsHeader: UIView {
    private let titleLabel = UILabel()
    private let statsStackView = UIStackView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        backgroundColor = .systemBackground
        layer.cornerRadius = 12
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 4
        
        titleLabel.text = "Type Reconstruction Statistics"
        titleLabel.font = .boldSystemFont(ofSize: 18)
        titleLabel.textColor = .label
        
        statsStackView.axis = .horizontal
        statsStackView.distribution = .fillEqually
        statsStackView.spacing = 8
        
        addSubview(titleLabel)
        addSubview(statsStackView)
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        statsStackView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            statsStackView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            statsStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            statsStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            statsStackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
    }
    
    func configure(with statistics: TypeStatistics) {
        // Clear existing stats
        statsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Add stat cards
        let totalCard = createStatCard(title: "Total Types", value: "\(statistics.totalTypes)", color: .systemBlue)
        let avgConfidenceCard = createStatCard(title: "Avg Confidence", value: String(format: "%.1f%%", statistics.averageConfidence * 100), color: .systemGreen)
        let propertiesCard = createStatCard(title: "Properties", value: "\(statistics.totalProperties)", color: .systemOrange)
        let methodsCard = createStatCard(title: "Methods", value: "\(statistics.totalMethods)", color: .systemPurple)
        
        statsStackView.addArrangedSubview(totalCard)
        statsStackView.addArrangedSubview(avgConfidenceCard)
        statsStackView.addArrangedSubview(propertiesCard)
        statsStackView.addArrangedSubview(methodsCard)
    }
    
    private func createStatCard(title: String, value: String, color: UIColor) -> UIView {
        let card = UIView()
        card.backgroundColor = color.withAlphaComponent(0.1)
        card.layer.cornerRadius = 8
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center
        
        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .boldSystemFont(ofSize: 20)
        valueLabel.textColor = color
        valueLabel.textAlignment = .center
        
        card.addSubview(titleLabel)
        card.addSubview(valueLabel)
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -4),
            
            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            valueLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 4),
            valueLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -4),
            valueLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8)
        ])
        
        return card
    }
}

class TypeFilterBar: UIView {
    weak var delegate: TypeFilterBarDelegate?
    
    private let categoryButton = UIButton(type: .system)
    private let sourceButton = UIButton(type: .system)
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        backgroundColor = .systemBackground
        layer.cornerRadius = 8
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor
        
        categoryButton.setTitle("All Categories", for: .normal)
        categoryButton.addTarget(self, action: #selector(categoryButtonTapped), for: .touchUpInside)
        
        sourceButton.setTitle("All Sources", for: .normal)
        sourceButton.addTarget(self, action: #selector(sourceButtonTapped), for: .touchUpInside)
        
        addSubview(categoryButton)
        addSubview(sourceButton)
        
        categoryButton.translatesAutoresizingMaskIntoConstraints = false
        sourceButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            categoryButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            categoryButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            categoryButton.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5, constant: -18),
            
            sourceButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            sourceButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            sourceButton.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5, constant: -18)
        ])
    }
    
    @objc private func categoryButtonTapped() {
        delegate?.filterBar(self, didSelectCategory: nil) // Would show picker
    }
    
    @objc private func sourceButtonTapped() {
        delegate?.filterBar(self, didSelectSource: nil) // Would show picker
    }
}

protocol TypeFilterBarDelegate: AnyObject {
    func filterBar(_ filterBar: TypeFilterBar, didSelectCategory category: TypeCategory?)
    func filterBar(_ filterBar: TypeFilterBar, didSelectSource source: TypeSource?)
}

class TypeEmptyStateView: UIView {
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = .systemGray
        
        titleLabel.font = .boldSystemFont(ofSize: 20)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        
        messageLabel.font = .systemFont(ofSize: 16)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        
        addSubview(iconImageView)
        addSubview(titleLabel)
        addSubview(messageLabel)
        
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.topAnchor.constraint(equalTo: topAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 64),
            iconImageView.heightAnchor.constraint(equalToConstant: 64),
            
            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    func configure(icon: String, title: String, message: String) {
        iconImageView.image = UIImage(systemName: icon)
        titleLabel.text = title
        messageLabel.text = message
    }
}

// MARK: - Type Cell

class TypeCell: UITableViewCell {
    private let categoryIconLabel = UILabel()
    private let nameLabel = UILabel()
    private let categoryLabel = UILabel()
    private let sourceLabel = UILabel()
    private let confidenceLabel = UILabel()
    private let sizeLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        backgroundColor = .systemBackground
        
        categoryIconLabel.font = .systemFont(ofSize: 24)
        
        nameLabel.font = .boldSystemFont(ofSize: 16)
        nameLabel.textColor = .label
        
        categoryLabel.font = .systemFont(ofSize: 14)
        categoryLabel.textColor = .secondaryLabel
        
        sourceLabel.font = .systemFont(ofSize: 12)
        sourceLabel.textColor = .tertiaryLabel
        
        confidenceLabel.font = .systemFont(ofSize: 12, weight: .medium)
        
        sizeLabel.font = .systemFont(ofSize: 12)
        sizeLabel.textColor = .tertiaryLabel
        
        contentView.addSubview(categoryIconLabel)
        contentView.addSubview(nameLabel)
        contentView.addSubview(categoryLabel)
        contentView.addSubview(sourceLabel)
        contentView.addSubview(confidenceLabel)
        contentView.addSubview(sizeLabel)
        
        categoryIconLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        categoryLabel.translatesAutoresizingMaskIntoConstraints = false
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false
        confidenceLabel.translatesAutoresizingMaskIntoConstraints = false
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            categoryIconLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            categoryIconLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            categoryIconLabel.widthAnchor.constraint(equalToConstant: 32),
            categoryIconLabel.heightAnchor.constraint(equalToConstant: 32),
            
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: categoryIconLabel.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: confidenceLabel.leadingAnchor, constant: -8),
            
            categoryLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            categoryLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            categoryLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            
            sourceLabel.topAnchor.constraint(equalTo: categoryLabel.bottomAnchor, constant: 2),
            sourceLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            sourceLabel.trailingAnchor.constraint(equalTo: sizeLabel.leadingAnchor, constant: -8),
            sourceLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            
            confidenceLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            confidenceLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            confidenceLabel.widthAnchor.constraint(equalToConstant: 60),
            
            sizeLabel.topAnchor.constraint(equalTo: confidenceLabel.bottomAnchor, constant: 4),
            sizeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            sizeLabel.widthAnchor.constraint(equalToConstant: 60)
        ])
    }
    
    func configure(with type: ReconstructedType) {
        categoryIconLabel.text = type.category.icon
        nameLabel.text = type.name
        categoryLabel.text = type.category.displayName
        sourceLabel.text = type.source.displayName
        
        let confidence = Int(type.confidence * 100)
        confidenceLabel.text = "\(confidence)%"
        confidenceLabel.textColor = confidenceColor(for: type.confidence)
        
        sizeLabel.text = "\(type.size) bytes"
    }
    
    private func confidenceColor(for confidence: Double) -> UIColor {
        if confidence >= 0.8 {
            return .systemGreen
        } else if confidence >= 0.6 {
            return .systemOrange
        } else {
            return .systemRed
        }
    }
}

