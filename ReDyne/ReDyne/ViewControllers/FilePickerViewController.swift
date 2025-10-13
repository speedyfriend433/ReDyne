import UIKit
import UniformTypeIdentifiers
import SwiftUI
import Combine

@objc class FilePickerViewController: UIViewController {

    // MARK: - SwiftUI File Picker
    private var sceneDelegateWrapper: SceneDelegateWrapper!
    private var swiftUIFilePickerViewController: SwiftUIFilePickerViewController!

    // MARK: - UI Elements
    
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
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
    private var analysisHistory: [AnalysisHistoryEntry] = []
    
    // MARK: - Properties for Scene Delegate
    private var storedSceneDelegate: SceneDelegate?

    @objc func setSceneDelegate(_ sceneDelegate: SceneDelegate) {
        print("setSceneDelegate called with sceneDelegate: \(sceneDelegate)")
        storedSceneDelegate = sceneDelegate
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "ReDyne"
        view.backgroundColor = Constants.Colors.primaryBackground

        if let sceneDelegate = storedSceneDelegate {
            print("Initializing SwiftUI file picker with scene delegate")
            sceneDelegateWrapper = SceneDelegateWrapper(sceneDelegate: sceneDelegate)
            swiftUIFilePickerViewController = SwiftUIFilePickerViewController(
                sceneDelegateWrapper: sceneDelegateWrapper,
                onFileSelected: { [weak self] url in
                    print("📁 SwiftUI file selected: \(url)")
                    self?.handleSwiftUIFileSelection(url)
                }
            )
            print("SwiftUI file picker initialized successfully")
        } else {
            print("No scene delegate available for SwiftUI file picker")
        }

        setupUI()
        setupActions()
        setupDragAndDrop()
        loadRecentFiles()
        configureFilePickerMode()

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
        loadAnalysisHistory()
        updateInfoLabel()
    }
    
    private func loadAnalysisHistory() {
        analysisHistory = AnalysisHistoryManager.shared.getHistory()
        tableView.reloadData()
    }
    
    private func updateInfoLabel() {
        let mode = UserDefaults.standard.useLegacyFilePicker ? "Legacy (Enhanced)" : "Modern"
        infoLabel.text = "Select a dylib or Mach-O binary to decompile\n💡 Tip: You can drag & drop files here!\n\n File Picker Mode: \(mode)"
    }

