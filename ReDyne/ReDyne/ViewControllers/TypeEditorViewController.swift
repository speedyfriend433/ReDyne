import UIKit

/// Advanced editor for type definitions
class TypeEditorViewController: UIViewController {
    
    // MARK: - Properties
    
    private let mode: EditorMode
    private var type: ReconstructedType
    private let inferenceEngine: TypeInferenceEngine?
    
    private var isCurrentlyEditing: Bool = false
    
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
    
    private lazy var nameField: UITextField = {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholder = "Type name"
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 16)
        field.isEnabled = isCurrentlyEditing
        return field
    }()
    
    private lazy var categorySegmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: TypeCategory.allCases.map { $0.displayName })
        control.translatesAutoresizingMaskIntoConstraints = false
        control.isEnabled = isCurrentlyEditing
        control.apportionsSegmentWidthsByContent = true
        return control
    }()
    
    private lazy var sizeField: UITextField = {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholder = "Size in bytes"
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 16)
        field.keyboardType = .numberPad
        field.isEnabled = isCurrentlyEditing
        return field
    }()
    
    private lazy var alignmentField: UITextField = {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholder = "Alignment"
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 16)
        field.keyboardType = .numberPad
        field.isEnabled = isCurrentlyEditing
        return field
    }()
    
    private lazy var confidenceSlider: UISlider = {
        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = 0.0
        slider.maximumValue = 1.0
        slider.isEnabled = isCurrentlyEditing
        return slider
    }()
    
    private lazy var confidenceLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16)
        label.textAlignment = .center
        return label
    }()
    
    private lazy var sourceSegmentedControl: UISegmentedControl = {
        let sources = TypeSource.allCases.map { $0.displayName }
        let control = UISegmentedControl(items: sources)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.isEnabled = isCurrentlyEditing
        control.apportionsSegmentWidthsByContent = true
        return control
    }()
    
    private lazy var propertiesTableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(PropertyCell.self, forCellReuseIdentifier: "PropertyCell")
        tableView.backgroundColor = .systemGroupedBackground
        return tableView
    }()
    
    private lazy var methodsTableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(MethodCell.self, forCellReuseIdentifier: "MethodCell")
        tableView.backgroundColor = .systemGroupedBackground
        return tableView
    }()
    
    // MARK: - Initialization
    
    enum EditorMode {
        case create
        case edit
        case view
    }
    
    init(type: ReconstructedType, mode: EditorMode, inferenceEngine: TypeInferenceEngine? = nil) {
        self.type = type
        self.mode = mode
        self.inferenceEngine = inferenceEngine
        super.init(nibName: nil, bundle: nil)
        
        self.isCurrentlyEditing = (mode == .create || mode == .edit)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupNavigationBar()
        populateFields()
        setupKeyboardHandling()
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = .systemGroupedBackground
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(nameField)
        contentView.addSubview(categorySegmentedControl)
        contentView.addSubview(sizeField)
        contentView.addSubview(alignmentField)
        contentView.addSubview(confidenceSlider)
        contentView.addSubview(confidenceLabel)
        contentView.addSubview(sourceSegmentedControl)
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
            
            nameField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            nameField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            nameField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            categorySegmentedControl.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 16),
            categorySegmentedControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            categorySegmentedControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            sizeField.topAnchor.constraint(equalTo: categorySegmentedControl.bottomAnchor, constant: 16),
            sizeField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            sizeField.trailingAnchor.constraint(equalTo: contentView.centerXAnchor, constant: -10),
            
            alignmentField.topAnchor.constraint(equalTo: categorySegmentedControl.bottomAnchor, constant: 16),
            alignmentField.leadingAnchor.constraint(equalTo: contentView.centerXAnchor, constant: 10),
            alignmentField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            confidenceSlider.topAnchor.constraint(equalTo: sizeField.bottomAnchor, constant: 16),
            confidenceSlider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            confidenceSlider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            confidenceLabel.topAnchor.constraint(equalTo: confidenceSlider.bottomAnchor, constant: 8),
            confidenceLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            confidenceLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            sourceSegmentedControl.topAnchor.constraint(equalTo: confidenceLabel.bottomAnchor, constant: 16),
            sourceSegmentedControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            sourceSegmentedControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            propertiesTableView.topAnchor.constraint(equalTo: sourceSegmentedControl.bottomAnchor, constant: 16),
            propertiesTableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            propertiesTableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            propertiesTableView.heightAnchor.constraint(equalToConstant: 150),
            
            methodsTableView.topAnchor.constraint(equalTo: propertiesTableView.bottomAnchor, constant: 16),
            methodsTableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            methodsTableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            methodsTableView.heightAnchor.constraint(equalToConstant: 150),
            methodsTableView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
    }
    
    private func setupNavigationBar() {
        if isCurrentlyEditing {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .cancel,
                target: self,
                action: #selector(cancelTapped)
            )
            
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .save,
                target: self,
                action: #selector(saveTapped)
            )
        } else {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .edit,
                target: self,
                action: #selector(editTapped)
            )
        }
        
        title = mode == .create ? "New Type" : "Edit Type"
    }
    
    private func populateFields() {
        nameField.text = type.name
        
        if let categoryIndex = TypeCategory.allCases.firstIndex(of: type.category) {
            categorySegmentedControl.selectedSegmentIndex = categoryIndex
        }
        
        sizeField.text = "\(type.size)"
        alignmentField.text = "\(type.alignment)"
        confidenceSlider.value = Float(type.confidence)
        updateConfidenceLabel()
        
        if let sourceIndex = TypeSource.allCases.firstIndex(of: type.source) {
            sourceSegmentedControl.selectedSegmentIndex = sourceIndex
        }
    }
    
    private func setupKeyboardHandling() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
        
        confidenceSlider.addTarget(self, action: #selector(confidenceChanged), for: .valueChanged)
    }
    
    // MARK: - Actions
    
    @objc private func cancelTapped() {
        if mode == .create {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }
    
    @objc private func saveTapped() {
        // Validate and save type
        guard validateInput() else { return }
        
        updateTypeFromFields()
        
        // Save type (would integrate with persistence layer)
        let alert = UIAlertController(
            title: "Type Saved",
            message: "Type '\(type.name)' has been saved successfully.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            self.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }
    
    @objc private func editTapped() {
        isCurrentlyEditing = true
        setupNavigationBar()
        updateFieldStates()
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    @objc private func confidenceChanged() {
        updateConfidenceLabel()
    }
    
    private func updateConfidenceLabel() {
        let confidence = Int(confidenceSlider.value * 100)
        confidenceLabel.text = "Confidence: \(confidence)%"
    }
    
    private func updateFieldStates() {
        nameField.isEnabled = isEditing
        categorySegmentedControl.isEnabled = isEditing
        sizeField.isEnabled = isEditing
        alignmentField.isEnabled = isEditing
        confidenceSlider.isEnabled = isEditing
        sourceSegmentedControl.isEnabled = isEditing
    }
    
    private func validateInput() -> Bool {
        guard let name = nameField.text, !name.isEmpty else {
            showError("Type name is required")
            return false
        }
        
        guard let sizeText = sizeField.text, let size = Int(sizeText), size > 0 else {
            showError("Size must be a positive integer")
            return false
        }
        
        guard let alignmentText = alignmentField.text, let alignment = Int(alignmentText), alignment > 0 else {
            showError("Alignment must be a positive integer")
            return false
        }
        
        return true
    }
    
    private func updateTypeFromFields() {
        // Update type with field values
        // In a real implementation, this would update the actual type object
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension TypeEditorViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        if tableView == propertiesTableView {
            return 1
        } else {
            return 1
        }
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
            let cell = tableView.dequeueReusableCell(withIdentifier: "PropertyCell", for: indexPath) as! PropertyCell
            let property = type.properties[indexPath.row]
            cell.configure(with: property)
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "MethodCell", for: indexPath) as! MethodCell
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

extension TypeEditorViewController: UITableViewDelegate {
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
            message: "Type: \(property.type)\nOffset: \(property.offset)\nSize: \(property.size)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func showMethodDetail(_ method: TypeMethod) {
        let alert = UIAlertController(
            title: method.name,
            message: "Signature: \(method.signature)\nReturn Type: \(method.returnType)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Supporting Cells

class PropertyCell: UITableViewCell {
    private let nameLabel = UILabel()
    private let typeLabel = UILabel()
    private let offsetLabel = UILabel()
    
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
        
        contentView.addSubview(nameLabel)
        contentView.addSubview(typeLabel)
        contentView.addSubview(offsetLabel)
        
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        offsetLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            typeLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            typeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            typeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            offsetLabel.topAnchor.constraint(equalTo: typeLabel.bottomAnchor, constant: 2),
            offsetLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            offsetLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            offsetLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }
    
    func configure(with property: TypeProperty) {
        nameLabel.text = property.name
        typeLabel.text = property.type
        offsetLabel.text = "Offset: \(property.offset), Size: \(property.size)"
    }
}

class MethodCell: UITableViewCell {
    private let nameLabel = UILabel()
    private let signatureLabel = UILabel()
    private let returnTypeLabel = UILabel()
    
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
        
        contentView.addSubview(nameLabel)
        contentView.addSubview(signatureLabel)
        contentView.addSubview(returnTypeLabel)
        
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        signatureLabel.translatesAutoresizingMaskIntoConstraints = false
        returnTypeLabel.translatesAutoresizingMaskIntoConstraints = false
        
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
            returnTypeLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }
    
    func configure(with method: TypeMethod) {
        nameLabel.text = method.name
        signatureLabel.text = method.signature
        returnTypeLabel.text = "Returns: \(method.returnType)"
    }
}
