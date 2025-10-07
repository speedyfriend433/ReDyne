import UIKit

class BinaryPatchDetailViewController: UIViewController {
    
    // MARK: - Properties
    
    private var patchSet: BinaryPatchSet
    private let binaryPath: String?
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    
    // MARK: - Initialization
    
    init(patchSet: BinaryPatchSet, binaryPath: String?) {
        self.patchSet = patchSet
        self.binaryPath = binaryPath
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = patchSet.name
        view.backgroundColor = Constants.Colors.primaryBackground
        
        setupNavigationBar()
        setupTableView()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }
    
    // MARK: - Setup
    
    private func setupNavigationBar() {
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addPatch)),
            UIBarButtonItem(image: UIImage(systemName: "play.fill"), style: .plain, target: self, action: #selector(applyPatchSet))
        ]
    }
    
    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(PatchCell.self, forCellReuseIdentifier: "PatchCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "InfoCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func reload() {
        if let updated = BinaryPatchService.shared.getPatchSet(with: patchSet.id) {
            patchSet = updated
            title = patchSet.name
        }
        tableView.reloadData()
    }
    
    // MARK: - Actions
    
    @objc private func addPatch() {
        guard let binaryPath = binaryPath else {
            let alert = UIAlertController(title: "No Binary", message: "Please specify a target binary first", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        
        let editorVC = BinaryPatchEditorViewController(patchSet: patchSet, binaryPath: binaryPath, patch: nil)
        navigationController?.pushViewController(editorVC, animated: true)
    }
    
    @objc private func applyPatchSet() {
        guard let binaryPath = binaryPath else {
            let alert = UIAlertController(title: "No Binary", message: "Please specify a target binary to apply patches", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        
        let alert = UIAlertController(
            title: "Apply Patch Set?",
            message: "This will apply \(patchSet.enabledPatchCount) enabled patches to the binary.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Apply", style: .default) { [weak self] _ in
            self?.performApply()
        })
        
        present(alert, animated: true)
    }
    
    private func performApply() {
        guard let binaryPath = binaryPath else { return }
        
        let progressHUD = showProgress(message: "Applying patches...")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let result = try BinaryPatchEngine.shared.apply(
                    patchSet: self.patchSet,
                    toBinaryAt: binaryPath,
                    options: .default
                )
                
                DispatchQueue.main.async {
                    progressHUD.dismiss(animated: true)
                    self.showApplyResult(result)
                    
                    try? BinaryPatchService.shared.updatePatchSetStatus(.applied, for: self.patchSet.id)
                    self.reload()
                }
            } catch {
                DispatchQueue.main.async {
                    progressHUD.dismiss(animated: true)
                    ErrorHandler.showError(error, in: self)
                }
            }
        }
    }
    
    private func showApplyResult(_ result: BinaryPatchEngine.ApplyResult) {
        var message = "Successfully applied \(result.appliedPatchIDs.count) patches"
        message += "\n\nOutput: \(result.outputPath)"
        
        if let backup = result.backupPath {
            message += "\nBackup: \(backup)"
        }
        
        if !result.warnings.isEmpty {
            message += "\n\n⚠️ Warnings:\n" + result.warnings.joined(separator: "\n")
        }
        
        let alert = UIAlertController(title: "Patches Applied", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func showProgress(message: String) -> UIAlertController {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()
        alert.view.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
            indicator.bottomAnchor.constraint(equalTo: alert.view.bottomAnchor, constant: -20)
        ])
        present(alert, animated: true)
        return alert
    }
}

// MARK: - UITableViewDataSource

extension BinaryPatchDetailViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2 
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return 3
        }
        return patchSet.patches.count
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 0 ? "Information" : "Patches (\(patchSet.patches.count))"
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "InfoCell", for: indexPath)
            
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Status: \(patchSet.status.rawValue.capitalized)"
            case 1:
                cell.textLabel?.text = "Architecture: \(patchSet.targetArchitecture ?? "Unknown")"
            case 2:
                cell.textLabel?.text = "Target: \(patchSet.targetPath ?? "Not Set")"
                cell.textLabel?.numberOfLines = 0
                cell.textLabel?.font = .systemFont(ofSize: 12)
            default:
                break
            }
            
            cell.selectionStyle = .none
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "PatchCell", for: indexPath) as! PatchCell
            let patch = patchSet.patches[indexPath.row]
            cell.configure(with: patch)
            return cell
        }
    }
}

