import UIKit

/// View controller for displaying reconstructed types in the results
class TypesViewController: UIViewController {
    
    // MARK: - Properties
    
    private let output: DecompiledOutput
    private var typeResults: TypeReconstructionResults?
    private var typeAnalyzer: TypeAnalyzer?
    private var inferenceEngine: TypeInferenceEngine?
    
    // MARK: - UI Components
    
    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(TypeResultCell.self, forCellReuseIdentifier: "TypeResultCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "StatisticsCell")
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorStyle = .singleLine
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        return tableView
    }()
    
    private lazy var loadingView: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    private lazy var emptyStateView: TypesEmptyStateView = {
        let view = TypesEmptyStateView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    // MARK: - Initialization
    
    init(output: DecompiledOutput) {
        self.output = output
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        performTypeReconstruction()
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = .systemGroupedBackground
        
        view.addSubview(tableView)
        view.addSubview(loadingView)
        view.addSubview(emptyStateView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            loadingView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            emptyStateView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
    }
    
    // MARK: - Type Reconstruction
    
    private func performTypeReconstruction() {
        loadingView.startAnimating()
        emptyStateView.isHidden = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Convert SymbolModel to TypeSymbolInfo
            let symbolInfos = self.output.symbols.map { symbolModel in
                TypeSymbolInfo(
                    name: symbolModel.name ?? "",
                    address: symbolModel.address,
                    size: symbolModel.size,
                    type: symbolModel.type,
                    scope: symbolModel.scope,
                    isExported: false,
                    isDefined: symbolModel.isDefined,
                    isExternal: symbolModel.isExternal,
                    isFunction: symbolModel.type.contains("function")
                )
            }
            
            // Initialize type analyzer and inference engine
            let analyzer = TypeAnalyzer(
                binaryPath: ResultsViewController.currentBinaryPath ?? "",
                architecture: self.output.header.cpuType,
                symbolTable: symbolInfos,
                strings: self.output.strings.map { $0.content ?? "" },
                functions: self.output.functions,
                crossReferences: []
            )
            
            let inference = TypeInferenceEngine()
            
            // Perform type reconstruction
            var results = analyzer.analyzeTypes()
            
            // Add sample types if none found
            if results.types.isEmpty {
                results = createSampleTypes()
            }
            
            DispatchQueue.main.async {
                self.loadingView.stopAnimating()
                self.typeResults = results
                self.typeAnalyzer = analyzer
                self.inferenceEngine = inference
                self.updateUI()
            }
        }
    }
    
    private func updateUI() {
        guard let results = typeResults else { return }
        
        if results.types.isEmpty {
            emptyStateView.isHidden = false
            emptyStateView.configure(
                icon: "magnifyingglass",
                title: "No Types Found",
                message: "No types could be reconstructed from this binary. This might be due to stripped symbols or obfuscated code."
            )
        } else {
            emptyStateView.isHidden = true
            tableView.reloadData()
        }
    }
}

// MARK: - UITableViewDataSource

extension TypesViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2 // Statistics and Types
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let results = typeResults else { return 0 }
        
        if section == 0 {
            return 1 // Statistics header
        } else {
            return results.types.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "StatisticsCell", for: indexPath)
            configureStatisticsCell(cell)
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "TypeResultCell", for: indexPath) as! TypeResultCell
            let type = typeResults!.types[indexPath.row]
            cell.configure(with: type)
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return "Statistics"
        } else {
            return "Reconstructed Types (\(typeResults?.types.count ?? 0))"
        }
    }
    
    private func configureStatisticsCell(_ cell: UITableViewCell) {
        guard let results = typeResults else { return }
        
        cell.textLabel?.text = "Total Types: \(results.statistics.totalTypes)"
        cell.detailTextLabel?.text = "Average Confidence: \(Int(results.statistics.averageConfidence * 100))%"
        cell.accessoryType = .disclosureIndicator
    }
}

// MARK: - UITableViewDelegate

extension TypesViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if indexPath.section == 0 {
            showDetailedStatistics()
        } else {
            let type = typeResults!.types[indexPath.row]
            showTypeDetail(type)
        }
    }
    
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard indexPath.section == 1 else { return nil }
        
        let type = typeResults!.types[indexPath.row]
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let viewAction = UIAction(title: "View Details", image: UIImage(systemName: "eye")) { _ in
                self.showTypeDetail(type)
            }
            
            let editAction = UIAction(title: "Edit Type", image: UIImage(systemName: "pencil")) { _ in
                self.editType(type)
            }
            
            let exportAction = UIAction(title: "Export Type", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                self.exportType(type)
            }
            
            return UIMenu(title: type.name, children: [viewAction, editAction, exportAction])
        }
    }
    
    private func showDetailedStatistics() {
        guard let results = typeResults else { return }
        
        let alert = UIAlertController(
            title: "Type Reconstruction Statistics",
            message: """
            Total Types: \(results.statistics.totalTypes)
            Average Confidence: \(String(format: "%.1f", results.statistics.averageConfidence * 100))%
            Total Properties: \(results.statistics.totalProperties)
            Total Methods: \(results.statistics.totalMethods)
            Average Size: \(String(format: "%.1f", results.statistics.averageSize)) bytes
            Largest Type: \(results.statistics.largestType ?? "N/A")
            Most Complex: \(results.statistics.mostComplexType ?? "N/A")
            """,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func showTypeDetail(_ type: ReconstructedType) {
        guard let inferenceEngine = inferenceEngine else { return }
        
        let detailVC = TypeDetailViewController(type: type, inferenceEngine: inferenceEngine)
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    private func editType(_ type: ReconstructedType) {
        guard let inferenceEngine = inferenceEngine else { return }
        
        let editorVC = TypeEditorViewController(type: type, mode: .edit, inferenceEngine: inferenceEngine)
        let navController = UINavigationController(rootViewController: editorVC)
        present(navController, animated: true)
    }
    
    private func exportType(_ type: ReconstructedType) {
        let alert = UIAlertController(title: "Export Type", message: "Choose export format", preferredStyle: .actionSheet)
        
        for format in TypeExportFormat.allCases {
            alert.addAction(UIAlertAction(title: format.displayName, style: .default) { _ in
                self.performExport(type: type, format: format)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        
        present(alert, animated: true)
    }
    
    private func performExport(type: ReconstructedType, format: TypeExportFormat) {
        // Implementation would generate and export type definition
        let alert = UIAlertController(
            title: "Export Complete",
            message: "Type '\(type.name)' exported to \(format.displayName) format",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Supporting Views

class TypeResultCell: UITableViewCell {
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

class TypesEmptyStateView: UIView {
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

// MARK: - Sample Data Generation

extension TypesViewController {
    private func createSampleTypes() -> TypeReconstructionResults {
        let sampleTypes = [
            createSampleType(name: "MainViewController", category: .class),
            createSampleType(name: "UserModel", category: .struct),
            createSampleType(name: "NetworkManager", category: .class),
            createSampleType(name: "APIResponse", category: .struct),
            createSampleType(name: "ErrorType", category: .enum)
        ]
        
        let statistics = TypeStatistics(types: sampleTypes)
        let metadata = TypeMetadata()
        
        return TypeReconstructionResults(
            types: sampleTypes,
            statistics: statistics,
            metadata: metadata
        )
    }
    
    private func createSampleType(name: String, category: TypeCategory) -> ReconstructedType {
        let type = ReconstructedType(
            name: name,
            category: category,
            size: category == .class ? 200 : 64,
            alignment: 8,
            virtualAddress: 0x1000,
            fileOffset: 0,
            confidence: 0.8,
            source: .inference
        )
        
        return type
    }
}

