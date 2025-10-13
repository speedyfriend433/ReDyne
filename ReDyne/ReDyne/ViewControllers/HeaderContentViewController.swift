//
//  HeaderContentViewController.swift
//  ReDyne
//
//  Created by Assistant on 2024.
//

import UIKit
import Foundation

// MARK: - Data Models

// HeaderFile and HeaderCategory are defined in HeaderSelectionViewController.swift

class HeaderContentViewController: UIViewController {
    
    // MARK: - Properties
    
    private let headerFile: HeaderFile
    private var isShowingLineNumbers = true
    private var isWordWrapEnabled = true
    private var currentFontSize: CGFloat = 13.0
    
    // MARK: - UI Components
    
    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.alwaysBounceVertical = true
        scrollView.alwaysBounceHorizontal = true
        return scrollView
    }()
    
    private lazy var contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var textView: UITextView = {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: currentFontSize, weight: .regular)
        textView.textColor = .label
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 8
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        return textView
    }()
    
    private lazy var headerInfoView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemGroupedBackground
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var headerNameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.textColor = .label
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var headerDetailsLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var categoryBadge: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 6
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var categoryLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var closeButton: UIBarButtonItem = {
        return UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeButtonTapped)
        )
    }()
    
    private lazy var shareButton: UIBarButtonItem = {
        return UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(shareButtonTapped)
        )
    }()
    
    private lazy var optionsButton: UIBarButtonItem = {
        return UIBarButtonItem(
            title: "Options",
            style: .plain,
            target: self,
            action: #selector(optionsButtonTapped)
        )
    }()
    
    private lazy var lineCountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Initialization
    
    init(headerFile: HeaderFile) {
        self.headerFile = headerFile
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        configureContent()
        setupSyntaxHighlighting()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateLineCount()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        title = headerFile.name
        view.backgroundColor = .systemBackground
        
        navigationItem.leftBarButtonItem = closeButton
        navigationItem.rightBarButtonItems = [shareButton, optionsButton]
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(headerInfoView)
        contentView.addSubview(textView)
        contentView.addSubview(lineCountLabel)
        
        headerInfoView.addSubview(headerNameLabel)
        headerInfoView.addSubview(headerDetailsLabel)
        headerInfoView.addSubview(categoryBadge)
        categoryBadge.addSubview(categoryLabel)
        
        setupConstraints()
        setupGestures()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Content view
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Header info view
            headerInfoView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            headerInfoView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            headerInfoView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Header name label
            headerNameLabel.topAnchor.constraint(equalTo: headerInfoView.topAnchor, constant: 16),
            headerNameLabel.leadingAnchor.constraint(equalTo: headerInfoView.leadingAnchor, constant: 16),
            headerNameLabel.trailingAnchor.constraint(equalTo: categoryBadge.leadingAnchor, constant: -12),
            
            // Header details label
            headerDetailsLabel.topAnchor.constraint(equalTo: headerNameLabel.bottomAnchor, constant: 8),
            headerDetailsLabel.leadingAnchor.constraint(equalTo: headerInfoView.leadingAnchor, constant: 16),
            headerDetailsLabel.trailingAnchor.constraint(equalTo: headerInfoView.trailingAnchor, constant: -16),
            headerDetailsLabel.bottomAnchor.constraint(equalTo: headerInfoView.bottomAnchor, constant: -16),
            
            // Category badge
            categoryBadge.centerYAnchor.constraint(equalTo: headerNameLabel.centerYAnchor),
            categoryBadge.trailingAnchor.constraint(equalTo: headerInfoView.trailingAnchor, constant: -16),
            categoryBadge.heightAnchor.constraint(equalToConstant: 24),
            categoryBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            
            categoryLabel.centerXAnchor.constraint(equalTo: categoryBadge.centerXAnchor),
            categoryLabel.centerYAnchor.constraint(equalTo: categoryBadge.centerYAnchor),
            categoryLabel.leadingAnchor.constraint(equalTo: categoryBadge.leadingAnchor, constant: 8),
            categoryLabel.trailingAnchor.constraint(equalTo: categoryBadge.trailingAnchor, constant: -8),
            
            // Text view
            textView.topAnchor.constraint(equalTo: headerInfoView.bottomAnchor, constant: 20),
            textView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            textView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            textView.heightAnchor.constraint(equalToConstant: 500),
            
            // Line count label
            lineCountLabel.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 8),
            lineCountLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            lineCountLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            lineCountLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
    }
    
    private func setupGestures() {
        // Pinch to zoom
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        textView.addGestureRecognizer(pinchGesture)
        
        // Double tap to toggle word wrap
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        textView.addGestureRecognizer(doubleTapGesture)
    }
    
    // MARK: - Configuration
    
    private func configureContent() {
        headerNameLabel.text = headerFile.name
        headerDetailsLabel.text = "\(headerFile.lineCount) lines • Category: \(headerFile.category.rawValue)"
        categoryLabel.text = headerFile.category.rawValue
        categoryBadge.backgroundColor = headerFile.category.color
        
        textView.text = headerFile.content
        
        // Apply initial formatting
        updateTextFormatting()
    }
    
    private func setupSyntaxHighlighting() {
        // Basic syntax highlighting for Objective-C/Swift code
        let text = headerFile.content
        let attributedText = NSMutableAttributedString(string: text)
        
        // Define syntax highlighting colors
        let keywords: [String] = ["@interface", "@implementation", "@protocol", "@end", "@class", "@property", "@selector", "@synthesize", "@dynamic", "struct", "enum", "typedef", "NS_ENUM", "NS_OPTIONS"]
        let types: [String] = ["void", "int", "float", "double", "char", "BOOL", "id", "Class", "SEL", "IMP", "NSInteger", "NSUInteger", "CGFloat", "CGRect", "CGPoint", "CGSize"]
        let commentsPattern = "//.*$"
        let stringPattern = "@?\"[^\"]*\""
        
        // Apply advanced syntax highlighting
        let nsText = text as NSString

        // Highlight keywords with regex for all occurrences
        let keywordPattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"
        do {
            let regex = try NSRegularExpression(pattern: keywordPattern, options: [])
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                attributedText.addAttribute(.foregroundColor, value: UIColor.systemPurple, range: match.range)
                attributedText.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: currentFontSize, weight: .semibold), range: match.range)
            }
        } catch {
            print("Error creating keyword regex: \(error)")
        }

        // Highlight types with regex for all occurrences
        let typePattern = "\\b(" + types.joined(separator: "|") + ")\\b"
        do {
            let regex = try NSRegularExpression(pattern: typePattern, options: [])
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                attributedText.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: match.range)
            }
        } catch {
            print("Error creating type regex: \(error)")
        }
        
        // Highlight strings
        do {
            let regex = try NSRegularExpression(pattern: stringPattern, options: [.anchorsMatchLines])
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                attributedText.addAttribute(.foregroundColor, value: UIColor.systemRed, range: match.range)
            }
        } catch {
            print("Error creating string regex: \(error)")
        }
        
        // Highlight comments
        do {
            let regex = try NSRegularExpression(pattern: commentsPattern, options: [.anchorsMatchLines])
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                attributedText.addAttribute(.foregroundColor, value: UIColor.systemGreen, range: match.range)
            }
        } catch {
            print("Error creating comments regex: \(error)")
        }

        // Highlight numbers
        let numberPattern = "\\b\\d+\\.?\\d*\\b"
        do {
            let regex = try NSRegularExpression(pattern: numberPattern, options: [])
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                attributedText.addAttribute(.foregroundColor, value: UIColor.systemOrange, range: match.range)
            }
        } catch {
            print("Error creating number regex: \(error)")
        }

        // Highlight preprocessor directives
        let preprocessorPattern = "^\\s*#.*$"
        do {
            let regex = try NSRegularExpression(pattern: preprocessorPattern, options: [.anchorsMatchLines])
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                attributedText.addAttribute(.foregroundColor, value: UIColor.systemTeal, range: match.range)
            }
        } catch {
            print("Error creating preprocessor regex: \(error)")
        }
        
        textView.attributedText = attributedText
    }
    
    private func updateTextFormatting() {
        // Update font size
        if let attributedText = textView.attributedText {
            let mutableText = NSMutableAttributedString(attributedString: attributedText)
            mutableText.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: currentFontSize, weight: .regular), range: NSRange(location: 0, length: mutableText.length))
            textView.attributedText = mutableText
            setupSyntaxHighlighting() // Re-apply syntax highlighting
        }
        
        // Update word wrap
        textView.textContainer.lineBreakMode = isWordWrapEnabled ? .byWordWrapping : .byClipping
        textView.isScrollEnabled = !isWordWrapEnabled
    }
    
    private func updateLineCount() {
        let lines = headerFile.content.components(separatedBy: .newlines).count
        lineCountLabel.text = "\(lines) lines • \(headerFile.content.count) characters"
    }
    
    // MARK: - Actions
    
    @objc private func closeButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func shareButtonTapped() {
        let activityViewController = UIActivityViewController(
            activityItems: [headerFile.content],
            applicationActivities: nil
        )
        
        if let popover = activityViewController.popoverPresentationController {
            popover.barButtonItem = shareButton
        }
        
        present(activityViewController, animated: true)
    }
    
    @objc private func optionsButtonTapped() {
        let alertController = UIAlertController(title: "Display Options", message: nil, preferredStyle: .actionSheet)
        
        // Font size options
        alertController.addAction(UIAlertAction(title: "Increase Font Size", style: .default) { _ in
            self.currentFontSize = min(self.currentFontSize + 1, 20)
            self.updateTextFormatting()
        })
        
        alertController.addAction(UIAlertAction(title: "Decrease Font Size", style: .default) { _ in
            self.currentFontSize = max(self.currentFontSize - 1, 8)
            self.updateTextFormatting()
        })
        
        // Word wrap toggle
        let wordWrapTitle = isWordWrapEnabled ? "Disable Word Wrap" : "Enable Word Wrap"
        alertController.addAction(UIAlertAction(title: wordWrapTitle, style: .default) { _ in
            self.isWordWrapEnabled.toggle()
            self.updateTextFormatting()
        })
        
        // Copy content
        alertController.addAction(UIAlertAction(title: "Copy Content", style: .default) { _ in
            UIPasteboard.general.string = self.headerFile.content
            self.showCopyConfirmation()
        })
        
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alertController.popoverPresentationController {
            popover.barButtonItem = optionsButton
        }
        
        present(alertController, animated: true)
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .ended {
            let scale = gesture.scale
            let newSize = currentFontSize * scale
            currentFontSize = max(8, min(20, newSize))
            updateTextFormatting()
        }
    }
    
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        isWordWrapEnabled.toggle()
        updateTextFormatting()
        
        // Show brief feedback
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
    }
    
    private func showCopyConfirmation() {
        let alert = UIAlertController(
            title: "Copied",
            message: "Header content copied to clipboard",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