    private func configureFilePickerMode() {
        if UserDefaults.standard.useLegacyFilePicker {
            EnhancedFilePicker.enable()
        } else {
            EnhancedFilePicker.disable()
        }

        #if DEBUG
        Constants.logFilePickerMode()
        #endif
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
    
    private func setupDragAndDrop() {
        let dropInteraction = UIDropInteraction(delegate: self)
        view.addInteraction(dropInteraction)
        
        selectButton.isUserInteractionEnabled = true
    }
    
    private func loadRecentFiles() {
        var recentFiles = UserDefaults.standard.getRecentFiles()
        var validFiles: [String] = []
        var invalidFiles: [String] = []
        
        // Validate each recent file
        for filePath in recentFiles {
            if FileManager.default.fileExists(atPath: filePath) {
                validFiles.append(filePath)
            } else {
                // Try bookmark for external files
                if let bookmarkData = UserDefaults.standard.getFileBookmark(for: filePath) {
                    var isStale = false
                    do {
                        let url = try URL(
                            resolvingBookmarkData: bookmarkData,
                            options: .withoutUI,
                            relativeTo: nil,
                            bookmarkDataIsStale: &isStale
                        )
                        
                        if FileManager.default.fileExists(atPath: url.path) {
                            validFiles.append(filePath)
                        } else {
                            invalidFiles.append(filePath)
                        }
                    } catch {
                        invalidFiles.append(filePath)
                    }
                } else {
                    invalidFiles.append(filePath)
                }
            }
        }
        
        // Remove invalid files from UserDefaults
        if !invalidFiles.isEmpty {
            for invalidFile in invalidFiles {
                UserDefaults.standard.removeFileBookmark(for: invalidFile)
            }
            UserDefaults.standard.set(validFiles, forKey: Constants.UserDefaultsKeys.recentFiles)
        }
        
        self.recentFiles = validFiles
        tableView.reloadData()
    }
    
    // MARK: - Actions
    
    @objc private func selectFile() {
        if UserDefaults.standard.useLegacyFilePicker {
            print("Presenting SwiftUI file picker (Legacy mode)")
            if swiftUIFilePickerViewController != nil {
                swiftUIFilePickerViewController.presentFilePicker()
            } else {
                print("SwiftUI file picker not initialized")
                fallbackToUIKitPicker()
            }
        } else {
            print("Presenting UIKit file picker (Modern mode)")
            let contentTypes = Constants.FileTypes.binaryUTTypes()
            let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
            documentPicker.delegate = self
            documentPicker.allowsMultipleSelection = false
            documentPicker.shouldShowFileExtensions = true
            present(documentPicker, animated: true)
        }
    }

    private func fallbackToUIKitPicker() {
        print("Falling back to UIKit picker")
        let contentTypes = Constants.FileTypes.binaryUTTypes()
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        documentPicker.shouldShowFileExtensions = true
        present(documentPicker, animated: true)
    }
    
    @objc private func showSettings() {
        let alert = UIAlertController(title: "Settings", message: nil, preferredStyle: .actionSheet)
        let currentMode = UserDefaults.standard.useLegacyFilePicker
        let pickerTitle = currentMode ? "✓ Use Legacy File Picker (Two-Tap)" : "Use Legacy File Picker (Two-Tap)"
        alert.addAction(UIAlertAction(title: pickerTitle, style: .default) { [weak self] _ in
            self?.toggleFilePickerStyle()
        })
        
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
    
    private func toggleFilePickerStyle() {
        let isLegacy = UserDefaults.standard.useLegacyFilePicker
        UserDefaults.standard.useLegacyFilePicker = !isLegacy

        configureFilePickerMode()

        let newMode = !isLegacy ? "Legacy (Enhanced)" : "Modern"
        let message = "File picker changed to \(newMode) mode.\n\nLegacy mode: Enhanced file access with broader compatibility.\nModern mode: Standard iOS file picker."

        let alert = UIAlertController(
            title: "File Picker Updated",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.updateInfoLabel()
        })
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
        var workingURL = url.standardizedFileURL

        guard FileManager.default.fileExists(atPath: workingURL.path) else {
            ErrorHandler.showError(ReDyneError.invalidFile, in: self)
            return
        }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: workingURL.path)
            if let fileSize = attributes[.size] as? Int64, fileSize > Constants.File.maxFileSize {
                ErrorHandler.showError(ReDyneError.fileTooLarge(size: fileSize, limit: Constants.File.maxFileSize), in: self)
                return
            }
        } catch {
            ErrorHandler.log(error)
        }

        do {
            let persistedURL = try SavedBinaryStorage.shared.importBinary(from: workingURL)
            workingURL = persistedURL
        } catch {
            ErrorHandler.log(error)
            let nsError = error as NSError
            let reason = nsError.localizedFailureReason ?? nsError.localizedDescription
            ErrorHandler.showError(
                ReDyneError.failedToPersistBinary(reason: reason),
                in: self
            )
            return
        }
        
        if addToRecent {
            // Add to recent files
            UserDefaults.standard.addRecentFile(workingURL.path)
            
            // Save security-scoped bookmark for external files
            if workingURL.startAccessingSecurityScopedResource() {
                if let bookmarkData = try? workingURL.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    UserDefaults.standard.saveFileBookmark(bookmarkData, for: workingURL.path)
                }
                workingURL.stopAccessingSecurityScopedResource()
            }
            
