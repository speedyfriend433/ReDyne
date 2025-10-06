import UIKit

class ResultsViewController: UIViewController {
    
    // MARK: - UI Elements
    
    private lazy var segmentedControl: UISegmentedControl = {
        let items = ["Info", "Symbols", "Strings", "Code", "Functions"]
        let control = UISegmentedControl(items: items)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        return control
    }()
    
    private let containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var searchBar: UISearchBar = {
        let search = UISearchBar()
        search.translatesAutoresizingMaskIntoConstraints = false
        search.placeholder = "Search..."
        search.delegate = self
        search.searchBarStyle = .minimal
        return search
    }()
    
    // MARK: - Child View Controllers
    
    private lazy var headerViewController: HeaderViewController = {
        return HeaderViewController(output: output)
    }()
    
    private lazy var symbolsViewController: SymbolsViewController = {
        return SymbolsViewController(symbols: output.symbols)
    }()
    
    private lazy var stringsViewController: StringsViewController = {
        return StringsViewController(strings: output.strings)
    }()
    
    private lazy var disassemblyViewController: DisassemblyViewController = {
        return DisassemblyViewController(instructions: output.instructions)
    }()
    
    private lazy var functionsViewController: FunctionsViewController = {
        return FunctionsViewController(functions: output.functions)
    }()
    
    private lazy var xrefsViewController: XrefsViewController? = {
        guard let xrefAnalysis = output.xrefAnalysis as? XrefAnalysisResult else { return nil }
        return XrefsViewController(xrefAnalysis: xrefAnalysis)
    }()
    
    private lazy var objcClassesViewController: ObjCClassesViewController? = {
        guard let objcAnalysis = output.objcAnalysis as? ObjCAnalysisResult else { return nil }
        return ObjCClassesViewController(objcAnalysis: objcAnalysis)
    }()
    
    private lazy var importsExportsViewController: ImportsExportsViewController? = {
        guard let importExportAnalysis = output.importExportAnalysis as? ImportExportAnalysis else { return nil }
        return ImportsExportsViewController(analysis: importExportAnalysis)
    }()
    
    private lazy var dependencyViewController: DependencyViewController? = {
        guard let importExportAnalysis = output.importExportAnalysis as? ImportExportAnalysis,
              let dependencyAnalysis = importExportAnalysis.dependencyAnalysis else { return nil }
        return DependencyViewController(dependencyAnalysis: dependencyAnalysis)
    }()
    
    private lazy var codeSignatureViewController: CodeSignatureViewController? = {
        guard let codeSignAnalysis = output.codeSigningAnalysis as? CodeSigningAnalysis else { return nil }
        return CodeSignatureViewController(analysis: codeSignAnalysis)
    }()
    
    private lazy var cfgViewController: CFGViewController? = {
        guard let cfgAnalysis = output.cfgAnalysis as? CFGAnalysisResult else { return nil }
        return CFGViewController(cfgAnalysis: cfgAnalysis)
    }()
    
    // MARK: - Properties
    
    private let output: DecompiledOutput
    private var currentViewController: UIViewController?
    
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
        
        title = output.fileName
        view.backgroundColor = Constants.Colors.primaryBackground
        
        setupUI()
        setupNavigationBar()
        
        showViewController(headerViewController)
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.addSubview(segmentedControl)
        view.addSubview(searchBar)
        view.addSubview(containerView)
        
