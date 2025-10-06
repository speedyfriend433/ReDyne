import UIKit

class XrefsViewController: UIViewController {
    
    // MARK: - UI Elements
    
    private let segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Calls", "Jumps", "Data Refs", "All"])
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
    
    private let totalXrefsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 2
        return label
    }()
    
    private let totalCallsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 2
        return label
    }()
    
    private let totalJumpsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 2
        return label
    }()
    
    private let totalDataRefsLabel: UILabel = {
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
        table.register(XrefCell.self, forCellReuseIdentifier: "XrefCell")
        return table
    }()
    
    private let searchBar: UISearchBar = {
        let search = UISearchBar()
        search.translatesAutoresizingMaskIntoConstraints = false
        search.placeholder = "Search xrefs..."
        search.searchBarStyle = .minimal
        return search
    }()
    
    // MARK: - Properties
    
    private let xrefAnalysis: XrefAnalysisResult
    private var displayedXrefs: [CrossReference] = []
    private var filteredXrefs: [CrossReference] = []
    private var searchText: String = ""
    
    // MARK: - Initialization
    
    init(xrefAnalysis: XrefAnalysisResult) {
        self.xrefAnalysis = xrefAnalysis
        self.displayedXrefs = xrefAnalysis.allXrefs
        self.filteredXrefs = xrefAnalysis.allXrefs
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Cross-References"
        view.backgroundColor = Constants.Colors.primaryBackground
        
        setupUI()
        setupActions()
        setupTableView()
        updateStats()
        filterXrefs()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.addSubview(searchBar)
        view.addSubview(segmentedControl)
        view.addSubview(statsView)
        view.addSubview(tableView)
        
        let statsStackView = UIStackView(arrangedSubviews: [totalXrefsLabel, totalCallsLabel, totalJumpsLabel, totalDataRefsLabel])
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
            statsView.heightAnchor.constraint(equalToConstant: 80),
            
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
        totalAttr.append(NSAttributedString(string: "\(xrefAnalysis.totalXrefs)\n", attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 24, weight: .bold),
            .foregroundColor: Constants.Colors.accentColor
        ]))
        totalAttr.append(NSAttributedString(string: "Total", attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]))
        totalXrefsLabel.attributedText = totalAttr
        
        let callsAttr = NSMutableAttributedString()
        callsAttr.append(NSAttributedString(string: "\(xrefAnalysis.totalCalls)\n", attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor.systemGreen
        ]))
        callsAttr.append(NSAttributedString(string: "Calls", attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]))
        totalCallsLabel.attributedText = callsAttr
        
        let jumpsAttr = NSMutableAttributedString()
        jumpsAttr.append(NSAttributedString(string: "\(xrefAnalysis.totalJumps)\n", attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor.systemOrange
        ]))
        jumpsAttr.append(NSAttributedString(string: "Jumps", attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]))
        totalJumpsLabel.attributedText = jumpsAttr
        
        let dataAttr = NSMutableAttributedString()
        dataAttr.append(NSAttributedString(string: "\(xrefAnalysis.totalDataRefs)\n", attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor.systemBlue
        ]))
        dataAttr.append(NSAttributedString(string: "Data", attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]))
        totalDataRefsLabel.attributedText = dataAttr
    }
    
    @objc private func segmentChanged() {
        filterXrefs()
    }
    
    private func filterXrefs() {
        var typeFiltered: [CrossReference] = []
        
        switch segmentedControl.selectedSegmentIndex {
        case 0:
            typeFiltered = xrefAnalysis.allXrefs.calls()
        case 1:
            typeFiltered = xrefAnalysis.allXrefs.jumps()
        case 2:
            typeFiltered = xrefAnalysis.allXrefs.dataReferences()
        case 3:
            typeFiltered = xrefAnalysis.allXrefs
        default:
            typeFiltered = xrefAnalysis.allXrefs
        }
        
        if searchText.isEmpty {
            filteredXrefs = typeFiltered
        } else {
            filteredXrefs = typeFiltered.filter { xref in
                xref.fromSymbol.localizedCaseInsensitiveContains(searchText) ||
                xref.toSymbol.localizedCaseInsensitiveContains(searchText) ||
                xref.instruction.localizedCaseInsensitiveContains(searchText) ||
                Constants.formatAddress(xref.fromAddress).contains(searchText) ||
                Constants.formatAddress(xref.toAddress).contains(searchText)
            }
        }
        
        filteredXrefs.sort { $0.fromAddress < $1.fromAddress }
        
        tableView.reloadData()
    }
}