            loadRecentFiles()
        }
        
        let decompileVC = DecompileViewController(fileURL: workingURL)
        navigationController?.pushViewController(decompileVC, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension FilePickerViewController: UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2  // Saved Analyses + Recent Files
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            // Saved Analyses
            return analysisHistory.isEmpty ? 1 : min(analysisHistory.count, 5)  // Show up to 5
        } else {
            // Recent Files
            return recentFiles.isEmpty ? 1 : recentFiles.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FileCell") 
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "FileCell")
        cell.accessoryType = .disclosureIndicator
        
        if indexPath.section == 0 {
            // Saved Analyses section
            if analysisHistory.isEmpty {
                cell.textLabel?.text = "No saved analyses yet"
                cell.detailTextLabel?.text = "Analyzed binaries will appear here"
                cell.textLabel?.textColor = .secondaryLabel
                cell.detailTextLabel?.textColor = .tertiaryLabel
                cell.selectionStyle = .none
                cell.accessoryType = .none
            } else {
                let entry = analysisHistory[indexPath.row]
                cell.textLabel?.text = "📦 \(entry.binaryName)"
                cell.detailTextLabel?.text = "\(entry.formattedDate) • \(entry.formattedFileSize) • \(entry.totalFunctions) functions"
                cell.textLabel?.textColor = .label
                cell.detailTextLabel?.textColor = .secondaryLabel
                cell.selectionStyle = .default
                cell.accessoryType = .disclosureIndicator
            }
        } else {
            // Recent Files section
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
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return analysisHistory.isEmpty ? nil : "💾 Saved Analyses (Tap to Re-open)"
        } else {
            return "📂 Recent Files"
        }
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 && !analysisHistory.isEmpty && analysisHistory.count > 5 {
            return "Showing 5 of \(analysisHistory.count) • Tap 'View All' in Settings"
        }
        return nil
    }
}

// MARK: - UITableViewDelegate