        searchBar.isHidden = true
        
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Constants.UI.compactSpacing),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.UI.standardSpacing),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.UI.standardSpacing),
            
            searchBar.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: Constants.UI.compactSpacing),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            containerView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupNavigationBar() {
        let exportButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(showExportOptions)
        )
        
        let moreButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: self,
            action: #selector(showMoreOptions)
        )
        
        let infoButton = UIBarButtonItem(
            image: UIImage(systemName: "info.circle"),
            style: .plain,
            target: self,
            action: #selector(showInfo)
        )
        
        navigationItem.rightBarButtonItems = [exportButton, moreButton, infoButton]
    }
    
    @objc private func showMoreOptions() {
        let menuVC = AnalysisMenuViewController(style: .insetGrouped)
        menuVC.delegate = self
        let navController = UINavigationController(rootViewController: menuVC)
        present(navController, animated: true)
    }
    
    // MARK: - View Management
    
    private func showViewController(_ viewController: UIViewController) {
        if let current = currentViewController {
            current.willMove(toParent: nil)
            current.view.removeFromSuperview()
            current.removeFromParent()
        }
        
        addChild(viewController)
        containerView.addSubview(viewController.view)
        viewController.view.frame = containerView.bounds
        viewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        viewController.didMove(toParent: self)
        
        currentViewController = viewController
        
        searchBar.isHidden = (segmentedControl.selectedSegmentIndex == 0)
    }
    
    @objc private func segmentChanged() {
        searchBar.text = ""
        searchBar.resignFirstResponder()
        
        switch segmentedControl.selectedSegmentIndex {
        case 0:
            showViewController(headerViewController)
        case 1:
            showViewController(symbolsViewController)
        case 2:
            showViewController(stringsViewController)
        case 3:
            showViewController(disassemblyViewController)
        case 4:
            showViewController(functionsViewController)
        default:
            break
        }
    }
    
    // MARK: - Actions
    
    @objc private func showExportOptions() {
        let alert = UIAlertController(title: "Export Analysis", message: "Choose export format", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "📄 Plain Text (.txt)", style: .default) { [weak self] _ in
            self?.export(format: .text)
        })
        
        alert.addAction(UIAlertAction(title: "🌐 HTML Report (.html)", style: .default) { [weak self] _ in
            self?.export(format: .html)
        })
        
        alert.addAction(UIAlertAction(title: "📋 JSON Data (.json)", style: .default) { [weak self] _ in
            self?.export(format: .json)
        })
        
        alert.addAction(UIAlertAction(title: "📤 Quick Share", style: .default) { [weak self] _ in
            self?.quickShare()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        
        present(alert, animated: true)
    }
    
    @objc private func showInfo() {
        let info = """
        File: \(output.fileName)
        Size: \(Constants.formatBytes(Int64(output.fileSize)))
        
        Architecture: \(output.header.cpuType)
        File Type: \(output.header.fileType)
        
        Segments: \(output.segments.count)
        Sections: \(output.sections.count)
        Symbols: \(output.totalSymbols)
        Instructions: \(output.totalInstructions)
        Functions: \(output.totalFunctions)
        
        Processing Time: \(Constants.formatDuration(output.processingTime))
        """
        
        let alert = UIAlertController(title: "Binary Information", message: info, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - Export Methods
    
    private func export(format: ExportFormat) {
        guard let data = ExportService.export(output, format: format) else {
            showAlert(title: "Export Failed", message: "Could not generate \(format.displayName) export.")
            return
        }
        
        let filename = ExportService.generateFilename(for: output, format: format)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        do {
            try data.write(to: tempURL)
            
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            
            if let popover = activityVC.popoverPresentationController {
                popover.barButtonItem = navigationItem.rightBarButtonItems?.first
            }
            
            activityVC.completionWithItemsHandler = { _, completed, _, error in
                if completed {
                    print("Exported successfully: \(filename)")
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    try? FileManager.default.removeItem(at: tempURL)
                }
            }
            
            present(activityVC, animated: true)
            
        } catch {
            showAlert(title: "Export Failed", message: "Error writing file: \(error.localizedDescription)")
        }
    }
    
    private func quickShare() {
        guard let data = ExportService.export(output, format: .text),
              let text = String(data: data, encoding: .utf8) else {
            showAlert(title: "Share Failed", message: "Could not generate report.")
            return
        }
        
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        
        if let popover = activityVC.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        
        present(activityVC, animated: true)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UISearchBarDelegate

extension ResultsViewController: UISearchBarDelegate {
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if let symbolsVC = currentViewController as? SymbolsViewController {
            symbolsVC.filterSymbols(query: searchText)
        } else if let stringsVC = currentViewController as? StringsViewController {
            stringsVC.filterStrings(query: searchText)
        } else if let disassemblyVC = currentViewController as? DisassemblyViewController {
            disassemblyVC.filterInstructions(query: searchText)
        } else if let functionsVC = currentViewController as? FunctionsViewController {
            functionsVC.filterFunctions(query: searchText)
        }
    }
    
    private func showNoDataAvailable(type: String) {
        let alert = UIAlertController(
            title: "No \(type) Data",
            message: "\(type) analysis is not available for this binary.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - Analysis Menu Delegate

extension ResultsViewController: AnalysisMenuDelegate {
    func didSelectAnalysisType(_ type: AnalysisType) {
        switch type {
        case .xrefs:
            if let xrefsVC = xrefsViewController {
                navigationController?.pushViewController(xrefsVC, animated: true)
            } else {
                showNoDataAvailable(type: "Xref")
            }
        case .objc:
            if let objcVC = objcClassesViewController {
                navigationController?.pushViewController(objcVC, animated: true)
            } else {
                showNoDataAvailable(type: "Objective-C")
            }
        case .imports:
            if let importExportVC = importsExportsViewController {
                navigationController?.pushViewController(importExportVC, animated: true)
            } else {
                showNoDataAvailable(type: "Import/Export")
            }
        case .dependencies:
            if let dependencyVC = dependencyViewController {
                navigationController?.pushViewController(dependencyVC, animated: true)
            } else {
                showNoDataAvailable(type: "Dependency")
            }
        case .signature:
            if let codeSignVC = codeSignatureViewController {
                navigationController?.pushViewController(codeSignVC, animated: true)
            } else {
                showNoDataAvailable(type: "Code Signature")
            }
        case .cfg:
            if let cfgVC = cfgViewController {
                navigationController?.pushViewController(cfgVC, animated: true)
            } else {
                showNoDataAvailable(type: "CFG")
            }
        }
    }
}

// MARK: - Child View Controllers (50% done)

class HeaderViewController: UIViewController {
    private let output: DecompiledOutput
    private let textView = UITextView()
    
    init(output: DecompiledOutput) {
        self.output = output
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        textView.frame = view.bounds
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        
        view.addSubview(textView)
        
        loadHeaderInfo()
    }
    
    private func loadHeaderInfo() {
        var text = "=== Mach-O Header ===\n\n"
        text += "CPU Type: \(output.header.cpuType)\n"
        text += "File Type: \(output.header.fileType)\n"
        text += "Architecture: \(output.header.is64Bit ? "64-bit" : "32-bit")\n"
        text += "Load Commands: \(output.header.ncmds)\n"
        text += "Flags: 0x\(String(format: "%X", output.header.flags))\n"
        if let uuid = output.header.uuid {
            text += "UUID: \(uuid)\n"
        }
        text += "Encrypted: \(output.header.isEncrypted ? "Yes" : "No")\n\n"
        
        text += "=== Segments (\(output.segments.count)) ===\n\n"
        for segment in output.segments {
            let paddedName = segment.name.padding(toLength: 16, withPad: " ", startingAt: 0)
            text += String(format: "%@ VM: 0x%016llX-0x%016llX  File: 0x%016llX-0x%016llX  %@\n",
                          paddedName, segment.vmAddress, segment.vmAddress + segment.vmSize,
                          segment.fileOffset, segment.fileOffset + segment.fileSize, segment.protection)
        }
        
        textView.text = text
    }
}

class SymbolsViewController: UITableViewController {
    private var symbols: [SymbolModel]
    private var filteredSymbols: [SymbolModel]
    
    init(symbols: [SymbolModel]) {
        self.symbols = symbols.sortedByAddress()
        self.filteredSymbols = self.symbols
        super.init(style: .plain)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SymbolCell")
        tableView.rowHeight = 44
    }
    
    func filterSymbols(query: String) {
        if query.isEmpty {
            filteredSymbols = symbols
        } else {
            filteredSymbols = symbols.searchSymbols(query: query) as! [SymbolModel]
        }
        tableView.reloadData()
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredSymbols.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SymbolCell", for: indexPath)
        let symbol = filteredSymbols[indexPath.row]
        
        cell.textLabel?.text = "\(Constants.formatAddress(symbol.address)) \(symbol.name)"
        cell.textLabel?.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        cell.detailTextLabel?.text = "\(symbol.type) | \(symbol.scope)"
        
        return cell
    }
}

class StringsViewController: UITableViewController {
    private var strings: [StringModel]
    private var filteredStrings: [StringModel]
    
    init(strings: [StringModel]) {
        self.strings = strings.sortedByAddress()
        self.filteredStrings = self.strings
        super.init(style: .plain)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "StringCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44
    }
    
    func filterStrings(query: String) {
        if query.isEmpty {
            filteredStrings = strings
        } else {
            filteredStrings = strings.filter { $0.content.localizedCaseInsensitiveContains(query) }
        }
        tableView.reloadData()
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredStrings.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "StringCell", for: indexPath)
        let string = filteredStrings[indexPath.row]
        
        var content = cell.defaultContentConfiguration()
        content.text = string.content
        content.secondaryText = "\(Constants.formatAddress(string.address)) - \(string.section)"
        content.textProperties.font = .systemFont(ofSize: 13)
        content.textProperties.numberOfLines = 2
        content.secondaryTextProperties.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        content.secondaryTextProperties.color = .secondaryLabel
        
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let string = filteredStrings[indexPath.row]
        let alert = UIAlertController(title: "String Details", message: nil, preferredStyle: .alert)
        
        let details = """
        Address: \(Constants.formatAddress(string.address))
        Offset: 0x\(String(format: "%llX", string.offset))
        Length: \(string.length) bytes
        Section: \(string.section)
        Type: \(string.isCString ? "C String" : "Data String")
        
        Content:
        \(string.content)
        """
        
        alert.message = details
        alert.addAction(UIAlertAction(title: "Copy Address", style: .default) { _ in
            UIPasteboard.general.string = Constants.formatAddress(string.address)
        })
        alert.addAction(UIAlertAction(title: "Copy Content", style: .default) { _ in
            UIPasteboard.general.string = string.content
        })
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        
        present(alert, animated: true)
    }
}

class DisassemblyViewController: UITableViewController {
    private var instructions: [InstructionModel]
    private var filteredInstructions: [InstructionModel]
    
    init(instructions: [InstructionModel]) {
        self.instructions = instructions
        self.filteredInstructions = instructions
        super.init(style: .plain)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "InstructionCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 30
    }
    
    func filterInstructions(query: String) {
        if query.isEmpty {
            filteredInstructions = instructions
        } else {
            filteredInstructions = instructions.search(mnemonic: query)
        }
        tableView.reloadData()
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return min(filteredInstructions.count, Constants.Disassembly.maxInstructionsDisplay)
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "InstructionCell", for: indexPath)
        let instruction = filteredInstructions[indexPath.row]
        
        cell.textLabel?.attributedText = instruction.attributedString()
        cell.textLabel?.numberOfLines = 0
        
        return cell
    }
}

class FunctionsViewController: UITableViewController {
    private var functions: [FunctionModel]
    private var filteredFunctions: [FunctionModel]
    
    init(functions: [FunctionModel]) {
        self.functions = functions.sortedByAddress()
        self.filteredFunctions = self.functions
        super.init(style: .plain)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FunctionCell")
    }
    
    func filterFunctions(query: String) {
        if query.isEmpty {
            filteredFunctions = functions
        } else {
            filteredFunctions = functions.search(name: query)
        }
        tableView.reloadData()
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredFunctions.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FunctionCell", for: indexPath)
        let function = filteredFunctions[indexPath.row]
        
        cell.textLabel?.text = function.name
        cell.textLabel?.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        cell.detailTextLabel?.text = "\(Constants.formatAddress(function.startAddress)) - \(function.instructionCount) instructions"
        cell.accessoryType = .disclosureIndicator
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let function = filteredFunctions[indexPath.row]
        
        let detailVC = FunctionDetailViewController(function: function)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

// MARK: - Function Detail View Controller

class FunctionDetailViewController: UIViewController {
    private let function: FunctionModel
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let textView = UITextView()
    
    init(function: FunctionModel) {
        self.function = function
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = function.name
        view.backgroundColor = Constants.Colors.primaryBackground
        
        setupUI()
        displayFunctionDetails()
    }
    
    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(textView)
        
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = Constants.Colors.secondaryBackground
        textView.textColor = .label
        textView.layer.cornerRadius = 8
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        
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
            
            textView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            textView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 400)
        ])
    }
    
    private func displayFunctionDetails() {
        var details = ""
        
        details += "╔═══════════════════════════════════════╗\n"
        details += "║          FUNCTION DETAILS             ║\n"
        details += "╚═══════════════════════════════════════╝\n\n"
        
        details += "Name:          \(function.name)\n"
        details += "Start Address: \(Constants.formatAddress(function.startAddress))\n"
        details += "End Address:   \(Constants.formatAddress(function.endAddress))\n"
        
        let size: String
        if function.endAddress >= function.startAddress {
            let sizeBytes = function.endAddress - function.startAddress
            size = "\(sizeBytes) bytes"
        } else {
            size = "Invalid (end < start)"
        }
        details += "Size:          \(size)\n"
        details += "Instructions:  \(function.instructionCount)\n\n"
        
        details += "╔═══════════════════════════════════════╗\n"
        details += "║          DISASSEMBLY                  ║\n"
        details += "╚═══════════════════════════════════════╝\n\n"
        
        if let instructions = function.instructions as? [InstructionModel] {
            for inst in instructions.prefix(100) { // you can set any values instead of 100 (but for me, 100 was enough to look around)
                details += "\(inst.fullDisassembly)\n"
            }
            
            if instructions.count > 100 {
                details += "\n... (\(instructions.count - 100) more instructions)\n"
            }
        }
        
        textView.text = details
    }
}

