import UIKit

class BinaryPatchDashboardViewController: UIViewController {
    
    // MARK: - Properties
    
    private var patchSets: [BinaryPatchSet] = []
    private var filteredPatchSets: [BinaryPatchSet] = []
    private let binaryPath: String?
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let searchController = UISearchController(searchResultsController: nil)
    private let emptyStateView = UIView()
    private let emptyLabel = UILabel()
    private let emptyIcon = UILabel()
    private let statsHeaderView = UIView()
    private let totalPatchSetsLabel = UILabel()
    private let activePatchesLabel = UILabel()
    private let readyToApplyLabel = UILabel()
    
    // MARK: - Initialization
    
    init(binaryPath: String? = nil) {
        self.binaryPath = binaryPath
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Binary Patching"
        view.backgroundColor = Constants.Colors.primaryBackground
        
        setupNavigationBar()
        setupSearchController()
        setupStatsHeader()
        setupTableView()
        setupEmptyState()
        
        loadPatchSets()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadPatchSets()
    }
    
    // MARK: - Setup
    
    private func setupNavigationBar() {
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(createNewPatchSet)),
            UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.down"), style: .plain, target: self, action: #selector(importPatchSet)),
            UIBarButtonItem(image: UIImage(systemName: "doc.text.magnifyingglass"), style: .plain, target: self, action: #selector(showTemplates))
        ]
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(dismissViewController))
    }
    
    private func setupSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search patch sets..."
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
    }
    
    private func setupStatsHeader() {
        statsHeaderView.translatesAutoresizingMaskIntoConstraints = false
        statsHeaderView.backgroundColor = .systemBackground
        statsHeaderView.layer.cornerRadius = 12
        statsHeaderView.layer.shadowColor = UIColor.black.cgColor
        statsHeaderView.layer.shadowOpacity = 0.1
        statsHeaderView.layer.shadowOffset = CGSize(width: 0, height: 2)
        statsHeaderView.layer.shadowRadius = 8
        
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor.systemBlue.withAlphaComponent(0.1).cgColor,
            UIColor.systemPurple.withAlphaComponent(0.05).cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer.cornerRadius = 12
        statsHeaderView.layer.insertSublayer(gradientLayer, at: 0)
        
        totalPatchSetsLabel.font = .systemFont(ofSize: 14, weight: .medium)
        totalPatchSetsLabel.textColor = .secondaryLabel
        totalPatchSetsLabel.translatesAutoresizingMaskIntoConstraints = false
        
        activePatchesLabel.font = .systemFont(ofSize: 14, weight: .medium)
        activePatchesLabel.textColor = .secondaryLabel
        activePatchesLabel.translatesAutoresizingMaskIntoConstraints = false
        
        readyToApplyLabel.font = .systemFont(ofSize: 14, weight: .medium)
        readyToApplyLabel.textColor = .secondaryLabel
        readyToApplyLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let totalStack = createStatStack(icon: "📦", label: totalPatchSetsLabel)
        let activeStack = createStatStack(icon: "✅", label: activePatchesLabel)
        let readyStack = createStatStack(icon: "🚀", label: readyToApplyLabel)
        
        let mainStack = UIStackView(arrangedSubviews: [totalStack, activeStack, readyStack])
        mainStack.axis = .horizontal
        mainStack.distribution = .fillEqually
        mainStack.spacing = 8
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        
        statsHeaderView.addSubview(mainStack)
        view.addSubview(statsHeaderView)
        
        NSLayoutConstraint.activate([
            statsHeaderView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            statsHeaderView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statsHeaderView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statsHeaderView.heightAnchor.constraint(equalToConstant: 80),
            
            mainStack.topAnchor.constraint(equalTo: statsHeaderView.topAnchor, constant: 16),
            mainStack.leadingAnchor.constraint(equalTo: statsHeaderView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: statsHeaderView.trailingAnchor, constant: -16),
            mainStack.bottomAnchor.constraint(equalTo: statsHeaderView.bottomAnchor, constant: -16)
        ])
        
        DispatchQueue.main.async {
            if let gradient = self.statsHeaderView.layer.sublayers?.first as? CAGradientLayer {
                gradient.frame = self.statsHeaderView.bounds
            }
        }
    }
    
    private func createStatStack(icon: String, label: UILabel) -> UIStackView {
        let iconLabel = UILabel()
        iconLabel.text = icon
        iconLabel.font = .systemFont(ofSize: 24)
        iconLabel.textAlignment = .center
        
        let stack = UIStackView(arrangedSubviews: [iconLabel, label])
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .center
        
        return stack
    }
    
    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(PatchSetCell.self, forCellReuseIdentifier: "PatchSetCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: statsHeaderView.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupEmptyState() {
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.isHidden = true
        
        emptyIcon.translatesAutoresizingMaskIntoConstraints = false
        emptyIcon.text = "🔧"
        emptyIcon.font = .systemFont(ofSize: 80)
        emptyIcon.textAlignment = .center
        
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "No Patch Sets\n\nTap + to create your first patch set\nor use templates to get started!"
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.font = .systemFont(ofSize: 17, weight: .medium)
        emptyLabel.textColor = .secondaryLabel
        
        emptyStateView.addSubview(emptyIcon)
        emptyStateView.addSubview(emptyLabel)
        view.addSubview(emptyStateView)
        
        NSLayoutConstraint.activate([
            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            
            emptyIcon.topAnchor.constraint(equalTo: emptyStateView.topAnchor),
            emptyIcon.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            
            emptyLabel.topAnchor.constraint(equalTo: emptyIcon.bottomAnchor, constant: 16),
            emptyLabel.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor),
            emptyLabel.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor),
            emptyLabel.bottomAnchor.constraint(equalTo: emptyStateView.bottomAnchor)
        ])
    }
    
    // MARK: - Data Loading
    
    private func loadPatchSets() {
        BinaryPatchService.shared.loadPatchSets()
        patchSets = BinaryPatchService.shared.getAllPatchSets()
        filteredPatchSets = patchSets
        
        updateStats()
        updateEmptyState()
        tableView.reloadData()
    }
    
    private func updateStats() {
        let totalSets = patchSets.count
        let totalPatches = patchSets.reduce(0) { $0 + $1.enabledPatchCount }
        let readySets = patchSets.filter { $0.status == .ready }.count
        
        totalPatchSetsLabel.text = "\(totalSets) Sets"
        activePatchesLabel.text = "\(totalPatches) Active"
        readyToApplyLabel.text = "\(readySets) Ready"
        
        statsHeaderView.isHidden = patchSets.isEmpty
    }
    
    private func updateEmptyState() {
        emptyStateView.isHidden = !patchSets.isEmpty
        tableView.isHidden = patchSets.isEmpty
    }
    
    // MARK: - Actions
    
    @objc private func createNewPatchSet() {
        let alert = UIAlertController(title: "New Patch Set", message: "Enter a name for the patch set", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Patch Set Name"
            textField.autocapitalizationType = .words
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self, weak alert] _ in
            guard let self = self,
                  let name = alert?.textFields?.first?.text,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            
            do {
                var patchSet = try BinaryPatchService.shared.createPatchSet(name: name, description: nil, author: nil)
                
                if let binaryPath = self.binaryPath {
                    patchSet.targetPath = binaryPath
                    if let uuid = try? MachOUtilities.uuidForBinary(at: binaryPath) {
                        patchSet.targetUUID = uuid
                    }
                    if let arch = try? MachOUtilities.architectureForBinary(at: binaryPath) {
                        patchSet.targetArchitecture = arch
                    }
                    try BinaryPatchService.shared.updatePatchSet(patchSet)
                }
                
                self.loadPatchSets()
                
                let detailVC = BinaryPatchDetailViewController(patchSet: patchSet, binaryPath: self.binaryPath)
                self.navigationController?.pushViewController(detailVC, animated: true)
            } catch {
                ErrorHandler.showError(error, in: self)
            }
        })
        
        present(alert, animated: true)
    }
    
    @objc private func importPatchSet() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }
    
    @objc private func dismissViewController() {
        dismiss(animated: true)
    }
    
    @objc private func showTemplates() {
        let templateBrowser = PatchTemplateBrowserViewController()
        templateBrowser.delegate = self
        let navController = UINavigationController(rootViewController: templateBrowser)
        present(navController, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension BinaryPatchDashboardViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredPatchSets.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PatchSetCell", for: indexPath) as! PatchSetCell
        let patchSet = filteredPatchSets[indexPath.row]
        cell.configure(with: patchSet)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension BinaryPatchDashboardViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let patchSet = filteredPatchSets[indexPath.row]
        let detailVC = BinaryPatchDetailViewController(patchSet: patchSet, binaryPath: binaryPath)
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let patchSet = filteredPatchSets[indexPath.row]
        
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.deletePatchSet(patchSet)
            completion(true)
        }
        
        let exportAction = UIContextualAction(style: .normal, title: "Export") { [weak self] _, _, completion in
            self?.exportPatchSet(patchSet)
            completion(true)
        }
        exportAction.backgroundColor = .systemBlue
        
        return UISwipeActionsConfiguration(actions: [deleteAction, exportAction])
    }
}

