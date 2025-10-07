import UIKit

protocol PatchTemplateDelegate: AnyObject {
    func didSelectTemplate(_ template: PatchTemplate)
}

class PatchTemplateBrowserViewController: UIViewController {
    
    weak var delegate: PatchTemplateDelegate?
    
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let searchController = UISearchController(searchResultsController: nil)
    
    private var templates: [PatchTemplate] = []
    private var filteredTemplates: [PatchTemplate] = []
    private var selectedCategory: PatchTemplate.Category?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Patch Templates"
        view.backgroundColor = Constants.Colors.primaryBackground
        
        setupNavigationBar()
        setupSearchController()
        setupTableView()
        
        loadTemplates()
    }
    
    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(dismiss))
        
        let filterButton = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal.decrease.circle"), style: .plain, target: self, action: #selector(showFilterMenu))
        navigationItem.rightBarButtonItem = filterButton
    }
    
    private func setupSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search templates..."
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
    }
    
    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(TemplateCell.self, forCellReuseIdentifier: "TemplateCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 120
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func loadTemplates() {
        if let category = selectedCategory {
            templates = PatchTemplateLibrary.shared.templates(for: category)
        } else {
            templates = PatchTemplateLibrary.shared.templates
        }
        filteredTemplates = templates
        tableView.reloadData()
    }
    
    @objc private func dismiss(_ sender: Any) {
        dismiss(animated: true)
    }
    
    @objc private func showFilterMenu() {
        let alert = UIAlertController(title: "Filter by Category", message: nil, preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "All Templates", style: .default) { [weak self] _ in
            self?.selectedCategory = nil
            self?.loadTemplates()
        })
        
        for category in PatchTemplate.Category.allCases {
            let action = UIAlertAction(title: category.rawValue, style: .default) { [weak self] _ in
                self?.selectedCategory = category
                self?.loadTemplates()
            }
            action.setValue(UIImage(systemName: category.icon), forKey: "image")
            alert.addAction(action)
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension PatchTemplateBrowserViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredTemplates.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TemplateCell", for: indexPath) as! TemplateCell
        let template = filteredTemplates[indexPath.row]
        cell.configure(with: template)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension PatchTemplateBrowserViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let template = filteredTemplates[indexPath.row]
        showTemplateDetail(template)
    }
    
    private func showTemplateDetail(_ template: PatchTemplate) {
        let detailVC = PatchTemplateDetailViewController(template: template)
        detailVC.delegate = self
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

// MARK: - UISearchResultsUpdating

extension PatchTemplateBrowserViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        guard let query = searchController.searchBar.text else {
            filteredTemplates = templates
            tableView.reloadData()
            return
        }
        
        if query.isEmpty {
            filteredTemplates = templates
        } else {
            filteredTemplates = PatchTemplateLibrary.shared.search(query: query)
        }
        
        tableView.reloadData()
    }
}

// MARK: - PatchTemplateDelegate

extension PatchTemplateBrowserViewController: PatchTemplateDelegate {
    func didSelectTemplate(_ template: PatchTemplate) {
        dismiss(animated: true) { [weak self] in
            self?.delegate?.didSelectTemplate(template)
        }
    }
}

// MARK: - TemplateCell

class TemplateCell: UITableViewCell {
    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let categoryLabel = UILabel()
    private let difficultyLabel = UILabel()
    private let tagsLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = Constants.Colors.accentColor
        
        nameLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        descriptionLabel.font = .systemFont(ofSize: 14)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.numberOfLines = 2
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        categoryLabel.font = .systemFont(ofSize: 12, weight: .medium)
        categoryLabel.translatesAutoresizingMaskIntoConstraints = false
        
        difficultyLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        difficultyLabel.layer.cornerRadius = 4
        difficultyLabel.layer.masksToBounds = true
        difficultyLabel.textAlignment = .center
        difficultyLabel.translatesAutoresizingMaskIntoConstraints = false
        
        tagsLabel.font = .systemFont(ofSize: 11)
        tagsLabel.textColor = .tertiaryLabel
        tagsLabel.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(iconView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(descriptionLabel)
        contentView.addSubview(categoryLabel)
        contentView.addSubview(difficultyLabel)
        contentView.addSubview(tagsLabel)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),
            
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: difficultyLabel.leadingAnchor, constant: -8),
            
            difficultyLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            difficultyLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            difficultyLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            difficultyLabel.heightAnchor.constraint(equalToConstant: 20),
            
            descriptionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
            descriptionLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            categoryLabel.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 8),
            categoryLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            
            tagsLabel.topAnchor.constraint(equalTo: categoryLabel.bottomAnchor, constant: 4),
            tagsLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            tagsLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            tagsLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
    }
    
    func configure(with template: PatchTemplate) {
        iconView.image = UIImage(systemName: template.icon)
        nameLabel.text = template.name
        descriptionLabel.text = template.description
        categoryLabel.text = "\(template.category.rawValue)"
        
        difficultyLabel.text = template.difficulty.rawValue
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
        
        if !template.tags.isEmpty {
            tagsLabel.text = "🏷 " + template.tags.map { "#\($0)" }.joined(separator: " ")
        } else {
            tagsLabel.text = ""
        }
        
        accessoryType = .disclosureIndicator
    }
}

