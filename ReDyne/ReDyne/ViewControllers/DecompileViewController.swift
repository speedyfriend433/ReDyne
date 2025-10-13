import UIKit

class DecompileViewController: UIViewController {
    
    // MARK: - UI Elements
    
    private let progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .default)
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.progressTintColor = Constants.Colors.accentColor
        return progress
    }()
    
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Preparing..."
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.numberOfLines = 0
        return label
    }()
    
    private let fileInfoLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()
    
    private let cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Cancel", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        return button
    }()
    
    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    // MARK: - Properties
    
    private let fileURL: URL
    private var decompileTask: DispatchWorkItem?
    private var disassembleTask: DispatchWorkItem?
    
    // MARK: - Initialization
    
    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Decompiling"
        view.backgroundColor = Constants.Colors.primaryBackground
        
        setupUI()
        setupActions()
        updateFileInfo()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startDecompilation()
        }
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.addSubview(activityIndicator)
        view.addSubview(fileInfoLabel)
        view.addSubview(statusLabel)
        view.addSubview(progressView)
        view.addSubview(cancelButton)
        
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -100),
            
            fileInfoLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 30),
            fileInfoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.UI.standardSpacing),
            fileInfoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.UI.standardSpacing),
            
            statusLabel.topAnchor.constraint(equalTo: fileInfoLabel.bottomAnchor, constant: Constants.UI.standardSpacing),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.UI.standardSpacing),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.UI.standardSpacing),
            
            progressView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: Constants.UI.standardSpacing),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.UI.standardSpacing),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.UI.standardSpacing),
            progressView.heightAnchor.constraint(equalToConstant: 4),
            
            cancelButton.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 30),
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }
    
    private func setupActions() {
        cancelButton.addTarget(self, action: #selector(cancelDecompilation), for: .touchUpInside)
    }
    
    private func updateFileInfo() {
        let fileName = fileURL.lastPathComponent
        let fileSize = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64
        
        var info = "File: \(fileName)"
        if let size = fileSize {
            info += "\nSize: \(Constants.formatBytes(size))"
        }
        
        fileInfoLabel.text = info
    }
    
    // MARK: - Decompilation
    
    private func startDecompilation() {
        activityIndicator.startAnimating()
        progressView.progress = 0
        
        let processingQueue = DispatchQueue(label: Constants.Processing.backgroundQueueLabel, qos: .userInitiated)
        
        decompileTask = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            var output: DecompiledOutput?
            
            do {
                output = try BinaryParserService.parseBinary(
                    atPath: self.fileURL.path,
                    progressBlock: { status, progress in
                        DispatchQueue.main.async {
                            self.statusLabel.text = status
                            self.progressView.progress = progress
                        }
                    }
                )
            } catch {
                DispatchQueue.main.async {
                    self.handleError(error)
                }
                return
            }
            
            guard let output = output else {
                DispatchQueue.main.async {
                    self.handleError(ReDyneError.parseFailure(detail: "Unknown error"))
                }
                return
            }
            
            self.updateStatus("Disassembling code...", progress: 0.6)
            
            do {
                let instructions = try DisassemblerService.disassembleFile(
                    atPath: self.fileURL.path,
                    progressBlock: { status, progress in
                        DispatchQueue.main.async {
                            self.statusLabel.text = status
                            self.progressView.progress = 0.6 + (progress * 0.3)
                        }
                    }
                )
                
                output.instructions = instructions
                output.totalInstructions = UInt(instructions.count)
                
                let functions = DisassemblerService.extractFunctions(fromInstructions: instructions, symbols: output.symbols)
                output.functions = functions
                
                self.updateStatus("Analyzing cross-references...", progress: 0.85)
                let disassemblyText = instructions.map { $0.fullDisassembly }.joined(separator: "\n")
                let symbols = (output.symbols as NSArray).map { $0 as! SymbolModel }
                let symbolInfos = symbols.map { SymbolInfo(from: $0) }
                let xrefResult = XrefAnalyzer.analyze(disassembly: disassemblyText, symbols: symbolInfos)
                output.xrefAnalysis = xrefResult
                output.totalXrefs = UInt(xrefResult.totalXrefs)
                output.totalCalls = UInt(xrefResult.totalCalls)
                
            } catch {
                ErrorHandler.log(error)
            }
            
            self.updateStatus("Analyzing Objective-C runtime...", progress: 0.90)
            if let objcResult = ObjCParserBridge.parseObjCRuntime(atPath: self.fileURL.path) as? ObjCAnalysisResult {
                output.objcAnalysis = objcResult
                output.totalObjCClasses = UInt(objcResult.totalClasses)
                output.totalObjCMethods = UInt(objcResult.totalMethods)
            }
            
            self.updateStatus("Analyzing imports and exports...", progress: 0.93)
            if let importExportResult = ObjCParserBridge.parseImportsExports(atPath: self.fileURL.path) as? ImportExportAnalysis {
                output.importExportAnalysis = importExportResult
                output.totalImports = UInt(importExportResult.totalImports)
                output.totalExports = UInt(importExportResult.totalExports)
                output.totalLinkedLibraries = UInt(importExportResult.totalLibraries)
            }
            
            self.updateStatus("Analyzing code signature...", progress: 0.94)
            if let codeSignResult = ObjCParserBridge.parseCodeSignature(atPath: self.fileURL.path) as? CodeSigningAnalysis {
                output.codeSigningAnalysis = codeSignResult
            }
            
            self.updateStatus("Analyzing control flow graphs...", progress: 0.97)
            let functions = (output.functions as NSArray).map { $0 as! FunctionModel }
            let cfgResult = CFGAnalyzer.analyze(functions: functions)
            output.cfgAnalysis = cfgResult
            
            self.updateStatus("Finalizing...", progress: 0.99)
            
            DispatchQueue.main.async {
                self.showResults(output)
            }
        }
        
        if let task = decompileTask {
            processingQueue.async(execute: task)
        }
    }
    
    private func updateStatus(_ message: String, progress: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.text = message
            self?.progressView.progress = progress
        }
    }
    
    @objc private func cancelDecompilation() {
        decompileTask?.cancel()
        disassembleTask?.cancel()
        
        navigationController?.popViewController(animated: true)
    }
    
    private func handleError(_ error: Error) {
        activityIndicator.stopAnimating()
        
        ErrorHandler.log(error)
        
        let redyneError: ReDyneError
        if let nsError = error as NSError? {
            redyneError = ErrorHandler.convert(nsError)
        } else if let rdError = error as? ReDyneError {
            redyneError = rdError
        } else {
            redyneError = .parseFailure(detail: error.localizedDescription)
        }
        
        ErrorHandler.showError(redyneError, in: self) { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
    }
    
    private func showResults(_ output: DecompiledOutput) {
        activityIndicator.stopAnimating()
        progressView.progress = 1.0
        statusLabel.text = "Complete!"
        
        // Save to analysis history
        AnalysisHistoryManager.shared.addAnalysis(from: output, binaryPath: fileURL.path)
        
        // Cache the output for instant re-opening
        AnalysisCache.shared.save(output, for: fileURL.path)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            let resultsVC = ResultsViewController(output: output)
            self?.navigationController?.pushViewController(resultsVC, animated: true)
        }
    }
}

