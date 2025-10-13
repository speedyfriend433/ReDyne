import UIKit

/// Detail view for a single reconstructed type
class TypeDetailViewController: UIViewController {
    
    // MARK: - Properties
    
    private let type: ReconstructedType
    private let inferenceEngine: TypeInferenceEngine
    
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
    
    private lazy var headerView: TypeDetailHeaderView = {
        let header = TypeDetailHeaderView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.configure(with: type)
        return header
    }()
    
    private lazy var propertiesTableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(PropertyDetailCell.self, forCellReuseIdentifier: "PropertyDetailCell")
        tableView.backgroundColor = .systemGroupedBackground
        return tableView
    }()
    
    private lazy var methodsTableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(MethodDetailCell.self, forCellReuseIdentifier: "MethodDetailCell")
        tableView.backgroundColor = .systemGroupedBackground
        return tableView
    }()
    
    // MARK: - Initialization
    
    init(type: ReconstructedType, inferenceEngine: TypeInferenceEngine) {
        self.type = type
        self.inferenceEngine = inferenceEngine
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupNavigationBar()
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = .systemGroupedBackground
        title = type.name
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(headerView)
        contentView.addSubview(propertiesTableView)
        contentView.addSubview(methodsTableView)
        
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
            
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            propertiesTableView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 20),
            propertiesTableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            propertiesTableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            propertiesTableView.heightAnchor.constraint(equalToConstant: 300),
            
            methodsTableView.topAnchor.constraint(equalTo: propertiesTableView.bottomAnchor, constant: 20),
            methodsTableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            methodsTableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            methodsTableView.heightAnchor.constraint(equalToConstant: 300),
            methodsTableView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
    }
    
    private func setupNavigationBar() {
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                image: UIImage(systemName: "pencil"),
                style: .plain,
                target: self,
                action: #selector(editTapped)
            ),
            UIBarButtonItem(
                image: UIImage(systemName: "square.and.arrow.up"),
                style: .plain,
                target: self,
                action: #selector(exportTapped)
            )
        ]
    }
    
    // MARK: - Actions
    
    @objc private func editTapped() {
        let editorVC = TypeEditorViewController(type: type, mode: .edit, inferenceEngine: inferenceEngine)
        let navController = UINavigationController(rootViewController: editorVC)
        present(navController, animated: true)
    }
    
    @objc private func exportTapped() {
        let alert = UIAlertController(title: "Export Type", message: "Choose export format", preferredStyle: .actionSheet)
        
        for format in TypeExportFormat.allCases {
            alert.addAction(UIAlertAction(title: format.displayName, style: .default) { _ in
                self.performExport(format: format)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.last
        }
        
        present(alert, animated: true)
    }
    
    private func performExport(format: TypeExportFormat) {
        // Implementation would generate and export type definition
        let alert = UIAlertController(
            title: "Export Complete",
            message: "Type exported to \(format.displayName) format",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension TypeDetailViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == propertiesTableView {
            return type.properties.count
        } else {
            return type.methods.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == propertiesTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "PropertyDetailCell", for: indexPath) as! PropertyDetailCell
            let property = type.properties[indexPath.row]
            cell.configure(with: property)
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "MethodDetailCell", for: indexPath) as! MethodDetailCell
            let method = type.methods[indexPath.row]
            cell.configure(with: method)
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if tableView == propertiesTableView {
            return "Properties (\(type.properties.count))"
        } else {
            return "Methods (\(type.methods.count))"
        }
    }
}

// MARK: - UITableViewDelegate

extension TypeDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if tableView == propertiesTableView {
            let property = type.properties[indexPath.row]
            showPropertyDetail(property)
        } else {
            let method = type.methods[indexPath.row]
            showMethodDetail(method)
        }
    }
    
    private func showPropertyDetail(_ property: TypeProperty) {
        let alert = UIAlertController(
            title: property.name,
            message: """
            Type: \(property.type)
            Offset: \(property.offset)
            Size: \(property.size)
            Optional: \(property.isOptional ? "Yes" : "No")
            Static: \(property.isStatic ? "Yes" : "No")
            Access: \(property.accessLevel.displayName)
            """,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func showMethodDetail(_ method: TypeMethod) {
        let alert = UIAlertController(
            title: method.name,
            message: """
            Signature: \(method.signature)
            Return Type: \(method.returnType)
            Parameters: \(method.parameters.count)
            Static: \(method.isStatic ? "Yes" : "No")
            Virtual: \(method.isVirtual ? "Yes" : "No")
            Access: \(method.accessLevel.displayName)
            """,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Supporting Views

class TypeDetailHeaderView: UIView {
    private let categoryIconLabel = UILabel()
    private let nameLabel = UILabel()
    private let categoryLabel = UILabel()
    private let sourceLabel = UILabel()
    private let confidenceLabel = UILabel()
    private let sizeLabel = UILabel()
    private let alignmentLabel = UILabel()
    
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
        
        categoryIconLabel.font = .systemFont(ofSize: 32)
        categoryIconLabel.textAlignment = .center
        
        nameLabel.font = .boldSystemFont(ofSize: 24)
        nameLabel.textColor = .label
        nameLabel.textAlignment = .center
        
        categoryLabel.font = .systemFont(ofSize: 16)
        categoryLabel.textColor = .secondaryLabel
        categoryLabel.textAlignment = .center
        
        sourceLabel.font = .systemFont(ofSize: 14)
        sourceLabel.textColor = .tertiaryLabel
        sourceLabel.textAlignment = .center
        
        confidenceLabel.font = .systemFont(ofSize: 14, weight: .medium)
        confidenceLabel.textAlignment = .center
        
        sizeLabel.font = .systemFont(ofSize: 14)
        sizeLabel.textColor = .secondaryLabel
        sizeLabel.textAlignment = .center
        
        alignmentLabel.font = .systemFont(ofSize: 14)
        alignmentLabel.textColor = .secondaryLabel
        alignmentLabel.textAlignment = .center
        
        addSubview(categoryIconLabel)
        addSubview(nameLabel)
        addSubview(categoryLabel)
        addSubview(sourceLabel)
        addSubview(confidenceLabel)
        addSubview(sizeLabel)
        addSubview(alignmentLabel)
        
        categoryIconLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        categoryLabel.translatesAutoresizingMaskIntoConstraints = false
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false
        confidenceLabel.translatesAutoresizingMaskIntoConstraints = false
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        alignmentLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            categoryIconLabel.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            categoryIconLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            categoryIconLabel.widthAnchor.constraint(equalToConstant: 40),
            categoryIconLabel.heightAnchor.constraint(equalToConstant: 40),
            
            nameLabel.topAnchor.constraint(equalTo: categoryIconLabel.bottomAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            categoryLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 8),
            categoryLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            categoryLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            sourceLabel.topAnchor.constraint(equalTo: categoryLabel.bottomAnchor, constant: 4),
            sourceLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            sourceLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            confidenceLabel.topAnchor.constraint(equalTo: sourceLabel.bottomAnchor, constant: 12),
            confidenceLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            confidenceLabel.trailingAnchor.constraint(equalTo: centerXAnchor, constant: -8),
            
            sizeLabel.topAnchor.constraint(equalTo: sourceLabel.bottomAnchor, constant: 12),
            sizeLabel.leadingAnchor.constraint(equalTo: centerXAnchor, constant: 8),
            sizeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            alignmentLabel.topAnchor.constraint(equalTo: confidenceLabel.bottomAnchor, constant: 8),
            alignmentLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            alignmentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            alignmentLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20)
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
        alignmentLabel.text = "Alignment: \(type.alignment)"
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

class PropertyDetailCell: UITableViewCell {
    private let nameLabel = UILabel()
    private let typeLabel = UILabel()
    private let offsetLabel = UILabel()
    private let sizeLabel = UILabel()
    private let accessLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        nameLabel.font = .boldSystemFont(ofSize: 16)
        nameLabel.textColor = .label
        
        typeLabel.font = .systemFont(ofSize: 14)
        typeLabel.textColor = .secondaryLabel
        
        offsetLabel.font = .systemFont(ofSize: 12)
        offsetLabel.textColor = .tertiaryLabel
        
        sizeLabel.font = .systemFont(ofSize: 12)
        sizeLabel.textColor = .tertiaryLabel
        
        accessLabel.font = .systemFont(ofSize: 12)
        accessLabel.textColor = .tertiaryLabel
        
        contentView.addSubview(nameLabel)
        contentView.addSubview(typeLabel)
        contentView.addSubview(offsetLabel)
        contentView.addSubview(sizeLabel)
        contentView.addSubview(accessLabel)
        
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        offsetLabel.translatesAutoresizingMaskIntoConstraints = false
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        accessLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            typeLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            typeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            typeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            offsetLabel.topAnchor.constraint(equalTo: typeLabel.bottomAnchor, constant: 2),
            offsetLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            offsetLabel.trailingAnchor.constraint(equalTo: contentView.centerXAnchor, constant: -8),
            
            sizeLabel.topAnchor.constraint(equalTo: typeLabel.bottomAnchor, constant: 2),
            sizeLabel.leadingAnchor.constraint(equalTo: contentView.centerXAnchor, constant: 8),
            sizeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            accessLabel.topAnchor.constraint(equalTo: offsetLabel.bottomAnchor, constant: 2),
            accessLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            accessLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            accessLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }
    
    func configure(with property: TypeProperty) {
        nameLabel.text = property.name
        typeLabel.text = property.type
        offsetLabel.text = "Offset: \(property.offset)"
        sizeLabel.text = "Size: \(property.size)"
        accessLabel.text = "Access: \(property.accessLevel.displayName) \(property.accessLevel.icon)"
    }
}

class MethodDetailCell: UITableViewCell {
    private let nameLabel = UILabel()
    private let signatureLabel = UILabel()
    private let returnTypeLabel = UILabel()
    private let parametersLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        nameLabel.font = .boldSystemFont(ofSize: 16)
        nameLabel.textColor = .label
        
        signatureLabel.font = .systemFont(ofSize: 14)
        signatureLabel.textColor = .secondaryLabel
        signatureLabel.numberOfLines = 0
        
        returnTypeLabel.font = .systemFont(ofSize: 12)
        returnTypeLabel.textColor = .tertiaryLabel
        
        parametersLabel.font = .systemFont(ofSize: 12)
        parametersLabel.textColor = .tertiaryLabel
        
        contentView.addSubview(nameLabel)
        contentView.addSubview(signatureLabel)
        contentView.addSubview(returnTypeLabel)
        contentView.addSubview(parametersLabel)
        
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        signatureLabel.translatesAutoresizingMaskIntoConstraints = false
        returnTypeLabel.translatesAutoresizingMaskIntoConstraints = false
        parametersLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            signatureLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            signatureLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            signatureLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            returnTypeLabel.topAnchor.constraint(equalTo: signatureLabel.bottomAnchor, constant: 2),
            returnTypeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            returnTypeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            parametersLabel.topAnchor.constraint(equalTo: returnTypeLabel.bottomAnchor, constant: 2),
            parametersLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            parametersLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            parametersLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }
    
    func configure(with method: TypeMethod) {
        nameLabel.text = method.name
        signatureLabel.text = method.signature
        returnTypeLabel.text = "Returns: \(method.returnType)"
        parametersLabel.text = "Parameters: \(method.parameters.count)"
    }
}

