import UIKit

protocol AnalysisMenuDelegate: AnyObject {
    func didSelectAnalysisType(_ type: AnalysisType)
}

enum AnalysisType: String, CaseIterable {
    case xrefs = "Cross-References"
    case objc = "ObjC Classes"
    case imports = "Imports/Exports"
    case dependencies = "Dependencies"
    case signature = "Code Signature"
    case cfg = "Control Flow Graphs"
    case memoryMap = "Memory Map"
    
    var icon: String {
        switch self {
        case .xrefs: return "arrow.triangle.branch"
        case .objc: return "cube.box"
        case .imports: return "arrow.left.arrow.right"
        case .dependencies: return "link"
        case .signature: return "checkmark.seal"
        case .cfg: return "point.3.connected.trianglepath.dotted"
        case .memoryMap: return "square.stack.3d.up"
        }
    }
    
    var description: String {
        switch self {
        case .xrefs: return "Function calls and references"
        case .objc: return "Objective-C runtime classes"
        case .imports: return "Imported and exported symbols"
        case .dependencies: return "Linked libraries with versions"
        case .signature: return "Code signing and entitlements"
        case .cfg: return "Visual control flow graphs"
        case .memoryMap: return "Visual segment and section layout"
        }
    }
}

class AnalysisMenuViewController: UITableViewController {

    weak var delegate: AnalysisMenuDelegate?

    // Analysis availability flags
    private let hasObjCData: Bool
    private let hasCodeSignature: Bool
    private let availableTypes: [AnalysisType]

    init(hasObjCData: Bool = false, hasCodeSignature: Bool = false) {
        self.hasObjCData = hasObjCData
        self.hasCodeSignature = hasCodeSignature

        // Filter available analysis types based on data availability
        var types = [AnalysisType]()
        for type in AnalysisType.allCases {
            switch type {
            case .objc:
                if hasObjCData { types.append(type) }
            case .signature:
                if hasCodeSignature { types.append(type) }
            default:
                types.append(type) // Always show other types
            }
        }
        self.availableTypes = types

        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Advanced Analysis"
        tableView.register(AnalysisMenuCell.self, forCellReuseIdentifier: "Cell")
        tableView.backgroundColor = Constants.Colors.primaryBackground
    }
    
    // MARK: - Table View
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return availableTypes.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! AnalysisMenuCell
        let type = availableTypes[indexPath.row]
        cell.configure(with: type)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let type = availableTypes[indexPath.row]
        delegate?.didSelectAnalysisType(type)
        dismiss(animated: true)
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 70
    }
}

class AnalysisMenuCell: UITableViewCell {
    
    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = Constants.Colors.accentColor
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        return label
    }()
    
    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabel
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
        contentView.addSubview(iconImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(descriptionLabel)
        
        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 32),
            iconImageView.heightAnchor.constraint(equalToConstant: 32),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            descriptionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            descriptionLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            descriptionLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12)
        ])
    }
    
    func configure(with type: AnalysisType) {
        iconImageView.image = UIImage(systemName: type.icon)
        titleLabel.text = type.rawValue
        descriptionLabel.text = type.description
        accessoryType = .disclosureIndicator
    }
}