// MARK: - UISearchResultsUpdating

extension BinaryPatchDashboardViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        guard let query = searchController.searchBar.text, !query.isEmpty else {
            filteredPatchSets = patchSets
            tableView.reloadData()
            return
        }
        
        filteredPatchSets = BinaryPatchService.shared.searchPatchSets(query: query)
        tableView.reloadData()
    }
}

// MARK: - UIDocumentPickerDelegate

extension BinaryPatchDashboardViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        
        do {
            let data = try Data(contentsOf: url)
            try BinaryPatchService.shared.importPatchSet(from: data)
            loadPatchSets()
            
            let alert = UIAlertController(title: "Success", message: "Patch set imported successfully", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        } catch {
            ErrorHandler.showError(error, in: self)
        }
    }
}

// MARK: - PatchTemplateDelegate

extension BinaryPatchDashboardViewController: PatchTemplateDelegate {
    func didSelectTemplate(_ template: PatchTemplate) {
        let alert = UIAlertController(
            title: "Use Template",
            message: "Create a new patch set from '\(template.name)'?",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "Patch Set Name"
            textField.text = template.name
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self, weak alert] _ in
            guard let self = self,
                  let name = alert?.textFields?.first?.text,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            
            do {
                var patchSet = try BinaryPatchService.shared.createPatchSet(
                    name: name,
                    description: template.description,
                    author: nil
                )
                
                if let binaryPath = self.binaryPath {
                    patchSet.targetPath = binaryPath
                    if let uuid = try? MachOUtilities.uuidForBinary(at: binaryPath) {
                        patchSet.targetUUID = uuid
                    }
                    if let arch = try? MachOUtilities.architectureForBinary(at: binaryPath) {
                        patchSet.targetArchitecture = arch
                    }
                    try BinaryPatchService.shared.updatePatchSet(patchSet)
                }
                
                self.loadPatchSets()
                
                let detailVC = BinaryPatchDetailViewController(patchSet: patchSet, binaryPath: self.binaryPath)
                self.navigationController?.pushViewController(detailVC, animated: true)
                self.showTemplateInstructions(template, in: detailVC)
                
            } catch {
                ErrorHandler.showError(error, in: self)
            }
        })
        
        present(alert, animated: true)
    }
    
    private func showTemplateInstructions(_ template: PatchTemplate, in viewController: UIViewController) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let instructions = template.instructions.enumerated().map { index, instruction in
                "\(instruction.step). \(instruction.title)\n   \(instruction.detail)"
            }.joined(separator: "\n\n")
            
            let alert = UIAlertController(
                title: "Template Instructions",
                message: instructions,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Got It!", style: .default))
            viewController.present(alert, animated: true)
        }
    }
}

