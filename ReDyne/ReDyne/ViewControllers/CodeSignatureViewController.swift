import UIKit

class CodeSignatureViewController: UIViewController {
    
    private let analysis: CodeSigningAnalysis
    
    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()
    
    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        return stack
    }()
    
    init(analysis: CodeSigningAnalysis) {
        self.analysis = analysis
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Code Signature"
        view.backgroundColor = Constants.Colors.primaryBackground
        
        setupUI()
        populateData()
    }
    
    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32)
        ])
    }
    
    private func populateData() {
        let info = analysis.signingInfo
        
        let statusCard = createCard(icon: info.isSigned ? "✅" : "⚠️", 
                                   title: "Signature Status",
                                   content: info.signatureType,
                                   color: info.isSigned ? .systemGreen : .systemOrange)
        stackView.addArrangedSubview(statusCard)
        
        if info.isSigned {
            var detailsText = """
            Type: \(info.signatureType)
            Size: \(info.signatureSizeString)
            """
            if info.teamID != "Not available" {
                detailsText += "\nTeam ID: \(info.teamID)"
            }
            if info.bundleID != "Not available" {
                detailsText += "\nBundle ID: \(info.bundleID)"
            }
            let detailsCard = createCard(icon: "🔐", title: "Signature Details", content: detailsText)
            stackView.addArrangedSubview(detailsCard)
            
            // Entitlements
            if let entitlements = info.entitlements, entitlements.hasData {
                let entCard = createCard(icon: "📜", title: "Entitlements", content: "Found entitlements data")
                stackView.addArrangedSubview(entCard)

                if let xml = entitlements.rawXML {
                    let xmlView = createTextView(xml)
                    stackView.addArrangedSubview(xmlView)
                }

                if entitlements.entitlementCount > 0 {
                    var entDetails = "Parsed entitlements (\(entitlements.entitlementCount)):\n"
                    for (key, value) in entitlements.parsedEntitlements.prefix(5) {
                        entDetails += "• \(key): \(value)\n"
                    }
                    if entitlements.entitlementCount > 5 {
                        entDetails += "... and \(entitlements.entitlementCount - 5) more"
                    }
                    let entDetailsCard = createCard(icon: "📋", title: "Entitlement Details", content: entDetails)
                    stackView.addArrangedSubview(entDetailsCard)
                }
            } else {
                let noEntCard = createCard(icon: "📜", title: "Entitlements",
                                         content: info.hasEntitlements ?
                                         "Entitlements detected but parsing failed" :
                                         "No entitlements found")
                stackView.addArrangedSubview(noEntCard)
            }
        } else {
            let unsignedCard = createCard(icon: "⚠️", title: "Warning", 
                                         content: "This binary is not code signed. It may not run on iOS devices.",
                                         color: .systemRed)
            stackView.addArrangedSubview(unsignedCard)
        }
    }
    
    private func createCard(icon: String, title: String, content: String, color: UIColor = Constants.Colors.accentColor) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = Constants.Colors.secondaryBackground
        card.layer.cornerRadius = 12
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.1
        card.layer.shadowOffset = CGSize(width: 0, height: 2)
        card.layer.shadowRadius = 4
        
        let iconLabel = UILabel()
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        iconLabel.text = icon
        iconLabel.font = .systemFont(ofSize: 32)
        
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = color
        
        let contentLabel = UILabel()
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        contentLabel.text = content
        contentLabel.font = .systemFont(ofSize: 14, weight: .regular)
        contentLabel.textColor = .label
        contentLabel.numberOfLines = 0
        
        card.addSubview(iconLabel)
        card.addSubview(titleLabel)
        card.addSubview(contentLabel)
        
        NSLayoutConstraint.activate([
            iconLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            iconLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            
            contentLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            contentLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            contentLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            contentLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        
        return card
    }
    
    private func createTextView(_ text: String) -> UITextView {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.text = text
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = Constants.Colors.secondaryBackground
        textView.layer.cornerRadius = 8
        textView.isEditable = false
        textView.heightAnchor.constraint(equalToConstant: 200).isActive = true
        return textView
    }
}

