import UIKit

class DiffViewController: UIViewController {
    
    // MARK: - UI Elements
    
    private let leftTextView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = Constants.Colors.secondaryBackground
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        return textView
    }()
    
    private let rightTextView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = Constants.Colors.secondaryBackground
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        return textView
    }()
    
    private let dividerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .separator
        return view
    }()
    
    private lazy var segmentedControl: UISegmentedControl = {
        let items = ["Symbols", "Disassembly", "Statistics"]
        let control = UISegmentedControl(items: items)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        return control
    }()
    
    // MARK: - Properties
    
    private let leftOutput: DecompiledOutput
    private let rightOutput: DecompiledOutput
    
    // MARK: - Initialization
    
    init(leftOutput: DecompiledOutput, rightOutput: DecompiledOutput) {
        self.leftOutput = leftOutput
        self.rightOutput = rightOutput
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Compare Binaries"
        view.backgroundColor = Constants.Colors.primaryBackground
        
        setupUI()
        updateContent()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.addSubview(segmentedControl)
        view.addSubview(leftTextView)
        view.addSubview(dividerView)
        view.addSubview(rightTextView)
        
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Constants.UI.compactSpacing),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.UI.standardSpacing),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.UI.standardSpacing),
            
            leftTextView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: Constants.UI.standardSpacing),
            leftTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            leftTextView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            leftTextView.trailingAnchor.constraint(equalTo: dividerView.leadingAnchor),
            
            dividerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dividerView.topAnchor.constraint(equalTo: leftTextView.topAnchor),
            dividerView.bottomAnchor.constraint(equalTo: leftTextView.bottomAnchor),
            dividerView.widthAnchor.constraint(equalToConstant: 1),
            
            rightTextView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: Constants.UI.standardSpacing),
            rightTextView.leadingAnchor.constraint(equalTo: dividerView.trailingAnchor),
            rightTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rightTextView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - Content Updates
    
    @objc private func modeChanged() {
        updateContent()
    }
    
    private func updateContent() {
        switch segmentedControl.selectedSegmentIndex {
        case 0:
            showSymbolComparison()
        case 1:
            showDisassemblyComparison()
        case 2:
            showStatistics()
        default:
            break
        }
    }
    
    private func showSymbolComparison() {
        let leftSymbols = leftOutput.symbols.sortedByName()
        let rightSymbols = rightOutput.symbols.sortedByName()
        
        var leftText = "=== \(leftOutput.fileName) ===\n"
        leftText += "Symbols: \(leftSymbols.count)\n\n"
        
        for symbol in leftSymbols.prefix(100) {
            leftText += "\(Constants.formatAddress(symbol.address, padding: 12)) \(symbol.name)\n"
        }
        
        var rightText = "=== \(rightOutput.fileName) ===\n"
        rightText += "Symbols: \(rightSymbols.count)\n\n"
        
        for symbol in rightSymbols.prefix(100) {
            rightText += "\(Constants.formatAddress(symbol.address, padding: 12)) \(symbol.name)\n"
        }
        
        let leftSet = Set(leftSymbols.map { $0.name })
        let rightSet = Set(rightSymbols.map { $0.name })
        let leftOnly = leftSet.subtracting(rightSet).count
        let rightOnly = rightSet.subtracting(leftSet).count
        let common = leftSet.intersection(rightSet).count
        
        leftText += "\n\n=== Differences ===\n"
        leftText += "Only in left: \(leftOnly)\n"
        leftText += "Common: \(common)\n"
        
        rightText += "\n\n=== Differences ===\n"
        rightText += "Only in right: \(rightOnly)\n"
        rightText += "Common: \(common)\n"
        
        leftTextView.text = leftText
        rightTextView.text = rightText
    }
    
    private func showDisassemblyComparison() {
        var leftText = "=== \(leftOutput.fileName) ===\n"
        leftText += "Instructions: \(leftOutput.instructions.count)\n\n"
        
        for inst in leftOutput.instructions.prefix(50) {
            leftText += inst.fullDisassembly + "\n"
        }
        
        if leftOutput.instructions.count > 50 {
            leftText += "\n... and \(leftOutput.instructions.count - 50) more instructions\n"
        }
        
        var rightText = "=== \(rightOutput.fileName) ===\n"
        rightText += "Instructions: \(rightOutput.instructions.count)\n\n"
        
        for inst in rightOutput.instructions.prefix(50) {
            rightText += inst.fullDisassembly + "\n"
        }
        
        if rightOutput.instructions.count > 50 {
            rightText += "\n... and \(rightOutput.instructions.count - 50) more instructions\n"
        }
        
        leftTextView.text = leftText
        rightTextView.text = rightText
    }
    
    private func showStatistics() {
        let leftStats = generateStatistics(for: leftOutput)
        let rightStats = generateStatistics(for: rightOutput)
        
        leftTextView.text = leftStats
        rightTextView.text = rightStats
    }
    
    private func generateStatistics(for output: DecompiledOutput) -> String {
        var stats = "=== \(output.fileName) ===\n\n"
        
        stats += "File Information:\n"
        stats += "  Size: \(Constants.formatBytes(Int64(output.fileSize)))\n"
        stats += "  CPU Type: \(output.header.cpuType)\n"
        stats += "  File Type: \(output.header.fileType)\n"
        stats += "  Architecture: \(output.header.is64Bit ? "64-bit" : "32-bit")\n"
        stats += "  Encrypted: \(output.header.isEncrypted ? "Yes" : "No")\n\n"
        
        stats += "Structure:\n"
        stats += "  Segments: \(output.segments.count)\n"
        stats += "  Sections: \(output.sections.count)\n"
        stats += "  Load Commands: \(output.header.ncmds)\n\n"
        
        stats += "Symbols:\n"
        stats += "  Total: \(output.totalSymbols)\n"
        stats += "  Defined: \(output.definedSymbols)\n"
        stats += "  Undefined: \(output.undefinedSymbols)\n"
        stats += "  Functions: \(output.totalFunctions)\n\n"
        
        stats += "Code:\n"
        stats += "  Instructions: \(output.totalInstructions)\n"
        stats += "  Functions Detected: \(output.functions.count)\n\n"
        
        stats += "Processing:\n"
        stats += "  Time: \(Constants.formatDuration(output.processingTime))\n"
        stats += "  Date: \(output.processingDate)\n"
        
        return stats
    }
}