// MARK: - Helper Methods

extension BinaryPatchDashboardViewController {
    private func deletePatchSet(_ patchSet: BinaryPatchSet) {
        let alert = UIAlertController(
            title: "Delete Patch Set?",
            message: "This will permanently delete \"\(patchSet.name)\" and all its patches.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            do {
                try BinaryPatchService.shared.deletePatchSet(with: patchSet.id)
                self?.loadPatchSets()
            } catch {
                ErrorHandler.showError(error, in: self!)
            }
        })
        
        present(alert, animated: true)
    }
    
    private func exportPatchSet(_ patchSet: BinaryPatchSet) {
        do {
            let data = try BinaryPatchService.shared.exportPatchSet(patchSet.id)
            let fileName = "\(patchSet.name.replacingOccurrences(of: " ", with: "_"))_v\(patchSet.version).json"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: tempURL)
            
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = view.bounds
            }
            present(activityVC, animated: true)
        } catch {
            ErrorHandler.showError(error, in: self)
        }
    }
}

// MARK: - PatchSetCell

class PatchSetCell: UITableViewCell {
    private let iconLabel = UILabel()
    private let nameLabel = UILabel()
    private let statusBadge = UIView()
    private let statusLabel = UILabel()
    private let patchCountLabel = UILabel()
    private let dateLabel = UILabel()
    private let cardView = UIView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        backgroundColor = .clear
        selectionStyle = .none
        
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = .systemBackground
        cardView.layer.cornerRadius = 12
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.08
        cardView.layer.shadowOffset = CGSize(width: 0, height: 2)
        cardView.layer.shadowRadius = 6
        contentView.addSubview(cardView)
        
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        iconLabel.font = .systemFont(ofSize: 32)
        iconLabel.textAlignment = .center
        cardView.addSubview(iconLabel)
        
        nameLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(nameLabel)
        
        statusBadge.translatesAutoresizingMaskIntoConstraints = false
        statusBadge.layer.cornerRadius = 10
        cardView.addSubview(statusBadge)
        
        statusLabel.font = .systemFont(ofSize: 11, weight: .bold)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusBadge.addSubview(statusLabel)
        
        patchCountLabel.font = .systemFont(ofSize: 14, weight: .medium)
        patchCountLabel.textColor = .secondaryLabel
        patchCountLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(patchCountLabel)
        
        dateLabel.font = .systemFont(ofSize: 12)
        dateLabel.textColor = .tertiaryLabel
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(dateLabel)
        
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            
            iconLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            iconLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            iconLabel.widthAnchor.constraint(equalToConstant: 40),
            
            nameLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusBadge.leadingAnchor, constant: -8),
            
            statusBadge.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            statusBadge.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            statusBadge.heightAnchor.constraint(equalToConstant: 20),
            
            statusLabel.topAnchor.constraint(equalTo: statusBadge.topAnchor, constant: 2),
            statusLabel.leadingAnchor.constraint(equalTo: statusBadge.leadingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: statusBadge.trailingAnchor, constant: -8),
            statusLabel.bottomAnchor.constraint(equalTo: statusBadge.bottomAnchor, constant: -2),
            
            patchCountLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
            patchCountLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            patchCountLabel.trailingAnchor.constraint(lessThanOrEqualTo: cardView.trailingAnchor, constant: -16),
            
            dateLabel.topAnchor.constraint(equalTo: patchCountLabel.bottomAnchor, constant: 4),
            dateLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            dateLabel.trailingAnchor.constraint(lessThanOrEqualTo: cardView.trailingAnchor, constant: -16),
            dateLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12)
        ])
    }
    
    func configure(with patchSet: BinaryPatchSet) {
        nameLabel.text = patchSet.name
        
        switch patchSet.status {
        case .draft:
            iconLabel.text = "📝"
            statusLabel.text = "DRAFT"
            statusLabel.textColor = .white
            statusBadge.backgroundColor = .systemGray
        case .ready:
            iconLabel.text = "✅"
            statusLabel.text = "READY"
            statusLabel.textColor = .white
            statusBadge.backgroundColor = .systemBlue
        case .applied:
            iconLabel.text = "🎯"
            statusLabel.text = "APPLIED"
            statusLabel.textColor = .white
            statusBadge.backgroundColor = .systemGreen
        case .archived:
            iconLabel.text = "📦"
            statusLabel.text = "ARCHIVED"
            statusLabel.textColor = .white
            statusBadge.backgroundColor = .systemOrange
        }
        
        let enabled = patchSet.enabledPatchCount
        let total = patchSet.patchCount
        if enabled > 0 {
            patchCountLabel.text = "\(enabled)/\(total) patches enabled"
        } else {
            patchCountLabel.text = "\(total) patches (none enabled)"
        }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        dateLabel.text = "Updated " + formatter.localizedString(for: patchSet.updatedAt, relativeTo: Date())
        
        cardView.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: .curveEaseOut) {
            self.cardView.transform = .identity
        }
    }
    
    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        
        UIView.animate(withDuration: 0.2) {
            self.cardView.transform = highlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
            self.cardView.alpha = highlighted ? 0.8 : 1.0
        }
    }
}

