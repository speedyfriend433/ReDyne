import UIKit

class ResultsViewController: UIViewController {
    
    // MARK: - Static Properties
    
    static var currentBinaryPath: String?
    
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
        let vc = FunctionsViewController(functions: output.functions)
        vc.setInstructions(output.instructions)
        return vc
    }()
    
    private lazy var typesViewController: TypesViewController = {
        return TypesViewController(output: output)
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
    
    private lazy var memoryMapViewController: MemoryMapViewController = {
        let segments = output.segments as NSArray as! [SegmentModel]
        let sections = output.sections as NSArray as! [SectionModel]
        let baseAddress = segments.map { $0.vmAddress }.min() ?? 0
        return MemoryMapViewController(
            segments: segments,
            sections: sections,
            fileSize: output.fileSize,
            baseAddress: baseAddress
        )
    }()
    
    // MARK: - Properties
    
    private let output: DecompiledOutput
    private var currentViewController: UIViewController?
    
    // MARK: - Initialization
    
    init(output: DecompiledOutput) {
        self.output = output
        super.init(nibName: nil, bundle: nil)
        
        ResultsViewController.currentBinaryPath = output.filePath
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
        let objcResult = output.objcAnalysis as? ObjCAnalysisResult
        let hasObjCData = objcResult != nil && objcResult!.totalClasses > 0
        let hasCodeSignature = output.codeSigningAnalysis != nil

        let menuVC = AnalysisMenuViewController(hasObjCData: hasObjCData, hasCodeSignature: hasCodeSignature)
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
        case .memoryMap:
            navigationController?.pushViewController(memoryMapViewController, animated: true)
        case .pseudocode:
            print("Pseudocode generation selected")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.showPseudocodeSelector()
            }
        case .binaryPatching:
            print("Binary patching selected")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.showBinaryPatchingDashboard()
            }
        case .typeReconstruction:
            print("Type reconstruction selected")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.showTypeReconstruction()
            }
        case .classDump:
            print("Class dump selected")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.showClassDump()
            }
        }
    }
    
    private func showPseudocodeSelector() {
        print("showPseudocodeSelector() called")
        print("Presenting view controller: \(String(describing: presentingViewController))")
        print("Presented view controller: \(String(describing: presentedViewController))")
        
        let alert = UIAlertController(
            title: "Generate Pseudocode",
            message: "Select a function to generate pseudocode for:",
            preferredStyle: .actionSheet
        )
        
        print("Alert controller created")
        
        alert.addAction(UIAlertAction(title: "Current Function", style: .default) { [weak self] _ in
            self?.generatePseudocodeForCurrentFunction()
        })
        
        alert.addAction(UIAlertAction(title: "Select from Functions", style: .default) { [weak self] _ in
            self?.showFunctionSelector()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        
        print("About to present alert")
        present(alert, animated: true) {
            print("Alert presented successfully")
        }
    }
    
    private func generatePseudocodeForCurrentFunction() {
        print("🔧 Attempting to generate pseudocode for current view")
        
        switch segmentedControl.selectedSegmentIndex {
        case 3:
            generatePseudocodeFromDisassemblyView()
        case 4:
            generatePseudocodeFromFunctionsView()
        default:
            
            let alert = UIAlertController(
                title: "No Function Selected",
                message: "Please navigate to the Code or Functions tab first, or use 'Select from Functions' to choose a specific function.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
    
    private func generatePseudocodeFromDisassemblyView() {
        let instructions = disassemblyViewController.getAllInstructions()
        
        if instructions.isEmpty {
            showNothingToGenerateAlert()
            return
        }
        
        var disassembly = ""
        var startAddress: UInt64 = 0
        
        for (index, instruction) in instructions.enumerated() {
            if index == 0 {
                startAddress = instruction.address
            }
            disassembly += String(format: "0x%llx: %@ %@\n", 
                                instruction.address,
                                instruction.mnemonic,
                                instruction.operands)
        }
        
        let pseudocodeVC = PseudocodeViewController(
            disassembly: disassembly,
            startAddress: startAddress,
            functionName: "FUN_\(String(format: "%08llx", startAddress))"
        )
        
        navigationController?.pushViewController(pseudocodeVC, animated: true)
    }
    
    private func generatePseudocodeFromFunctionsView() {
        let functions = output.functions
        
        if functions.isEmpty {
            showNothingToGenerateAlert()
            return
        }
        
        if functions.count == 1 {
            let function = functions[0]
            let disassembly = generateDisassemblyText(for: function)
            let pseudocodeVC = PseudocodeViewController(
                disassembly: disassembly,
                startAddress: function.startAddress,
                functionName: function.name
            )
            navigationController?.pushViewController(pseudocodeVC, animated: true)
            return
        }
        
        let alert = UIAlertController(
            title: "Quick Function Selection",
            message: "Select a function to generate pseudocode:",
            preferredStyle: .actionSheet
        )
        
        // Show first 10 functions
        for function in functions.prefix(10) {
            alert.addAction(UIAlertAction(title: function.name, style: .default) { [weak self] _ in
                guard let self = self else { return }
                let disassembly = self.generateDisassemblyText(for: function)
                let pseudocodeVC = PseudocodeViewController(
                    disassembly: disassembly,
                    startAddress: function.startAddress,
                    functionName: function.name
                )
                self.navigationController?.pushViewController(pseudocodeVC, animated: true)
            })
        }
        
        if functions.count > 10 {
            alert.addAction(UIAlertAction(title: "More Functions...", style: .default) { [weak self] _ in
                self?.showFunctionSelector()
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        
        present(alert, animated: true)
    }
    
    private func generateDisassemblyText(for function: FunctionModel) -> String {
        // Generate placeholder disassembly
        // In a real implementation, this would fetch actual instructions
        var text = ""
        let startAddr = function.startAddress
        
        for i in 0..<Int(function.instructionCount) {
            let addr = startAddr + UInt64(i * 4)
            text += String(format: "0x%llx: <instruction>\n", addr)
        }
        
        return text.isEmpty ? "No disassembly available" : text
    }
    
    private func showNothingToGenerateAlert() {
        let alert = UIAlertController(
            title: "Nothing to Generate",
            message: "No functions or instructions available. Please load a binary file first.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func showFunctionSelector() {
        segmentedControl.selectedSegmentIndex = 4
        segmentChanged()
        
        functionsViewController.enablePseudocodeMode()
        functionsViewController.pseudocodeDelegate = self
        
        if functionsViewController.isViewLoaded {
            functionsViewController.viewDidLoad()
            functionsViewController.tableView.reloadData()
        }
        
        let alert = UIAlertController(
            title: "Select Function",
            message: "Tap on any function in the list to generate its pseudocode.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func showBinaryPatchingDashboard() {
        let dashboardVC = BinaryPatchDashboardViewController(binaryPath: ResultsViewController.currentBinaryPath)
        let navController = UINavigationController(rootViewController: dashboardVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
    
    private func showTypeReconstruction() {
        // Create proper Type Reconstruction with real data
        let output = self.output
        
        // Convert symbols to TypeSymbolInfo format
        let symbolInfos = output.symbols.map { symbolModel in
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
        
        // Convert strings
        let strings = output.strings.map { $0.content ?? "" }
        
        // Convert functions
        let functions = output.functions.map { functionModel in
            FunctionInfo(
                name: functionModel.name,
                address: functionModel.startAddress,
                size: UInt64(functionModel.endAddress - functionModel.startAddress),
                isExported: false
            )
        }
        
        let analyzer = TypeAnalyzer(
            binaryPath: output.filePath,
            architecture: output.header.cpuType,
            symbolTable: symbolInfos,
            strings: strings,
            functions: output.functions,
            crossReferences: []
        )
        
        let inference = TypeInferenceEngine()
        
        // Perform analysis
        let results = analyzer.analyzeTypes()
        
        let typeVC = TypeReconstructionViewController(
            results: results,
            typeAnalyzer: analyzer,
            inferenceEngine: inference
        )
        
        let navController = UINavigationController(rootViewController: typeVC)
        navController.modalPresentationStyle = UIModalPresentationStyle.fullScreen
        present(navController, animated: true)
    }
}

// MARK: - Function Selection Delegate

extension ResultsViewController: FunctionSelectionDelegate {
    func didSelectFunctionForPseudocode(_ function: FunctionModel, disassembly: String) {
        print("🎯 Generating pseudocode for: \(function.name)")
        print("📝 Start address: 0x\(String(format: "%llx", function.startAddress))")
        print("📊 Instruction count: \(function.instructionCount)")
        
        let pseudocodeVC = PseudocodeViewController(
            disassembly: disassembly,
            startAddress: function.startAddress,
            functionName: function.name
        )
        
        navigationController?.pushViewController(pseudocodeVC, animated: true)
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "SymbolCell") 
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "SymbolCell")
        let symbol = filteredSymbols[indexPath.row]
        
        if symbol.address == 0 {
            cell.textLabel?.text = "⚠️ \(symbol.name)"
            cell.textLabel?.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            cell.detailTextLabel?.text = "\(symbol.type) | \(symbol.scope) | External/Undefined"
            cell.textLabel?.textColor = .secondaryLabel
        } else {
            cell.textLabel?.text = "\(Constants.formatAddress(symbol.address)) \(symbol.name)"
            cell.textLabel?.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            cell.detailTextLabel?.text = "\(symbol.type) | \(symbol.scope)"
            cell.textLabel?.textColor = .label
        }
        
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
    
    func getAllInstructions() -> [InstructionModel] {
        return instructions
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

protocol FunctionSelectionDelegate: AnyObject {
    func didSelectFunctionForPseudocode(_ function: FunctionModel, disassembly: String)
}

class FunctionsViewController: UITableViewController {
    private var functions: [FunctionModel]
    private var filteredFunctions: [FunctionModel]
    private var allInstructions: [InstructionModel] = []
    weak var pseudocodeDelegate: FunctionSelectionDelegate?
    private var pseudocodeMode: Bool = false
    
    init(functions: [FunctionModel]) {
        self.functions = functions.sortedByAddress()
        self.filteredFunctions = self.functions
        super.init(style: .plain)
    }
    
    func setInstructions(_ instructions: [InstructionModel]) {
        self.allInstructions = instructions
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FunctionCell")
        
        if pseudocodeMode {
            let banner = UILabel()
            banner.text = "  Select a function to generate pseudocode"
            banner.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
            banner.textColor = .systemBlue
            banner.font = .systemFont(ofSize: 14, weight: .medium)
            banner.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 44)
            tableView.tableHeaderView = banner
        }
    }
    
    func enablePseudocodeMode() {
        pseudocodeMode = true
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
        
        let displayName = FunctionDatabase.shared.getName(
            binaryPath: ResultsViewController.currentBinaryPath ?? "",
            address: function.startAddress
        ) ?? function.name
        
        cell.textLabel?.text = displayName
        cell.textLabel?.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        cell.detailTextLabel?.text = "\(Constants.formatAddress(function.startAddress)) - \(function.instructionCount) instructions"
        cell.accessoryType = .disclosureIndicator
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let function = filteredFunctions[indexPath.row]
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            var actions: [UIMenuElement] = []
            
            let renameAction = UIAction(
                title: "Rename Function",
                image: UIImage(systemName: "pencil")
            ) { [weak self] _ in
                guard let self = self,
                      let binaryPath = ResultsViewController.currentBinaryPath else { return }
                
                self.showRenameDialog(
                    for: function.startAddress,
                    binaryPath: binaryPath,
                    currentName: function.name
                ) { newName in
                    if newName != nil {
                        self.tableView.reloadRows(at: [indexPath], with: .automatic)
                    }
                }
            }
            actions.append(renameAction)
            
            let commentAction = UIAction(
                title: "Add Comment",
                image: UIImage(systemName: "text.bubble")
            ) { [weak self] _ in
                guard let self = self,
                      let binaryPath = ResultsViewController.currentBinaryPath else { return }
                
                self.showCommentDialog(for: function.startAddress, binaryPath: binaryPath) { _ in
                    //comment add
                }
            }
            actions.append(commentAction)
            
            let copyAction = UIAction(
                title: "Copy Address",
                image: UIImage(systemName: "doc.on.doc")
            ) { _ in
                UIPasteboard.general.string = "0x\(String(format: "%llX", function.startAddress))"
            }
            actions.append(copyAction)
            
            return UIMenu(title: function.name, children: actions)
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let function = filteredFunctions[indexPath.row]
        
        if pseudocodeMode, let delegate = pseudocodeDelegate {
            // Generate simple disassembly text (placeholder for now)
            let disassembly = generateDisassemblyText(for: function)
            delegate.didSelectFunctionForPseudocode(function, disassembly: disassembly)
            pseudocodeMode = false
            tableView.tableHeaderView = nil
            return
        }
        
        let detailVC = FunctionDetailViewController(function: function)
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    private func generateDisassemblyText(for function: FunctionModel) -> String {
        let endAddr = function.startAddress + UInt64(function.instructionCount * 4)
        
        let functionInstructions = allInstructions.filter { instruction in
            instruction.address >= function.startAddress && instruction.address < endAddr
        }
        
        if functionInstructions.isEmpty {
            print("No instructions found for function \(function.name)")
            return generatePlaceholderDisassembly(for: function)
        }
        
        var text = ""
        for instruction in functionInstructions {
            // Format: 0x100001000: 12345678 mov x0, x1
            text += String(format: "0x%llx: %@ %@ %@\n",
                          instruction.address,
                          instruction.hexBytes,
                          instruction.mnemonic,
                          instruction.operands)
        }
        
        print("Generated \(functionInstructions.count) instructions for \(function.name)")
        return text
    }
    
    private func generatePlaceholderDisassembly(for function: FunctionModel) -> String {
        var text = ""
        let startAddr = function.startAddress
        
        for i in 0..<Int(function.instructionCount) {
            let addr = startAddr + UInt64(i * 4)
            text += String(format: "0x%llx: mov x0, x1\n", addr)
        }
        
        return text
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
        
        let displayName = FunctionDatabase.shared.getName(
            binaryPath: ResultsViewController.currentBinaryPath ?? "",
            address: function.startAddress
        ) ?? function.name
        
        title = displayName
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
        
        let displayName = FunctionDatabase.shared.getName(
            binaryPath: ResultsViewController.currentBinaryPath ?? "",
            address: function.startAddress
        )
        
        if let customName = displayName {
            details += "Name:          \(customName)\n"
            details += "Original Name: \(function.name)\n"
        } else {
            details += "Name:          \(function.name)\n"
        }
        

        if let comment = FunctionDatabase.shared.getComment(
            binaryPath: ResultsViewController.currentBinaryPath ?? "",
            address: function.startAddress
        ) {
            details += "Comment:       \(comment)\n"
        }
        
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

// MARK: - Class Dump Support

extension ResultsViewController {
    private func showClassDump() {
        let output = self.output
        
        // Present ClassDumpViewController
        let classDumpVC = ClassDumpViewController(binaryPath: output.filePath)
        let navController = UINavigationController(rootViewController: classDumpVC)
        navController.modalPresentationStyle = UIModalPresentationStyle.fullScreen
        
        // Add close button
        classDumpVC.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(dismissClassDump)
        )
        
        present(navController, animated: true)
    }
    
    @objc private func dismissClassDump() {
        dismiss(animated: true)
    }
}

