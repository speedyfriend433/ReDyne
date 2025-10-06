import UIKit
import UniformTypeIdentifiers

@objc class FilePickerViewController: UIViewController {
    
    // MARK: - UI Elements
    
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.register(UITableViewCell.self, forCellReuseIdentifier: "FileCell")
        return table
    }()
    
    private let selectButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Select Binary File"
        config.baseBackgroundColor = Constants.Colors.accentColor
        config.baseForegroundColor = .white
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20)
        
        let button = UIButton(configuration: config, primaryAction: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let infoLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Select a dylib or Mach-O binary to decompile"
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 14)
        label.numberOfLines = 0
        return label
    }()
    
    // MARK: - Properties
    
    private var recentFiles: [String] = []
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "ReDyne"
        view.backgroundColor = Constants.Colors.primaryBackground
        
        setupUI()
        setupActions()
        loadRecentFiles()
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "gear"),
            style: .plain,
            target: self,
            action: #selector(showSettings)
        )
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadRecentFiles()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.addSubview(tableView)
        view.addSubview(selectButton)
        view.addSubview(infoLabel)
        
        tableView.delegate = self
        tableView.dataSource = self
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: selectButton.topAnchor, constant: -20),
            
            selectButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            selectButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            selectButton.bottomAnchor.constraint(equalTo: infoLabel.topAnchor, constant: -12),
            selectButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
            
            infoLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            infoLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            infoLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }
    
    private func setupActions() {
        selectButton.addTarget(self, action: #selector(selectFile), for: .touchUpInside)
    }
    
    private func loadRecentFiles() {
        recentFiles = UserDefaults.standard.getRecentFiles()
        tableView.reloadData()
    }
    
    // MARK: - Actions
    
    @objc private func selectFile() {

        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [
            .data,
            .item,
            .executable,
            .unixExecutable,
            UTType(filenameExtension: "dylib") ?? .data,
            UTType(filenameExtension: "framework") ?? .data
        ])
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        documentPicker.shouldShowFileExtensions = true
        
        present(documentPicker, animated: true)
    }
    
    @objc private func showSettings() {
        let alert = UIAlertController(title: "Settings", message: nil, preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "Clear Recent Files", style: .destructive) { [weak self] _ in
            self?.clearRecentFiles()
        })
        
        alert.addAction(UIAlertAction(title: "About ReDyne", style: .default) { [weak self] _ in
            self?.showAbout()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        
        present(alert, animated: true)
    }
    
    private func clearRecentFiles() {
        UserDefaults.standard.clearRecentFiles()
        loadRecentFiles()
    }
    
    private func showAbout() {
        let alert = UIAlertController(
            title: "ReDyne",
            message: "A sophisticated dylib decompiler for iOS.\n\nVersion 1.0\n\nDeep Mach-O parsing, ARM64/x86_64 disassembly, control flow analysis, and pseudocode generation. (later)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - File Processing
    
    private func processFile(at url: URL, addToRecent: Bool = true) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            ErrorHandler.showError(ReDyneError.invalidFile, in: self)
            return
        }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64, fileSize > Constants.File.maxFileSize {
                ErrorHandler.showError(ReDyneError.fileTooLarge(size: fileSize, limit: Constants.File.maxFileSize), in: self)
                return
            }
        } catch {
            ErrorHandler.log(error)
        }
        
        if addToRecent {
            UserDefaults.standard.addRecentFile(url.path)
            loadRecentFiles()
        }
        
        let decompileVC = DecompileViewController(fileURL: url)
        navigationController?.pushViewController(decompileVC, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension FilePickerViewController: UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return recentFiles.isEmpty ? 1 : recentFiles.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FileCell", for: indexPath)
        cell.accessoryType = .disclosureIndicator
        
        if recentFiles.isEmpty {
            cell.textLabel?.text = "No recent files"
            cell.textLabel?.textColor = .secondaryLabel
            cell.selectionStyle = .none
            cell.accessoryType = .none
        } else {
            let path = recentFiles[indexPath.row]
            cell.textLabel?.text = (path as NSString).lastPathComponent
            cell.detailTextLabel?.text = path
            cell.textLabel?.textColor = .label
            cell.selectionStyle = .default
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Recent Files"
    }
}

// MARK: - UITableViewDelegate

extension FilePickerViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard !recentFiles.isEmpty else { return }
        
        let path = recentFiles[indexPath.row]
        
        if let bookmarkData = UserDefaults.standard.getFileBookmark(for: path) {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withoutUI,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                
                guard url.startAccessingSecurityScopedResource() else {
                    showFileNotFoundAlert(at: indexPath)
                    return
                }
                
                if isStale {
                    if let newBookmarkData = try? url.bookmarkData(
                        options: .minimalBookmark,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    ) {
                        UserDefaults.standard.saveFileBookmark(newBookmarkData, for: path)
                    }
                }
                
                processFile(at: url, addToRecent: false)
                
                return
            } catch {
                ErrorHandler.log(error)
            }
        }
        
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            processFile(at: url, addToRecent: false)
        } else {
            showFileNotFoundAlert(at: indexPath)
        }
    }
    
    private func showFileNotFoundAlert(at indexPath: IndexPath) {
        let alert = UIAlertController(
            title: "File Not Found",
            message: "The selected file no longer exists.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Remove from Recent", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            let path = self.recentFiles[indexPath.row]
            self.recentFiles.remove(at: indexPath.row)
            UserDefaults.standard.set(self.recentFiles, forKey: Constants.UserDefaultsKeys.recentFiles)
            
            UserDefaults.standard.removeFileBookmark(for: path)
            
            self.tableView.reloadData()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete && !recentFiles.isEmpty {
            let path = recentFiles[indexPath.row]
            recentFiles.remove(at: indexPath.row)
            UserDefaults.standard.set(recentFiles, forKey: Constants.UserDefaultsKeys.recentFiles)
            
            UserDefaults.standard.removeFileBookmark(for: path)
            
            if recentFiles.isEmpty {
                tableView.reloadData()
            } else {
                tableView.deleteRows(at: [indexPath], with: .fade)
            }
        }
    }
}

// MARK: - UIDocumentPickerDelegate

extension FilePickerViewController: UIDocumentPickerDelegate {
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        
        guard url.startAccessingSecurityScopedResource() else {
            ErrorHandler.showError(ReDyneError.fileAccessDenied, in: self)
            return
        }
        
        do {
            let bookmarkData = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.saveFileBookmark(bookmarkData, for: url.path)
        } catch {
            ErrorHandler.log(error)
        }
        
        processFile(at: url)
        
        // The file needs to remain accessible for background processing.
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    }
}

