import UIKit

/// Advanced filter view controller for type reconstruction
class TypeAdvancedFilterViewController: UIViewController {
    
    // MARK: - Properties
    
    private var selectedCategory: TypeCategory?
    private var selectedSource: TypeSource?
    private var selectedComplexity: TypeComplexity?
    private var minConfidence: Double = 0.0
    private var maxConfidence: Double = 1.0
    
    weak var delegate: TypeAdvancedFilterDelegate?
    
    // MARK: - UI Components
    
    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = true
        return scrollView
    }()
    
    private lazy var contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var categorySegmentedControl: UISegmentedControl = {
        let items = ["All", "Class", "Struct", "Enum"]
        let control = UISegmentedControl(items: items)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(categoryChanged), for: .valueChanged)
        return control
    }()
    
    private lazy var sourceSegmentedControl: UISegmentedControl = {
        let items = ["All", "Symbol", "Inference", "User"]
        let control = UISegmentedControl(items: items)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(sourceChanged), for: .valueChanged)
        return control
    }()
    
    private lazy var complexitySegmentedControl: UISegmentedControl = {
        let items = ["All", "Simple", "Moderate", "Complex"]
        let control = UISegmentedControl(items: items)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(complexityChanged), for: .valueChanged)
        return control
    }()
    
    private lazy var confidenceSlider: UISlider = {
        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = 0.0
        slider.maximumValue = 1.0
        slider.value = 0.0
        slider.addTarget(self, action: #selector(confidenceChanged), for: .valueChanged)
        return slider
    }()
    
    private lazy var confidenceLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16)
        label.textAlignment = .center
        label.text = "Min Confidence: 0%"
        return label
    }()
    
    // MARK: - Initialization
    
    init(selectedCategory: TypeCategory?, selectedSource: TypeSource?) {
        self.selectedCategory = selectedCategory
        self.selectedSource = selectedSource
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupNavigationBar()
        updateInitialValues()
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = .systemGroupedBackground
        title = "Advanced Filters"
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(categorySegmentedControl)
        contentView.addSubview(sourceSegmentedControl)
        contentView.addSubview(complexitySegmentedControl)
        contentView.addSubview(confidenceSlider)
        contentView.addSubview(confidenceLabel)
        
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
            
            categorySegmentedControl.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            categorySegmentedControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            categorySegmentedControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            sourceSegmentedControl.topAnchor.constraint(equalTo: categorySegmentedControl.bottomAnchor, constant: 20),
            sourceSegmentedControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            sourceSegmentedControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            complexitySegmentedControl.topAnchor.constraint(equalTo: sourceSegmentedControl.bottomAnchor, constant: 20),
            complexitySegmentedControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            complexitySegmentedControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            confidenceSlider.topAnchor.constraint(equalTo: complexitySegmentedControl.bottomAnchor, constant: 20),
            confidenceSlider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            confidenceSlider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            confidenceLabel.topAnchor.constraint(equalTo: confidenceSlider.bottomAnchor, constant: 8),
            confidenceLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            confidenceLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            confidenceLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
    }
    
    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )
    }
    
    private func updateInitialValues() {
        // Set initial values based on current selections
        if let category = selectedCategory,
           let index = TypeCategory.allCases.firstIndex(of: category) {
            categorySegmentedControl.selectedSegmentIndex = index + 1
        }
        
        if let source = selectedSource,
           let index = TypeSource.allCases.firstIndex(of: source) {
            sourceSegmentedControl.selectedSegmentIndex = index + 1
        }
    }
    
    // MARK: - Actions
    
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    @objc private func doneTapped() {
        delegate?.advancedFilter(self, didUpdateCategory: selectedCategory)
        delegate?.advancedFilter(self, didUpdateSource: selectedSource)
        dismiss(animated: true)
    }
    
    @objc private func categoryChanged() {
        let index = categorySegmentedControl.selectedSegmentIndex
        switch index {
        case 0: selectedCategory = nil
        case 1: selectedCategory = .class
        case 2: selectedCategory = .struct
        case 3: selectedCategory = .enum
        default: selectedCategory = nil
        }
    }
    
    @objc private func sourceChanged() {
        let index = sourceSegmentedControl.selectedSegmentIndex
        switch index {
        case 0: selectedSource = nil
        case 1: selectedSource = .symbolTable
        case 2: selectedSource = .inference
        case 3: selectedSource = .userDefined
        default: selectedSource = nil
        }
    }
    
    @objc private func complexityChanged() {
        let index = complexitySegmentedControl.selectedSegmentIndex
        switch index {
        case 0: selectedComplexity = nil
        case 1: selectedComplexity = .simple
        case 2: selectedComplexity = .moderate
        case 3: selectedComplexity = .complex
        default: selectedComplexity = nil
        }
    }
    
    @objc private func confidenceChanged() {
        minConfidence = Double(confidenceSlider.value)
        let percentage = Int(minConfidence * 100)
        confidenceLabel.text = "Min Confidence: \(percentage)%"
    }
}

// MARK: - Protocol

protocol TypeAdvancedFilterDelegate: AnyObject {
    func advancedFilter(_ filter: TypeAdvancedFilterViewController, didUpdateCategory category: TypeCategory?)
    func advancedFilter(_ filter: TypeAdvancedFilterViewController, didUpdateSource source: TypeSource?)
}