extension FilePickerViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if indexPath.section == 0 {
            // Saved Analyses section
            guard !analysisHistory.isEmpty else { return }
            let entry = analysisHistory[indexPath.row]
            reopenAnalysis(entry)
            return
        }
        
        // Recent Files section
        guard !recentFiles.isEmpty else { return }
        
        let path = recentFiles[indexPath.row]
        
        // First check if file exists at the original path
        if FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            processFile(at: url, addToRecent: false)
            return
        }
        
        // Try to use security-scoped bookmark as fallback
        if let bookmarkData = UserDefaults.standard.getFileBookmark(for: path) {
            var isStale = false
            do {
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
                
                // Update bookmark if it's stale
                if isStale {
                    if let newBookmarkData = try? url.bookmarkData(
                        options: .minimalBookmark,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    ) {
                        UserDefaults.standard.saveFileBookmark(newBookmarkData, for: path)
                    }
                }
                
                // Verify the file still exists at the bookmarked location
                if FileManager.default.fileExists(atPath: url.path) {
                    processFile(at: url, addToRecent: false)
                } else {
                    showFileNotFoundAlert(at: indexPath)
                }
                
                return
            } catch {
                ErrorHandler.log(error)
            }
        }
        
        // File not found - show alert
        showFileNotFoundAlert(at: indexPath)
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
        if editingStyle == .delete {
            if indexPath.section == 0 {
                // Delete from Saved Analyses
                guard !analysisHistory.isEmpty else { return }
                let entry = analysisHistory[indexPath.row]
                AnalysisHistoryManager.shared.removeEntry(with: entry.id)
                loadAnalysisHistory()
            } else {
                // Delete from Recent Files
                guard !recentFiles.isEmpty else { return }
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
    
    private func reopenAnalysis(_ entry: AnalysisHistoryEntry) {
        print("🔍 Attempting to reopen: \(entry.binaryName)")
        print("🔍 Stored path: \(entry.binaryPath)")
        print("🔍 File exists: \(FileManager.default.fileExists(atPath: entry.binaryPath))")
        
        // Check if file still exists at original path
        if FileManager.default.fileExists(atPath: entry.binaryPath) {
            reopenWithPath(entry.binaryPath, entry: entry)
            return
        }
        
        print("❌ File not found at stored path!")
        
        // Use the improved AnalysisHistoryManager to find moved files
        if let foundPath = AnalysisHistoryManager.shared.findMovedFile(for: entry) {
            print("✅ Found moved file at: \(foundPath)")
            reopenWithPath(foundPath, entry: entry)
            return
        }
        
        print("❌ File not found using AnalysisHistoryManager strategies")
        
        // Fallback to SavedBinaries search for additional coverage
        let savedBinaries = SavedBinaryStorage.shared.listSavedBinaries()
        
        // Strategy: Look in SavedBinaries by exact name match
        if let matchingBinary = savedBinaries.first(where: { $0.lastPathComponent == entry.binaryName }) {
            print("✅ Found file in SavedBinaries by name: \(matchingBinary.path)")
            reopenWithPath(matchingBinary.path, entry: entry)
            return
        }
        
        // Strategy: Look in SavedBinaries by name without extension
        let baseName = (entry.binaryName as NSString).deletingPathExtension
        if let matchingBinary = savedBinaries.first(where: { 
            ($0.lastPathComponent as NSString).deletingPathExtension == baseName 
        }) {
            print("✅ Found file in SavedBinaries by base name: \(matchingBinary.path)")
            reopenWithPath(matchingBinary.path, entry: entry)
            return
        }
        
        // Strategy: Look in SavedBinaries by file size match
        if let matchingBinary = savedBinaries.first(where: { url in
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                if let size = attributes[.size] as? UInt64 {
                    return size == entry.fileSize
                }
            } catch {
                return false
            }
            return false
        }) {
            print("✅ Found file in SavedBinaries by size: \(matchingBinary.path)")
            reopenWithPath(matchingBinary.path, entry: entry)
            return
        }
        
        // No file found - show alert
        showFileNotFoundAlert(for: entry)
    }
    
    private func reopenWithPath(_ path: String, entry: AnalysisHistoryEntry) {
        // Try to load from cache first
        if let cachedOutput = AnalysisCache.shared.load(for: path) {
            print("⚡ Using cached analysis - INSTANT!")
            let resultsVC = ResultsViewController(output: cachedOutput)
            navigationController?.pushViewController(resultsVC, animated: true)
            return
        }
        
        // No cache, re-analyze the binary
        print("📊 No cache found, re-analyzing...")
        let url = URL(fileURLWithPath: path)
        processFile(at: url, addToRecent: false)
    }
    
    private func showFileNotFoundAlert(for entry: AnalysisHistoryEntry) {
        let alert = UIAlertController(
            title: "File Not Found",
            message: "The binary '\(entry.binaryName)' no longer exists at its saved location.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Remove from History", style: .destructive) { [weak self] _ in
            AnalysisHistoryManager.shared.removeEntry(with: entry.id)
            self?.loadAnalysisHistory()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - UIDocumentPickerDelegate

extension FilePickerViewController: UIDocumentPickerDelegate {
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        
        if UserDefaults.standard.useLegacyFilePicker {
            confirmAndProcessFile(at: url)
        } else {
            showOpenConfirmation(for: url)
        }
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    }
    
    private func showOpenConfirmation(for url: URL) {
        let fileName = url.lastPathComponent
        let fileSize = getFileSize(at: url)
        
        let alert = UIAlertController(
            title: "Open File?",
            message: "File: \(fileName)\nSize: \(fileSize)\n\nThis will start analyzing the binary. Continue?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Open", style: .default) { [weak self] _ in
            self?.confirmAndProcessFile(at: url)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func confirmAndProcessFile(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            ErrorHandler.showError(ReDyneError.invalidFile, in: self)
            return
        }

        // Handle different behavior for asCopy modes
        if UserDefaults.standard.useLegacyFilePicker {
            let isInAppContainer = url.path.contains("/Containers/Data/Application/") && 
                                  (url.path.contains("-Inbox/") || url.path.contains("/Documents/"))
            
            print("🔍 File path: \(url.path)")
            print("🔍 Is in app container: \(isInAppContainer)")

            if isInAppContainer {
                print("File in app container, processing directly")
                processFile(at: url)
                return
            }
        }

        print("Attempting security-scoped resource access")
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
    }
    
    private func getFileSize(at url: URL) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? Int64 {
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useKB, .useMB, .useGB]
                formatter.countStyle = .file
                return formatter.string(fromByteCount: size)
            }
        } catch {
            return "Unknown"
        }
        return "Unknown"
    }

    // MARK: - SwiftUI File Picker Handling

    private func handleSwiftUIFileSelection(_ url: URL) {
        confirmAndProcessFile(at: url)
    }
}

