import UIKit

class ObjCClassesViewController: UIViewController {
    
    // MARK: - UI Elements
    
    private let segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["All", "ObjC", "Swift"])
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
    
    private let totalClassesLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 2
        return label
    }()
    
    private let totalMethodsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 2
        return label
    }()
    
    private let totalPropertiesLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 2
        return label
    }()
    
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = Constants.Colors.primaryBackground
        table.register(ObjCClassCell.self, forCellReuseIdentifier: "ClassCell")
        return table
    }()
    
    private let searchBar: UISearchBar = {
        let search = UISearchBar()
        search.translatesAutoresizingMaskIntoConstraints = false
        search.placeholder = "Search classes..."
        search.searchBarStyle = .minimal
        return search
    }()
    
    // MARK: - Properties
    
    private let objcAnalysis: ObjCAnalysisResult
    private var displayedClasses: [ObjCClass] = []
    private var expandedIndexPaths: Set<IndexPath> = []
    private var searchText: String = ""
    
    // MARK: - Initialization
    
    init(objcAnalysis: ObjCAnalysisResult) {
        self.objcAnalysis = objcAnalysis
        self.displayedClasses = objcAnalysis.classes.sortedByName()
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Objective-C Classes"
        view.backgroundColor = Constants.Colors.primaryBackground
        
        setupUI()
        setupActions()
        setupTableView()
        updateStats()
        filterClasses()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.addSubview(searchBar)
        view.addSubview(segmentedControl)
        view.addSubview(statsView)
        view.addSubview(tableView)
        
        let statsStackView = UIStackView(arrangedSubviews: [totalClassesLabel, totalMethodsLabel, totalPropertiesLabel])
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
        let classesAttr = NSMutableAttributedString()
        classesAttr.append(NSAttributedString(string: "\(objcAnalysis.totalClasses)\n", attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 24, weight: .bold),
            .foregroundColor: Constants.Colors.accentColor
        ]))
        classesAttr.append(NSAttributedString(string: "Classes", attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]))
        totalClassesLabel.attributedText = classesAttr
        
        let methodsAttr = NSMutableAttributedString()
        methodsAttr.append(NSAttributedString(string: "\(objcAnalysis.totalMethods)\n", attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor.systemGreen
        ]))
        methodsAttr.append(NSAttributedString(string: "Methods", attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]))
        totalMethodsLabel.attributedText = methodsAttr
        
        let propsAttr = NSMutableAttributedString()
        propsAttr.append(NSAttributedString(string: "\(objcAnalysis.totalProperties)\n", attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor.systemOrange
        ]))
        propsAttr.append(NSAttributedString(string: "Properties", attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]))
        totalPropertiesLabel.attributedText = propsAttr
    }
    
    @objc private func segmentChanged() {
        filterClasses()
    }
    
    private func filterClasses() {
        var filtered = objcAnalysis.classes
        
        switch segmentedControl.selectedSegmentIndex {
        case 1:
            filtered = filtered.objcClasses()
        case 2:
            filtered = filtered.swiftClasses()
        default:
            break
        }
        
        if !searchText.isEmpty {
            filtered = filtered.filterByName(searchText)
        }
        
        displayedClasses = filtered.sortedByName()
        expandedIndexPaths.removeAll()
        tableView.reloadData()
    }
}

// MARK: - UITableViewDataSource

extension ObjCClassesViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return displayedClasses.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ClassCell", for: indexPath) as! ObjCClassCell
        let objcClass = displayedClasses[indexPath.row]
        let isExpanded = expandedIndexPaths.contains(indexPath)
        cell.configure(with: objcClass, isExpanded: isExpanded)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ObjCClassesViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if expandedIndexPaths.contains(indexPath) {
            expandedIndexPaths.remove(indexPath)
        } else {
            expandedIndexPaths.insert(indexPath)
        }
        
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }
    
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let objcClass = displayedClasses[indexPath.row]
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let copyName = UIAction(title: "Copy Class Name", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.string = objcClass.name
            }
            
            let copyInterface = UIAction(title: "Copy @interface", image: UIImage(systemName: "curlybraces")) { _ in
                UIPasteboard.general.string = self.generateInterfaceDeclaration(for: objcClass)
            }
            
            return UIMenu(title: objcClass.name, children: [copyName, copyInterface])
        }
    }
    
    private func generateInterfaceDeclaration(for objcClass: ObjCClass) -> String {
        var interface = objcClass.interfaceDeclaration + "\n\n"
        
        if !objcClass.properties.isEmpty {
            for property in objcClass.properties {
                let attrs = property.displayAttributes.isEmpty ? "" : "(\(property.displayAttributes)) "
                interface += "@property \(attrs)\(property.propertyType) *\(property.name);\n"
            }
            interface += "\n"
        }
        
        if !objcClass.instanceMethods.isEmpty {
            for method in objcClass.instanceMethods {
                interface += "\(method.displayName);\n"
            }
            interface += "\n"
        }
        
        if !objcClass.classMethods.isEmpty {
            for method in objcClass.classMethods {
                interface += "\(method.displayName);\n"
            }
            interface += "\n"
        }
        
        interface += "@end"
        return interface
    }
}

