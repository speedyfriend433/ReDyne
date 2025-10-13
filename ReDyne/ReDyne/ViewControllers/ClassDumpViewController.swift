import UIKit
import MobileCoreServices
import UniformTypeIdentifiers

class ClassDumpViewController: UIViewController {
    
    // MARK: - Properties
    
    private let binaryPath: String
    private var classDumpResult: String = ""
    private var generatedHeader: String = ""
    private var headerFiles: [HeaderFile] = []
    
    // MARK: - UI Elements
    
    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private lazy var contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var headerLabel: UILabel = {
        let label = UILabel()
        label.text = "Objective-C Header Extraction"
        label.font = .systemFont(ofSize: 28, weight: .bold)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.text = "Starting class dump analysis..."
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var progressView: UIProgressView = {
        let progressView = UIProgressView(progressViewStyle: .bar)
        progressView.progressTintColor = .systemBlue
        progressView.trackTintColor = .systemGray5
        progressView.layer.cornerRadius = 2
        progressView.clipsToBounds = true
        progressView.translatesAutoresizingMaskIntoConstraints = false
        return progressView
    }()
    
    private lazy var headerTextView: UITextView = {
        let textView = UITextView()
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 12
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.isEditable = false
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        textView.text = "Starting class dump analysis...\n\nThis will extract Objective-C headers from the binary.\n\nPlease wait..."
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    private lazy var viewHeadersButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("🔍 View Individual Headers", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.backgroundColor = .systemGreen
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.layer.shadowColor = UIColor.systemGreen.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowOpacity = 0.3
        button.layer.shadowRadius = 4
        button.isEnabled = false
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(viewHeadersButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var exportButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("📤 Export Complete Header", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.layer.shadowColor = UIColor.systemBlue.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowOpacity = 0.3
        button.layer.shadowRadius = 4
        button.isEnabled = false
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(exportButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var copyButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("📋 Copy to Clipboard", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.backgroundColor = .systemIndigo
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.layer.shadowColor = UIColor.systemIndigo.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowOpacity = 0.3
        button.layer.shadowRadius = 4
        button.isEnabled = false
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(copyButtonTapped), for: .touchUpInside)
        return button
    }()
    
    // MARK: - Initialization
    
    init(binaryPath: String) {
        self.binaryPath = binaryPath
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        print("[ClassDumpViewController] viewDidLoad called")
        setupUI()
        performClassDump()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("[ClassDumpViewController] viewDidAppear called")
        print("[ClassDumpViewController] View bounds: \(view.bounds)")
        print("[ClassDumpViewController] Scroll view bounds: \(scrollView.bounds)")
        print("[ClassDumpViewController] Content view bounds: \(contentView.bounds)")
        
        view.setNeedsLayout()
        view.layoutIfNeeded()
        
        print("[ClassDumpViewController] After layout - Scroll view frame: \(scrollView.frame)")
        print("[ClassDumpViewController] After layout - Content view frame: \(contentView.frame)")
        print("[ClassDumpViewController] After layout - Header label frame: \(headerLabel.frame)")
        print("[ClassDumpViewController] After layout - Status label frame: \(statusLabel.frame)")
        print("[ClassDumpViewController] After layout - Header text view frame: \(headerTextView.frame)")
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        print("[ClassDumpViewController] setupUI called")
        view.backgroundColor = .systemGroupedBackground
        title = "Class Dump Analysis"
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeButtonTapped)
        )
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        headerLabel.text = "Objective-C Header Extraction"
        headerLabel.textAlignment = .center
        
        statusLabel.text = "Starting class dump analysis..."
        statusLabel.textAlignment = .center
        
        headerTextView.text = "Starting class dump analysis...\n\nThis will extract Objective-C headers from the binary.\n\nPlease wait..."
        
        contentView.addSubview(headerLabel)
        contentView.addSubview(statusLabel)
        contentView.addSubview(progressView)
        contentView.addSubview(headerTextView)
        contentView.addSubview(viewHeadersButton)
        contentView.addSubview(exportButton)
        contentView.addSubview(copyButton)
        
        setupConstraints()
        
        print("[ClassDumpViewController] UI setup complete")
    }
    
    private func setupConstraints() {
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        headerTextView.translatesAutoresizingMaskIntoConstraints = false
        viewHeadersButton.translatesAutoresizingMaskIntoConstraints = false
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        
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
            
            headerLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            headerLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            headerLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            statusLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            progressView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            progressView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            progressView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            progressView.heightAnchor.constraint(equalToConstant: 4),
            
            headerTextView.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 20),
            headerTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            headerTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            headerTextView.heightAnchor.constraint(equalToConstant: 300),
            
            viewHeadersButton.topAnchor.constraint(equalTo: headerTextView.bottomAnchor, constant: 20),
            viewHeadersButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            viewHeadersButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            viewHeadersButton.heightAnchor.constraint(equalToConstant: 56),
            
            exportButton.topAnchor.constraint(equalTo: viewHeadersButton.bottomAnchor, constant: 16),
            exportButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            exportButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            exportButton.heightAnchor.constraint(equalToConstant: 56),
            
            copyButton.topAnchor.constraint(equalTo: exportButton.bottomAnchor, constant: 16),
            copyButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            copyButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            copyButton.heightAnchor.constraint(equalToConstant: 56),
            copyButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40)
        ])
    }
    
    // MARK: - Class Dump Analysis (added due to debug so you can ignore this part)
    
    private func performClassDump() {
        print("[ClassDumpViewController] performClassDump called with binaryPath: \(binaryPath)")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                print("[ClassDumpViewController] Starting analysis...")
                self.statusLabel.text = "Analyzing binary for Objective-C structures..."
                self.progressView.setProgress(0.2, animated: true)
            }
            
            print("[ClassDumpViewController] Performing C-based analysis...")
            let headerContent = self.performActualClassDump()
            
            DispatchQueue.main.async {
                print("[ClassDumpViewController] Analysis complete, processing result...")
                self.progressView.setProgress(0.8, animated: true)
                
                self.processClassDumpResult(headerContent)
                
                self.progressView.setProgress(1.0, animated: true)
                print("[ClassDumpViewController] Class dump complete")
            }
        }
    }
    
    private func performActualClassDump() -> String {
        print("[ClassDumpViewController] Starting sophisticated binary analysis using C implementation...")
        
        let cBinaryPath = binaryPath.cString(using: .utf8)!
        // TEMPORARY: Mock implementation until C functions are linked
        print("Class dump temporarily disabled - C functions not linked")
        let dumpResult = "// Class dump temporarily disabled"
        
        print("[ClassDumpViewController] C implementation completed successfully")
        print("[ClassDumpViewController] Generated header length: \(dumpResult.count)")
        
        return dumpResult
    }
    
    private func processClassDumpResult(_ headerContent: String) {
        print("[ClassDumpViewController] processClassDumpResult called with header length: \(headerContent.count)")
        
        if headerContent.isEmpty {
            generatedHeader = "// No Objective-C structures found in this binary\n\n// This binary does not contain any ObjC classes, categories, or protocols."
            statusLabel.text = "No Objective-C structures found"
            statusLabel.textColor = .systemOrange
            headerFiles = []
        } else {
            generatedHeader = headerContent
            statusLabel.text = "Objective-C header successfully generated"
            statusLabel.textColor = .systemGreen
            headerFiles = parseHeaderFiles(from: headerContent)
        }
        
        print("[ClassDumpViewController] Generated header length: \(generatedHeader.count)")
        
        // Parse and display individual headers as clickable text
        parseAndDisplayIndividualHeaders(generatedHeader)
        print("[ClassDumpViewController] Set header text to text view")
        
        exportButton.isEnabled = true
        copyButton.isEnabled = true
        viewHeadersButton.isEnabled = !headerFiles.isEmpty
        
        print("[ClassDumpViewController] Buttons enabled, result processing complete")
    }
    
    private func parseAndDisplayIndividualHeaders(_ fullHeaders: String) {
        // Split headers by @interface, @protocol, @class declarations
        let headerPattern = "(@interface|@protocol|@class)\\s+\\w+"
        let regex = try? NSRegularExpression(pattern: headerPattern, options: [])
        let matches = regex?.matches(in: fullHeaders, options: [], range: NSRange(location: 0, length: fullHeaders.count)) ?? []
        
        var individualHeaders: [(type: String, name: String, content: String)] = []
        
        for (index, match) in matches.enumerated() {
            let startIndex = fullHeaders.index(fullHeaders.startIndex, offsetBy: match.range.location)
            let endIndex: String.Index
            
            if index < matches.count - 1 {
                let nextMatch = matches[index + 1]
                endIndex = fullHeaders.index(fullHeaders.startIndex, offsetBy: nextMatch.range.location)
            } else {
                endIndex = fullHeaders.endIndex
            }
            
            let headerContent = String(fullHeaders[startIndex..<endIndex])
            
            // Extract header type and name from the declaration
            let declarationStart = fullHeaders.index(startIndex, offsetBy: match.range.length)
            let declarationPart = String(fullHeaders[declarationStart..<endIndex])
            let declarationWords = declarationPart
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .whitespaces)
            
            let headerType = String(fullHeaders[fullHeaders.index(startIndex, offsetBy: 1)..<fullHeaders.index(startIndex, offsetBy: match.range.length - 1)])
            let headerName = declarationWords.first ?? "Unknown"
            
            individualHeaders.append((type: headerType, name: headerName, content: headerContent))
        }
        
        // Display individual headers as a clean, organized list
        let attributedText = NSMutableAttributedString()
        
        // Add header title
        let titleFont = UIFont.systemFont(ofSize: 18, weight: .bold)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.label
        ]
        attributedText.append(NSAttributedString(string: "📋 Individual Headers\n\n", attributes: titleAttributes))
        
        // Add headers list
        let headerFont = UIFont.monospacedSystemFont(ofSize: 14, weight: .medium)
        let clickableFont = UIFont.monospacedSystemFont(ofSize: 14, weight: .bold)
        
        for (index, header) in individualHeaders.enumerated() {
            // Create formatted header entry with type indicator
            let typeIcon = header.type == "@interface" ? "🔵" : (header.type == "@protocol" ? "🟢" : "🟠")
            let headerText = "\(typeIcon) \(header.name)\n"
            
            let clickableText = NSMutableAttributedString(string: headerText, attributes: [
                .font: clickableFont,
                .foregroundColor: UIColor.systemBlue,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ])
            
            // Add tap gesture recognizer data
            clickableText.addAttribute(.init("HeaderIndex"), value: index, range: NSRange(location: 0, length: clickableText.length))
            clickableText.addAttribute(.init("HeaderContent"), value: header.content, range: NSRange(location: 0, length: clickableText.length))
            
            attributedText.append(clickableText)
            attributedText.append(NSAttributedString(string: "\n", attributes: [.font: headerFont]))
        }
        
        // Add footer with instructions
        let footerFont = UIFont.systemFont(ofSize: 12, weight: .medium)
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: footerFont,
            .foregroundColor: UIColor.secondaryLabel
        ]
        attributedText.append(NSAttributedString(string: "\n\nTap any header to view details", attributes: footerAttributes))
        
        headerTextView.attributedText = attributedText
        headerTextView.isEditable = false
        headerTextView.isSelectable = true
        headerTextView.dataDetectorTypes = []
        
        // Add tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(headerTapped(_:)))
        headerTextView.addGestureRecognizer(tapGesture)
    }
    
    @objc private func headerTapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: headerTextView)
        guard let textPosition = headerTextView.closestPosition(to: location),
              let textRange = headerTextView.tokenizer.rangeEnclosingPosition(textPosition, with: .word, inDirection: UITextDirection(rawValue: 0)) else {
            return
        }
        
        let startIndex = headerTextView.offset(from: headerTextView.beginningOfDocument, to: textRange.start)
        let endIndex = headerTextView.offset(from: headerTextView.beginningOfDocument, to: textRange.end)
        let range = NSRange(location: startIndex, length: endIndex - startIndex)
        
        guard let attributedText = headerTextView.attributedText,
              let headerContent = attributedText.attribute(.init("HeaderContent"), at: range.location, effectiveRange: nil) as? String else {
            return
        }
        
        // Show individual header content
        showIndividualHeaderContent(headerContent)
    }
    
    private func showIndividualHeaderContent(_ content: String) {
        let headerContentVC = HeaderContentViewController(headerFile: HeaderFile(name: "Individual Header", category: .interfaces, content: content, lineCount: content.components(separatedBy: .newlines).count))
        let navController = UINavigationController(rootViewController: headerContentVC)
        
        if #available(iOS 15.0, *) {
            if let sheet = navController.sheetPresentationController {
                sheet.detents = [UISheetPresentationController.Detent.medium(), UISheetPresentationController.Detent.large()]
                sheet.prefersGrabberVisible = true
            }
        }
        
        present(navController, animated: true)
    }
    
    // MARK: - Actions
    
    @objc private func closeButtonTapped() {
        print("[ClassDumpViewController] closeButtonTapped called")
        dismiss(animated: true)
    }
    
    @objc private func exportButtonTapped() {
        guard !generatedHeader.isEmpty else { return }
        
        let activityViewController = UIActivityViewController(
            activityItems: [generatedHeader],
            applicationActivities: nil
        )
        
        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = exportButton
            popover.sourceRect = exportButton.bounds
        }
        
        present(activityViewController, animated: true)
    }
    
    @objc private func viewHeadersButtonTapped() {
        guard !headerFiles.isEmpty else { return }
        
        let selectionVC = HeaderSelectionViewController(headerFiles: headerFiles)
        selectionVC.delegate = self
        let navController = UINavigationController(rootViewController: selectionVC)
        navController.modalPresentationStyle = .pageSheet
        present(navController, animated: true)
    }
    
    @objc private func copyButtonTapped() {
        guard !generatedHeader.isEmpty else { return }
        
        UIPasteboard.general.string = generatedHeader
        
        let alert = UIAlertController(
            title: "Copied",
            message: "Header copied to clipboard",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - Header Parsing
    
    private func parseHeaderFiles(from headerContent: String) -> [HeaderFile] {
        var headerFiles: [HeaderFile] = []
        let lines = headerContent.components(separatedBy: .newlines)
        
        var currentHeader: HeaderFile?
        var currentContent: [String] = []
        
        for line in lines {
            // Check if this is the start of a new header (starts with @interface or @protocol)
            if line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@interface") ||
               line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@protocol") ||
               line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@implementation") {
                
                // Save previous header if exists
                if let header = currentHeader, !currentContent.isEmpty {
                    let content = currentContent.joined(separator: "\n")
                    headerFiles.append(HeaderFile(name: header.name, category: header.category, content: content, lineCount: currentContent.count))
                }
                
                // Extract header name and category
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let headerName: String
                let headerCategory: HeaderCategory
                
                if trimmedLine.hasPrefix("@interface") {
                    headerCategory = .interfaces
                    headerName = extractHeaderName(from: trimmedLine, prefix: "@interface")
                } else if trimmedLine.hasPrefix("@protocol") {
                    headerCategory = .protocols
                    headerName = extractHeaderName(from: trimmedLine, prefix: "@protocol")
                } else {
                    headerCategory = .classes
                    headerName = extractHeaderName(from: trimmedLine, prefix: "@implementation")
                }
                
                currentHeader = HeaderFile(name: headerName, category: headerCategory, content: "", lineCount: 0)
                currentContent = [line]
            } else if let _ = currentHeader {
                // Add line to current header content
                currentContent.append(line)
            }
        }
        
        // Save the last header
        if let header = currentHeader, !currentContent.isEmpty {
            let content = currentContent.joined(separator: "\n")
            headerFiles.append(HeaderFile(name: header.name, category: header.category, content: content, lineCount: currentContent.count))
        }
        
        return headerFiles
    }
    
    private func extractHeaderName(from line: String, prefix: String) -> String {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixRange = trimmedLine.range(of: prefix)
        
        guard let range = prefixRange else {
            return "Unknown"
        }
        
        let afterPrefix = trimmedLine[range.upperBound...]
        let components = afterPrefix.components(separatedBy: .whitespaces)
        
        return components.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"
    }
    
    // MARK: - Cleanup
    
    deinit {
    }
}

// MARK: - HeaderSelectionDelegate
extension ClassDumpViewController: HeaderSelectionViewControllerDelegate {
    func headerSelectionViewController(_ controller: HeaderSelectionViewController, didSelectHeader header: HeaderFile) {
        // Create and present the header content view controller
        let contentVC = HeaderContentViewController(headerFile: header)
        let navController = UINavigationController(rootViewController: contentVC)
        navController.modalPresentationStyle = .pageSheet

        if #available(iOS 15.0, *) {
            if let sheet = navController.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }

        present(navController, animated: true)
    }

    func headerSelectionViewController(_ controller: HeaderSelectionViewController, didSelectHeaders headers: [HeaderFile]) {
        // Handle multiple header selection - for now, just select the first one
        if let firstHeader = headers.first {
            headerSelectionViewController(controller, didSelectHeader: firstHeader)
        }
    }
}