// MARK: - SwiftUI File Picker Controller

class SwiftUIFilePickerViewController {
    private var sceneDelegateWrapper: SceneDelegateWrapper
    private var onFileSelected: (URL) -> Void

    init(sceneDelegateWrapper: SceneDelegateWrapper, onFileSelected: @escaping (URL) -> Void) {
        self.sceneDelegateWrapper = sceneDelegateWrapper
        self.onFileSelected = onFileSelected
    }

    func presentFilePicker() {
        print("SwiftUIFilePickerViewController.presentFilePicker() called")
        
        let contentTypes = [UTType.item, UTType.folder]
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        documentPicker.allowsMultipleSelection = false
        documentPicker.shouldShowFileExtensions = true
        
        let delegate = DocumentPickerDelegate { [weak self] urls in
            print("Document picker callback with \(urls.count) URLs")
            guard let self = self, let url = urls.first else {
                print("No URLs or self is nil")
                return
            }
            self.onFileSelected(url)
        }
        documentPicker.delegate = delegate
        
        objc_setAssociatedObject(documentPicker, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        
        if let rootVC = sceneDelegateWrapper.sceneDelegate?.window.rootViewController {
            print("Presenting document picker directly")
            rootVC.present(documentPicker, animated: true)
        } else {
            print("No root view controller available")
        }
    }
}

private class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private let onPick: ([URL]) -> Void
    
    init(onPick: @escaping ([URL]) -> Void) {
        self.onPick = onPick
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        onPick(urls)
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        print("Document picker cancelled")
    }
}

// MARK: - SwiftUI File Picker View

struct SwiftUIFilePickerView: View {
    @ObservedObject var sceneDelegateWrapper: SceneDelegateWrapper
    @State private var isPresented = false

    var onFileSelected: ([URL]) -> Void

    var body: some View {
        Color.clear
            .documentPicker(
                isPresented: $isPresented,
                types: [UTType.item, UTType.folder],
                multiple: false,
                sceneDelegateWrapper: sceneDelegateWrapper,
                onPick: onFileSelected
            )
            .onAppear {
                print("SwiftUIFilePickerView appeared, triggering presentation")
                DispatchQueue.main.async {
                    print("Setting isPresented = true")
                    isPresented = true
                }
            }
    }
}

// MARK: - UIDropInteractionDelegate

extension FilePickerViewController: UIDropInteractionDelegate {
    
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        return session.hasItemsConforming(toTypeIdentifiers: [
            "public.file-url",
            "public.url",
            "public.data"
        ])
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        return UIDropProposal(operation: .copy)
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        session.loadObjects(ofClass: URL.self) { [weak self] urls in
            guard let self = self,
                  let url = urls.first as? URL else { return }
            
            DispatchQueue.main.async {
                if UserDefaults.standard.useLegacyFilePicker {
                    self.confirmAndProcessFile(at: url)
                } else {
                    self.showOpenConfirmation(for: url)
                }
            }
        }
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: UIDropSession) {
        UIView.animate(withDuration: 0.2) {
            self.selectButton.alpha = 0.7
            self.selectButton.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
        }
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
        UIView.animate(withDuration: 0.2) {
            self.selectButton.alpha = 1.0
            self.selectButton.transform = .identity
        }
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) {
        UIView.animate(withDuration: 0.2) {
            self.selectButton.alpha = 1.0
            self.selectButton.transform = .identity
        }
    }
}