// MARK: - UISearchBarDelegate

extension ObjCClassesViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.searchText = searchText
        filterClasses()
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - ObjCClassCell

class ObjCClassCell: UITableViewCell {
    
    private let iconLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 24)
        return label
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        return label
    }()
    
    private let superclassLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabel
        return label
    }()
    
    private let countsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .tertiaryLabel
        return label
    }()
    
    private let detailsStackView: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8
        stack.isHidden = true
        return stack
    }()
    
    private var isExpanded = false
    
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
        contentView.addSubview(superclassLabel)
        contentView.addSubview(countsLabel)
        contentView.addSubview(detailsStackView)
        
        NSLayoutConstraint.activate([
            iconLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            iconLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            iconLabel.widthAnchor.constraint(equalToConstant: 30),
            
            nameLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 8),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            
            superclassLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            superclassLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            superclassLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            
            countsLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            countsLabel.topAnchor.constraint(equalTo: superclassLabel.bottomAnchor, constant: 4),
            countsLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            countsLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12),
            
            detailsStackView.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailsStackView.topAnchor.constraint(equalTo: countsLabel.bottomAnchor, constant: 12),
            detailsStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            detailsStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }
    
    func configure(with objcClass: ObjCClass, isExpanded: Bool) {
        self.isExpanded = isExpanded
        
        iconLabel.text = objcClass.isSwift ? "🔷" : "🔶"
        nameLabel.text = objcClass.name
        superclassLabel.text = objcClass.superclassName.isEmpty ? "" : "⬆️ \(objcClass.superclassName)"
        
        let methodCount = objcClass.instanceMethods.count + objcClass.classMethods.count
        let propertyCount = objcClass.properties.count
        let ivarCount = objcClass.ivars.count
        countsLabel.text = "📞 \(methodCount) methods  •  📦 \(propertyCount) properties  •  🔧 \(ivarCount) ivars"
        
        detailsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        if isExpanded {
            if !objcClass.instanceMethods.isEmpty {
                let header = createSectionLabel("Instance Methods (\(objcClass.instanceMethods.count))")
                detailsStackView.addArrangedSubview(header)
                
                for method in objcClass.instanceMethods.prefix(10) {
                    let methodLabel = createMethodLabel(method.displayName)
                    detailsStackView.addArrangedSubview(methodLabel)
                }
                if objcClass.instanceMethods.count > 10 {
                    let more = createDetailLabel("... and \(objcClass.instanceMethods.count - 10) more")
                    detailsStackView.addArrangedSubview(more)
                }
            }
            
            if !objcClass.classMethods.isEmpty {
                let header = createSectionLabel("Class Methods (\(objcClass.classMethods.count))")
                detailsStackView.addArrangedSubview(header)
                
                for method in objcClass.classMethods.prefix(5) {
                    let methodLabel = createMethodLabel(method.displayName)
                    detailsStackView.addArrangedSubview(methodLabel)
                }
                if objcClass.classMethods.count > 5 {
                    let more = createDetailLabel("... and \(objcClass.classMethods.count - 5) more")
                    detailsStackView.addArrangedSubview(more)
                }
            }
            
            if !objcClass.properties.isEmpty {
                let header = createSectionLabel("Properties (\(objcClass.properties.count))")
                detailsStackView.addArrangedSubview(header)
                
                for property in objcClass.properties.prefix(5) {
                    let propLabel = createDetailLabel("@property \(property.propertyType) \(property.name)")
                    detailsStackView.addArrangedSubview(propLabel)
                }
                if objcClass.properties.count > 5 {
                    let more = createDetailLabel("... and \(objcClass.properties.count - 5) more")
                    detailsStackView.addArrangedSubview(more)
                }
            }
            
            detailsStackView.isHidden = false
        } else {
            detailsStackView.isHidden = true
        }
    }
    
    private func createSectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 14, weight: .bold)
        label.textColor = Constants.Colors.accentColor
        return label
    }
    
    private func createMethodLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .label
        label.numberOfLines = 0
        return label
    }
    
    private func createDetailLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }
}

