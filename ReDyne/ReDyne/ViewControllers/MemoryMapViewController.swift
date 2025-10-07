import UIKit

class MemoryMapViewController: UIViewController {
    
    // MARK: - Properties
    
    private let segments: [SegmentModel]
    private let sections: [SectionModel]
    private let fileSize: UInt64
    private let baseAddress: UInt64
    
    // MARK: - UI Elements
    
    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = true
        scroll.alwaysBounceVertical = true
        return scroll
    }()
    
    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .fill
        stack.distribution = .fill
        return stack
    }()
    
    private let headerLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 24, weight: .bold)
        label.text = "Memory Map"
        return label
    }()
    
    private let statsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()
    
    private lazy var memoryMapView: MemoryMapView = {
        let view = MemoryMapView(segments: segments, sections: sections, fileSize: fileSize, baseAddress: baseAddress)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.delegate = self
        return view
    }()
    
    private let legendStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .fill
        return stack
    }()
    
    // MARK: - Initialization
    
    init(segments: [SegmentModel], sections: [SectionModel], fileSize: UInt64, baseAddress: UInt64) {
        self.segments = segments
        self.sections = sections
        self.fileSize = fileSize
        self.baseAddress = baseAddress
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Memory Map"
        view.backgroundColor = Constants.Colors.primaryBackground
        
        setupUI()
        populateStats()
        setupLegend()
        
        // Export button
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(exportMap)
        )
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        
        contentStack.addArrangedSubview(headerLabel)
        contentStack.addArrangedSubview(statsLabel)
        contentStack.addArrangedSubview(memoryMapView)
        contentStack.addArrangedSubview(createSeparator())
        contentStack.addArrangedSubview(createLegendHeader())
        contentStack.addArrangedSubview(legendStack)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            
            memoryMapView.heightAnchor.constraint(equalToConstant: 400)
        ])
    }
    
    private func populateStats() {
        let totalSize = segments.reduce(0) { $0 + $1.vmSize }
        let executableSections = sections.count // TODO: filter by protection flags if available
        let writableSections = sections.count // TODO: filter by protection flags if available
        
        statsLabel.text = """
        Total VM Size: \(formatBytes(totalSize))
        File Size: \(formatBytes(fileSize))
        Base Address: 0x\(String(format: "%llX", baseAddress))
        Segments: \(segments.count)
        Executable Sections: \(executableSections)
        Writable Sections: \(writableSections)
        """
    }
    
    private func setupLegend() {
        let categories: [(String, UIColor, String)] = [
            ("__TEXT", MemoryMapView.Colors.text, "Code & Read-only data"),
            ("__DATA", MemoryMapView.Colors.data, "Writable data"),
            ("__LINKEDIT", MemoryMapView.Colors.linkedit, "Linking information"),
            ("__OBJC", MemoryMapView.Colors.objc, "Objective-C runtime"),
            ("Other", MemoryMapView.Colors.other, "Other segments")
        ]
        
        for (name, color, description) in categories {
            let legendItem = createLegendItem(name: name, color: color, description: description)
            legendStack.addArrangedSubview(legendItem)
        }
    }
    
    private func createLegendHeader() -> UILabel {
        let label = UILabel()
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.text = "Legend"
        return label
    }
    
    private func createLegendItem(name: String, color: UIColor, description: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let colorBox = UIView()
        colorBox.translatesAutoresizingMaskIntoConstraints = false
        colorBox.backgroundColor = color
        colorBox.layer.cornerRadius = 4
        colorBox.layer.borderWidth = 1
        colorBox.layer.borderColor = UIColor.separator.cgColor
        
        let nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        nameLabel.text = name
        
        let descLabel = UILabel()
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        descLabel.font = .systemFont(ofSize: 13)
        descLabel.textColor = .secondaryLabel
        descLabel.text = description
        
        container.addSubview(colorBox)
        container.addSubview(nameLabel)
        container.addSubview(descLabel)
        
        NSLayoutConstraint.activate([
            colorBox.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            colorBox.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            colorBox.widthAnchor.constraint(equalToConstant: 24),
            colorBox.heightAnchor.constraint(equalToConstant: 24),
            
            nameLabel.leadingAnchor.constraint(equalTo: colorBox.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: container.topAnchor),
            nameLabel.widthAnchor.constraint(equalToConstant: 120),
            
            descLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),
            descLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            descLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            
            container.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        return container
    }
    
    private func createSeparator() -> UIView {
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    // MARK: - Actions
    
    @objc private func exportMap() {
        // Render the memory map to an image
        let renderer = UIGraphicsImageRenderer(bounds: memoryMapView.bounds)
        let image = renderer.image { ctx in
            memoryMapView.layer.render(in: ctx.cgContext)
        }
        
        let activityVC = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )
        
        if let popover = activityVC.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        
        present(activityVC, animated: true)
    }
}

// MARK: - MemoryMapViewDelegate

extension MemoryMapViewController: MemoryMapViewDelegate {
    func memoryMapView(_ view: MemoryMapView, didSelectSegment segment: SegmentModel) {
        let alert = UIAlertController(
            title: segment.name,
            message: segmentDetailText(segment),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func segmentDetailText(_ segment: SegmentModel) -> String {
        let segmentSections = sections.filter { $0.segmentName == segment.name }
        
        var details = """
        VM Address: 0x\(String(format: "%llX", segment.vmAddress))
        VM Size: \(formatBytes(segment.vmSize))
        File Offset: 0x\(String(format: "%llX", segment.fileOffset))
        File Size: \(formatBytes(segment.fileSize))
        Protection: \(segment.protection)
        
        Sections: \(segmentSections.count)
        """
        
        if !segmentSections.isEmpty {
            details += "\n\nSections:\n"
            for section in segmentSections.prefix(5) {
                details += "• \(section.sectionName) (\(formatBytes(section.size)))\n"
            }
            if segmentSections.count > 5 {
                details += "... and \(segmentSections.count - 5) more"
            }
        }
        
        return details
    }
}

