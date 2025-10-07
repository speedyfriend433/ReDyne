import UIKit

class PatchTemplateDetailViewController: UIViewController {
    
    weak var delegate: PatchTemplateDelegate?
    private let template: PatchTemplate
    
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    
    init(template: PatchTemplate) {
        self.template = template
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = template.name
        view.backgroundColor = Constants.Colors.primaryBackground
        
        setupNavigationBar()
        setupScrollView()
        buildContent()
    }
    
    private func setupNavigationBar() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Use Template", style: .done, target: self, action: #selector(useTemplate))
    }
    
    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }
    
    private func buildContent() {
        var lastView: UIView?
        let spacing: CGFloat = 20
        let sideMargin: CGFloat = 20
        let headerCard = createHeaderCard()
        contentView.addSubview(headerCard)
        NSLayoutConstraint.activate([
            headerCard.topAnchor.constraint(equalTo: contentView.topAnchor, constant: spacing),
            headerCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: sideMargin),
            headerCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -sideMargin)
        ])
        lastView = headerCard
        
        let descTitle = createSectionTitle("Description")
        contentView.addSubview(descTitle)
        NSLayoutConstraint.activate([
            descTitle.topAnchor.constraint(equalTo: lastView!.bottomAnchor, constant: spacing),
            descTitle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: sideMargin),
            descTitle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -sideMargin)
        ])
        lastView = descTitle
        
        let descLabel = createBodyLabel(template.description)
        contentView.addSubview(descLabel)
        NSLayoutConstraint.activate([
            descLabel.topAnchor.constraint(equalTo: lastView!.bottomAnchor, constant: 8),
            descLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: sideMargin),
            descLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -sideMargin)
        ])
        lastView = descLabel
        
        if !template.instructions.isEmpty {
            let instrTitle = createSectionTitle("Step-by-Step Instructions")
            contentView.addSubview(instrTitle)
            NSLayoutConstraint.activate([
                instrTitle.topAnchor.constraint(equalTo: lastView!.bottomAnchor, constant: spacing),
                instrTitle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: sideMargin),
                instrTitle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -sideMargin)
            ])
            lastView = instrTitle
            
            for instruction in template.instructions {
                let stepCard = createStepCard(instruction)
                contentView.addSubview(stepCard)
                NSLayoutConstraint.activate([
                    stepCard.topAnchor.constraint(equalTo: lastView!.bottomAnchor, constant: 12),
                    stepCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: sideMargin),
                    stepCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -sideMargin)
                ])
                lastView = stepCard
            }
        }
        
        if !template.tags.isEmpty {
            let tagsTitle = createSectionTitle("Tags")
            contentView.addSubview(tagsTitle)
            NSLayoutConstraint.activate([
                tagsTitle.topAnchor.constraint(equalTo: lastView!.bottomAnchor, constant: spacing),
                tagsTitle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: sideMargin),
                tagsTitle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -sideMargin)
            ])
            lastView = tagsTitle
            
            let tagsLabel = createBodyLabel(template.tags.map { "#\($0)" }.joined(separator: "  "))
            tagsLabel.textColor = .systemBlue
            contentView.addSubview(tagsLabel)
            NSLayoutConstraint.activate([
                tagsLabel.topAnchor.constraint(equalTo: lastView!.bottomAnchor, constant: 8),
                tagsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: sideMargin),
                tagsLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -sideMargin),
                tagsLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -spacing)
            ])
        } else {
            NSLayoutConstraint.activate([
                lastView!.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -spacing)
            ])
        }
    }
    
    private func createHeaderCard() -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = Constants.Colors.secondaryBackground
        card.layer.cornerRadius = 12
        
        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: template.icon)
        iconView.tintColor = Constants.Colors.accentColor
        iconView.contentMode = .scaleAspectFit
        
        let categoryLabel = UILabel()
        categoryLabel.translatesAutoresizingMaskIntoConstraints = false
        categoryLabel.text = template.category.rawValue
        categoryLabel.font = .systemFont(ofSize: 14, weight: .medium)
        categoryLabel.textColor = .secondaryLabel
        
        let difficultyLabel = UILabel()
        difficultyLabel.translatesAutoresizingMaskIntoConstraints = false
        difficultyLabel.text = template.difficulty.rawValue
        difficultyLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        difficultyLabel.textAlignment = .center
        difficultyLabel.layer.cornerRadius = 6
        difficultyLabel.layer.masksToBounds = true
        
        switch template.difficulty {
        case .beginner:
            difficultyLabel.backgroundColor = .systemGreen.withAlphaComponent(0.2)
            difficultyLabel.textColor = .systemGreen
        case .intermediate:
            difficultyLabel.backgroundColor = .systemOrange.withAlphaComponent(0.2)
            difficultyLabel.textColor = .systemOrange
        case .advanced:
            difficultyLabel.backgroundColor = .systemRed.withAlphaComponent(0.2)
            difficultyLabel.textColor = .systemRed
        }
        
        card.addSubview(iconView)
        card.addSubview(categoryLabel)
        card.addSubview(difficultyLabel)
        
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            iconView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            iconView.widthAnchor.constraint(equalToConstant: 50),
            iconView.heightAnchor.constraint(equalToConstant: 50),
            iconView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            
            categoryLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 16),
            categoryLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            
            difficultyLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 16),
            difficultyLabel.topAnchor.constraint(equalTo: categoryLabel.bottomAnchor, constant: 6),
            difficultyLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            difficultyLabel.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        return card
    }
    
    private func createSectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = .systemFont(ofSize: 20, weight: .bold)
        return label
    }
    
    private func createBodyLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = .systemFont(ofSize: 16)
        label.textColor = .label
        label.numberOfLines = 0
        return label
    }
    
    private func createStepCard(_ instruction: TemplateInstruction) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = Constants.Colors.secondaryBackground
        card.layer.cornerRadius = 10
        
        let stepBadge = UILabel()
        stepBadge.translatesAutoresizingMaskIntoConstraints = false
        stepBadge.text = "\(instruction.step)"
        stepBadge.font = .systemFont(ofSize: 16, weight: .bold)
        stepBadge.textColor = .white
        stepBadge.backgroundColor = Constants.Colors.accentColor
        stepBadge.textAlignment = .center
        stepBadge.layer.cornerRadius = 15
        stepBadge.layer.masksToBounds = true
        
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = instruction.title
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.numberOfLines = 0
        
        let detailLabel = UILabel()
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.text = instruction.detail
        detailLabel.font = .systemFont(ofSize: 15)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0
        
        card.addSubview(stepBadge)
        card.addSubview(titleLabel)
        card.addSubview(detailLabel)
        
        var lastView: UIView = detailLabel
        
        NSLayoutConstraint.activate([
            stepBadge.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stepBadge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            stepBadge.widthAnchor.constraint(equalToConstant: 30),
            stepBadge.heightAnchor.constraint(equalToConstant: 30),
            
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: stepBadge.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12)
        ])
        
        if let pattern = instruction.arm64Pattern {
            let patternView = createCodeBlock(title: "ARM64 Pattern", code: pattern)
            card.addSubview(patternView)
            NSLayoutConstraint.activate([
                patternView.topAnchor.constraint(equalTo: lastView.bottomAnchor, constant: 10),
                patternView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                patternView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12)
            ])
            lastView = patternView
        }
        
        if let example = instruction.example {
            let exampleView = createCodeBlock(title: "Example", code: example)
            card.addSubview(exampleView)
            NSLayoutConstraint.activate([
                exampleView.topAnchor.constraint(equalTo: lastView.bottomAnchor, constant: 10),
                exampleView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                exampleView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12)
            ])
            lastView = exampleView
        }
        
        NSLayoutConstraint.activate([
            lastView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])
        
        return card
    }
    
    private func createCodeBlock(title: String, code: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = Constants.Colors.tertiaryBackground
        container.layer.cornerRadius = 6
        
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabel
        
        let codeLabel = UILabel()
        codeLabel.translatesAutoresizingMaskIntoConstraints = false
        codeLabel.text = code
        codeLabel.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        codeLabel.textColor = .systemGreen
        codeLabel.numberOfLines = 0
        
        container.addSubview(titleLabel)
        container.addSubview(codeLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            
            codeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            codeLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            codeLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            codeLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        
        return container
    }
    
    @objc private func useTemplate() {
        delegate?.didSelectTemplate(template)
    }
}

