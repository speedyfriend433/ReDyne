import UIKit

extension UIViewController {
    
    func showRenameDialog(
        for address: UInt64,
        binaryPath: String,
        currentName: String,
        completion: @escaping (String?) -> Void
    ) {
        let existingName = FunctionDatabase.shared.getName(binaryPath: binaryPath, address: address)
        
        let alert = UIAlertController(
            title: "Rename Function",
            message: "Enter a new name for this function\nAddress: 0x\(String(format: "%llX", address))",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = currentName
            textField.text = existingName ?? ""
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
            textField.spellCheckingType = .no
        }
        
        alert.addAction(UIAlertAction(title: "Rename", style: .default) { _ in
            guard let newName = alert.textFields?.first?.text,
                  !newName.isEmpty else {
                completion(nil)
                return
            }
            
            if self.isValidFunctionName(newName) {
                FunctionDatabase.shared.rename(
                    binaryPath: binaryPath,
                    address: address,
                    newName: newName
                )
                completion(newName)
            } else {
                self.showErrorAlert(message: "Invalid function name. Use only letters, numbers, and underscores. Must start with a letter or underscore.")
                completion(nil)
            }
        })
        
        if existingName != nil {
            alert.addAction(UIAlertAction(title: "Reset to Default", style: .destructive) { _ in
                FunctionDatabase.shared.deleteName(binaryPath: binaryPath, address: address)
                completion(currentName)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completion(nil)
        })
        
        present(alert, animated: true)
    }
    
    func showCommentDialog(
        for address: UInt64,
        binaryPath: String,
        completion: @escaping (String?) -> Void
    ) {
        let existingComment = FunctionDatabase.shared.getComment(binaryPath: binaryPath, address: address)
        
        let alert = UIAlertController(
            title: "Add Comment",
            message: "Add a comment for this function\nAddress: 0x\(String(format: "%llX", address))",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "Enter comment..."
            textField.text = existingComment ?? ""
        }
        
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            guard let comment = alert.textFields?.first?.text else {
                completion(nil)
                return
            }
            
            FunctionDatabase.shared.addComment(
                binaryPath: binaryPath,
                address: address,
                comment: comment
            )
            completion(comment.isEmpty ? nil : comment)
        })
        
        if existingComment != nil {
            alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { _ in
                FunctionDatabase.shared.addComment(
                    binaryPath: binaryPath,
                    address: address,
                    comment: ""
                )
                completion(nil)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completion(nil)
        })
        
        present(alert, animated: true)
    }
    
    func showDatabaseOptions(for binaryPath: String) {
        let stats = FunctionDatabase.shared.getStatistics(for: binaryPath)
        
        let alert = UIAlertController(
            title: "Function Database",
            message: """
            Renamed Functions: \(stats.renamedCount)
            Comments: \(stats.commentCount)
            Tags: \(stats.tagCount)
            """,
            preferredStyle: .actionSheet
        )
        
        alert.addAction(UIAlertAction(title: "Export Database", style: .default) { _ in
            self.exportDatabase(for: binaryPath)
        })
        
        alert.addAction(UIAlertAction(title: "Import Database", style: .default) { _ in
            self.importDatabase()
        })
        
        if stats.renamedCount > 0 || stats.commentCount > 0 {
            alert.addAction(UIAlertAction(title: "Clear This Binary's Data", style: .destructive) { _ in
                self.confirmClearDatabase(for: binaryPath)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        present(alert, animated: true)
    }
    
    // MARK: - Helper Methods
    
    private func isValidFunctionName(_ name: String) -> Bool {
        let pattern = "^[a-zA-Z_][a-zA-Z0-9_]*$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }
    
    private func exportDatabase(for binaryPath: String) {
        guard let data = FunctionDatabase.shared.exportDatabase(for: binaryPath) else {
            showErrorAlert(message: "Failed to export database")
            return
        }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("ReDyne_Functions.json")
        
        do {
            try data.write(to: tempURL)
            
            let activityVC = UIActivityViewController(
                activityItems: [tempURL],
                applicationActivities: nil
            )
            
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            }
            
            present(activityVC, animated: true)
        } catch {
            showErrorAlert(message: "Failed to save export file: \(error.localizedDescription)")
        }
    }
    
    private func importDatabase() {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.json])
        documentPicker.delegate = self as? UIDocumentPickerDelegate
        documentPicker.allowsMultipleSelection = false
        present(documentPicker, animated: true)
    }
    
    private func confirmClearDatabase(for binaryPath: String) {
        let alert = UIAlertController(
            title: "Clear Database?",
            message: "This will delete all renamed functions and comments for this binary. This cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { _ in
            FunctionDatabase.shared.clearDatabase(for: binaryPath)
            self.showSuccessAlert(message: "Database cleared successfully")
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func showErrorAlert(message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func showSuccessAlert(message: String) {
        let alert = UIAlertController(title: "Success", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

