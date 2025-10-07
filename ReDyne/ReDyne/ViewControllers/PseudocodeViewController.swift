import UIKit

class PseudocodeViewController: UIViewController {
    
    // MARK: - Properties
    private var textView: UITextView!
    private var toolbar: UIToolbar!
    private var statsLabel: UILabel!
    private var activityIndicator: UIActivityIndicatorView!
    
    private var disassemblyText: String = ""
    private var startAddress: UInt64 = 0
    private var functionName: String?
    private var pseudocodeOutput: PseudocodeOutput?
    
    // MARK: - Initialization
    
    convenience init(disassembly: String, startAddress: UInt64, functionName: String? = nil) {
        self.init()
        self.disassemblyText = disassembly
        self.startAddress = startAddress
        self.functionName = functionName
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        generatePseudocode()
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = functionName ?? "Pseudocode"
        
        textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = .systemBackground
        textView.textColor = .label
        textView.contentInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        
        if #available(iOS 13.0, *) {
            textView.backgroundColor = UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? .black : .white
            }
        }
        
        view.addSubview(textView)
        
        toolbar = UIToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)
        
        statsLabel = UILabel()
        statsLabel.font = UIFont.systemFont(ofSize: 11)
        statsLabel.textColor = .secondaryLabel
        statsLabel.textAlignment = .left
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statsLabel)
        
        activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
        
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            statsLabel.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 4),
            statsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            statsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            statsLabel.heightAnchor.constraint(equalToConstant: 20),
            
            textView.topAnchor.constraint(equalTo: statsLabel.bottomAnchor, constant: 4),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
        setupToolbar()
    }
    
    private func setupToolbar() {
        let copyButton = UIBarButtonItem(
            image: UIImage(systemName: "doc.on.doc"),
            style: .plain,
            target: self,
            action: #selector(copyPseudocode)
        )
        
        let exportButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(exportPseudocode)
        )
        
        let settingsButton = UIBarButtonItem(
            image: UIImage(systemName: "gear"),
            style: .plain,
            target: self,
            action: #selector(showSettings)
        )
        
        let refreshButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(regeneratePseudocode)
        )
        
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        toolbar.items = [
            copyButton,
            flexSpace,
            exportButton,
            flexSpace,
            settingsButton,
            flexSpace,
            refreshButton
        ]
    }
    
    // MARK: - Pseudocode Generation
    
    private func generatePseudocode() {
        activityIndicator.startAnimating()
        textView.isHidden = true
        statsLabel.text = "Generating pseudocode..."
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let result = PseudocodeService.shared.generatePseudocode(
                from: self.disassemblyText,
                startAddress: self.startAddress,
                functionName: self.functionName
            )
            
            DispatchQueue.main.async {
                self.activityIndicator.stopAnimating()
                self.textView.isHidden = false
                
                switch result {
                case .success(let output):
                    self.pseudocodeOutput = output
                    self.displayPseudocode(output)
                    
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }
    
    private func displayPseudocode(_ output: PseudocodeOutput) {
        let attributedText = NSMutableAttributedString(string: output.pseudocode)
        let baseFont = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        attributedText.addAttribute(.font, value: baseFont, range: NSRange(location: 0, length: attributedText.length))
        
        for highlight in output.syntaxHighlighting {
            let range = NSRange(location: highlight.start, length: highlight.length)
            if range.location + range.length <= attributedText.length {
                let color = colorForHighlightType(highlight.type)
                attributedText.addAttribute(.foregroundColor, value: color, range: range)
                
                if highlight.type == .keyword {
                    let boldFont = UIFont.monospacedSystemFont(ofSize: 13, weight: .bold)
                    attributedText.addAttribute(.font, value: boldFont, range: range)
                }
            }
        }
        
        textView.attributedText = attributedText
        
        let stats = output.statistics
        statsLabel.text = String(format: "%d instructions | %d blocks | %d vars | Complexity: %d | %d loops | %d conditionals",
                                stats.instructionCount,
                                stats.basicBlockCount,
                                stats.variableCount,
                                stats.complexity,
                                stats.loopCount,
                                stats.conditionalCount)
    }
    
    private func colorForHighlightType(_ type: PseudocodeOutput.HighlightType) -> UIColor {
        if #available(iOS 13.0, *) {
            switch type {
            case .keyword:
                return UIColor { traitCollection in
                    traitCollection.userInterfaceStyle == .dark
                        ? UIColor(red: 1.0, green: 0.42, blue: 0.68, alpha: 1.0)
                        : UIColor(red: 0.67, green: 0.12, blue: 0.56, alpha: 1.0)
                }
            case .type:
                return UIColor { traitCollection in
                    traitCollection.userInterfaceStyle == .dark
                        ? UIColor(red: 0.40, green: 0.85, blue: 0.93, alpha: 1.0)
                        : UIColor(red: 0.0, green: 0.6, blue: 0.8, alpha: 1.0)
                }
            case .variable:
                return UIColor { traitCollection in
                    traitCollection.userInterfaceStyle == .dark
                        ? UIColor(red: 0.77, green: 0.89, blue: 0.97, alpha: 1.0)
                        : UIColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1.0)
                }
            case .constant:
                return UIColor { traitCollection in
                    traitCollection.userInterfaceStyle == .dark
                        ? UIColor(red: 0.83, green: 0.69, blue: 0.53, alpha: 1.0)
                        : UIColor(red: 0.67, green: 0.4, blue: 0.0, alpha: 1.0)
                }
            case .comment:
                return UIColor.systemGray
            case .function:
                return UIColor { traitCollection in
                    traitCollection.userInterfaceStyle == .dark
                        ? UIColor(red: 0.60, green: 0.85, blue: 0.57, alpha: 1.0)
                        : UIColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1.0)
                }
            case .operator_:
                return UIColor.label
            case .register:
                return UIColor { traitCollection in
                    traitCollection.userInterfaceStyle == .dark
                        ? UIColor(red: 1.0, green: 0.72, blue: 0.47, alpha: 1.0)
                        : UIColor(red: 0.8, green: 0.4, blue: 0.0, alpha: 1.0)
                }
            case .address:
                return UIColor.systemGray
            }
        } else {
            switch type {
            case .keyword: return UIColor(red: 0.67, green: 0.12, blue: 0.56, alpha: 1.0)
            case .type: return UIColor(red: 0.0, green: 0.6, blue: 0.8, alpha: 1.0)
            case .variable: return UIColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1.0)
            case .constant: return UIColor(red: 0.67, green: 0.4, blue: 0.0, alpha: 1.0)
            case .comment: return UIColor.gray
            case .function: return UIColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1.0)
            case .operator_: return UIColor.black
            case .register: return UIColor(red: 0.8, green: 0.4, blue: 0.0, alpha: 1.0)
            case .address: return UIColor.gray
            }
        }
    }
    
    private func showError(_ error: PseudocodeError) {
        let errorText = """
        Pseudocode Generation Failed
        
        \(error.localizedDescription)
        
        This could be due to:
        • Invalid or incomplete disassembly
        • Unsupported instruction types
        • Complex control flow patterns
        
        Please try with a different function or check the disassembly input.
        """
        
        textView.text = errorText
        statsLabel.text = "Generation failed"
        
        let alert = UIAlertController(
            title: "Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - Actions
    
    @objc private func copyPseudocode() {
        guard let output = pseudocodeOutput else { return }
        
        UIPasteboard.general.string = """
        // \(output.functionSignature)
        
        \(output.pseudocode)
        """
        
        let alert = UIAlertController(
            title: "Copied",
            message: "Pseudocode copied to clipboard",
            preferredStyle: .alert
        )
        present(alert, animated: true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            alert.dismiss(animated: true)
        }
    }
    
    @objc private func exportPseudocode() {
        guard let output = pseudocodeOutput else { return }
        
        let text = """
        // \(output.functionSignature)
        // Generated by ReDyne Pseudocode Generator
        // Statistics: \(output.statistics.instructionCount) instructions, \
        \(output.statistics.basicBlockCount) basic blocks, \
        Complexity: \(output.statistics.complexity)
        
        \(output.pseudocode)
        """
        
        let activityVC = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )
        
        if let popover = activityVC.popoverPresentationController {
            popover.barButtonItem = toolbar.items?.first
        }
        
        present(activityVC, animated: true)
    }
    
    @objc private func showSettings() {
        let alert = UIAlertController(
            title: "Pseudocode Settings",
            message: "Configure pseudocode generation",
            preferredStyle: .actionSheet
        )
        
        let config = PseudocodeService.shared.configuration
        
        alert.addAction(UIAlertAction(
            title: config.showTypes ? "✓ Show Types" : "Show Types",
            style: .default,
            handler: { _ in
                PseudocodeService.shared.configuration.showTypes.toggle()
                self.regeneratePseudocode()
            }
        ))
        
        alert.addAction(UIAlertAction(
            title: config.showAddresses ? "✓ Show Addresses" : "Show Addresses",
            style: .default,
            handler: { _ in
                PseudocodeService.shared.configuration.showAddresses.toggle()
                self.regeneratePseudocode()
            }
        ))
        
        alert.addAction(UIAlertAction(
            title: config.simplifyExpressions ? "✓ Simplify Expressions" : "Simplify Expressions",
            style: .default,
            handler: { _ in
                PseudocodeService.shared.configuration.simplifyExpressions.toggle()
                self.regeneratePseudocode()
            }
        ))
        
        alert.addAction(UIAlertAction(
            title: config.inferTypes ? "✓ Infer Types" : "Infer Types",
            style: .default,
            handler: { _ in
                PseudocodeService.shared.configuration.inferTypes.toggle()
                self.regeneratePseudocode()
            }
        ))
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = toolbar.items?[4]
        }
        
        present(alert, animated: true)
    }
    
    @objc private func regeneratePseudocode() {
        generatePseudocode()
    }
}