// MARK: - UITableViewDelegate

extension BinaryPatchDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard indexPath.section == 1, let binaryPath = binaryPath else { return }
        
        let patch = patchSet.patches[indexPath.row]
        let editorVC = BinaryPatchEditorViewController(patchSet: patchSet, binaryPath: binaryPath, patch: patch)
        navigationController?.pushViewController(editorVC, animated: true)
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1 else { return nil }
        
        let patch = patchSet.patches[indexPath.row]
        
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self = self else { return }
            do {
                try BinaryPatchService.shared.deletePatch(withID: patch.id, in: self.patchSet.id)
                self.reload()
            } catch {
                ErrorHandler.showError(error, in: self)
            }
            completion(true)
        }
        
        let toggleAction = UIContextualAction(style: .normal, title: patch.enabled ? "Disable" : "Enable") { [weak self] _, _, completion in
            guard let self = self else { return }
            do {
                try BinaryPatchService.shared.setPatchEnabled(!patch.enabled, patchID: patch.id, in: self.patchSet.id)
                self.reload()
            } catch {
                ErrorHandler.showError(error, in: self)
            }
            completion(true)
        }
        toggleAction.backgroundColor = patch.enabled ? .systemOrange : .systemGreen
        
        return UISwipeActionsConfiguration(actions: [deleteAction, toggleAction])
    }
}

// MARK: - PatchCell

class PatchCell: UITableViewCell {
    private let nameLabel = UILabel()
    private let statusLabel = UILabel()
    private let addressLabel = UILabel()
    private let bytesLabel = UILabel()
    private let enabledIndicator = UIView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        nameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        
        addressLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        addressLabel.textColor = .secondaryLabel
        addressLabel.translatesAutoresizingMaskIntoConstraints = false
        
        bytesLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        bytesLabel.textColor = .tertiaryLabel
        bytesLabel.numberOfLines = 0
        bytesLabel.translatesAutoresizingMaskIntoConstraints = false
        
        enabledIndicator.translatesAutoresizingMaskIntoConstraints = false
        enabledIndicator.layer.cornerRadius = 4
        
        contentView.addSubview(enabledIndicator)
        contentView.addSubview(nameLabel)
        contentView.addSubview(statusLabel)
        contentView.addSubview(addressLabel)
        contentView.addSubview(bytesLabel)
        
        NSLayoutConstraint.activate([
            enabledIndicator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            enabledIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            enabledIndicator.widthAnchor.constraint(equalToConstant: 8),
            enabledIndicator.heightAnchor.constraint(equalToConstant: 8),
            
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: enabledIndicator.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -8),
            
            statusLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            addressLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            addressLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            addressLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),
            
            bytesLabel.topAnchor.constraint(equalTo: addressLabel.bottomAnchor, constant: 4),
            bytesLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            bytesLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            bytesLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }
    
    func configure(with patch: BinaryPatch) {
        nameLabel.text = patch.name
        
        enabledIndicator.backgroundColor = patch.enabled ? .systemGreen : .systemGray
        
        switch patch.status {
        case .draft:
            statusLabel.text = "Draft"
            statusLabel.textColor = .systemGray
        case .ready:
            statusLabel.text = "Ready"
            statusLabel.textColor = .systemBlue
        case .applied:
            statusLabel.text = "Applied"
            statusLabel.textColor = .systemGreen
        case .reverted:
            statusLabel.text = "Reverted"
            statusLabel.textColor = .systemOrange
        }
        
        addressLabel.text = "Address: 0x\(String(format: "%llX", patch.virtualAddress)) (offset: 0x\(String(format: "%llX", patch.fileOffset)))"
        
        let originalHex = patch.originalBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        let patchedHex = patch.patchedBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        bytesLabel.text = "\(originalHex) → \(patchedHex)"
        
        accessoryType = .disclosureIndicator
    }
}