// MARK: - UITableViewDataSource

extension XrefsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredXrefs.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "XrefCell", for: indexPath) as! XrefCell
        let xref = filteredXrefs[indexPath.row]
        cell.configure(with: xref)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension XrefsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let xref = filteredXrefs[indexPath.row]
        showXrefDetail(xref)
    }
    
    private func showXrefDetail(_ xref: CrossReference) {
        let alert = UIAlertController(title: "Cross-Reference Details", message: nil, preferredStyle: .alert)
        
        let message = """
        Type: \(xref.xrefType.displayName) \(xref.xrefType.symbol)
        
        From: \(Constants.formatAddress(xref.fromAddress))
        \(xref.fromSymbol.isEmpty ? "" : "Symbol: \(xref.fromSymbol)\n")
        To: \(Constants.formatAddress(xref.toAddress))
        \(xref.toSymbol.isEmpty ? "" : "Symbol: \(xref.toSymbol)\n")
        Instruction:
        \(xref.instruction)
        """
        
        let messageAttr = NSMutableAttributedString(string: message)
        alert.setValue(messageAttr, forKey: "attributedMessage")
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UISearchBarDelegate

extension XrefsViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.searchText = searchText
        filterXrefs()
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - XrefCell

class XrefCell: UITableViewCell {
    
    private let typeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 24)
        label.textAlignment = .center
        return label
    }()
    
    private let fromLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        label.numberOfLines = 0
        return label
    }()
    
    private let arrowLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "→"
        label.font = .systemFont(ofSize: 18, weight: .bold)
        label.textColor = .secondaryLabel
        return label
    }()
    
    private let toLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        label.numberOfLines = 0
        return label
    }()
    
    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
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
        contentView.addSubview(typeLabel)
        contentView.addSubview(fromLabel)
        contentView.addSubview(arrowLabel)
        contentView.addSubview(toLabel)
        contentView.addSubview(instructionLabel)
        
        NSLayoutConstraint.activate([
            typeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            typeLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            typeLabel.widthAnchor.constraint(equalToConstant: 40),
            
            fromLabel.leadingAnchor.constraint(equalTo: typeLabel.trailingAnchor, constant: 8),
            fromLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            fromLabel.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.35),
            
            arrowLabel.leadingAnchor.constraint(equalTo: fromLabel.trailingAnchor, constant: 8),
            arrowLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            arrowLabel.widthAnchor.constraint(equalToConstant: 20),
            
            toLabel.leadingAnchor.constraint(equalTo: arrowLabel.trailingAnchor, constant: 8),
            toLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            toLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            
            instructionLabel.leadingAnchor.constraint(equalTo: typeLabel.trailingAnchor, constant: 8),
            instructionLabel.topAnchor.constraint(equalTo: fromLabel.bottomAnchor, constant: 4),
            instructionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            instructionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }
    
    func configure(with xref: CrossReference) {
        typeLabel.text = xref.xrefType.symbol
        
        var fromText = Constants.formatAddress(xref.fromAddress)
        if !xref.fromSymbol.isEmpty {
            fromText += "\n\(xref.fromSymbol)"
        }
        fromLabel.text = fromText
        
        var toText = Constants.formatAddress(xref.toAddress)
        if !xref.toSymbol.isEmpty {
            toText += "\n\(xref.toSymbol)"
        }
        toLabel.text = toText
        
        instructionLabel.text = xref.instruction
        
        switch xref.xrefType {
        case .call:
            typeLabel.textColor = .systemGreen
        case .jump, .conditionalJump:
            typeLabel.textColor = .systemOrange
        case .dataRead, .dataWrite:
            typeLabel.textColor = .systemBlue
        case .addressLoad:
            typeLabel.textColor = .systemPurple
        case .unknown:
            typeLabel.textColor = .systemGray
        }
    }
}

