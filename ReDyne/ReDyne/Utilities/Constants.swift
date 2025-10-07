import Foundation
import UIKit
import UniformTypeIdentifiers

enum Constants {
    
    // MARK: - File Constraints
    
    enum File {
        static let maxFileSize: Int64 = 200 * 1024 * 1024
        static let allowedExtensions = ["dylib", "so", ""]
        static let tempDirectoryName = "ReDyneTempFiles"
    }
    
    // MARK: - UI Configuration
    
    enum UI {
        static let defaultFontSize: CGFloat = 12
        static let titleFontSize: CGFloat = 17
        static let largeTitleFontSize: CGFloat = 34
        static let cornerRadius: CGFloat = 8
        static let borderWidth: CGFloat = 1
        static let standardSpacing: CGFloat = 16
        static let compactSpacing: CGFloat = 8
        static let animationDuration: TimeInterval = 0.3
    }
    
    // MARK: - Colors
    
    enum Colors {
        static let opcodeColor = UIColor.systemBlue
        static let branchColor = UIColor.systemOrange
        static let immediateColor = UIColor.systemGreen
        static let registerColor = UIColor.label
        static let commentColor = UIColor.systemGray
        static let addressColor = UIColor.systemGray2
        static let accentColor = UIColor.systemBlue
        static let errorColor = UIColor.systemRed
        static let successColor = UIColor.systemGreen
        static let warningColor = UIColor.systemOrange
        static let primaryBackground = UIColor.systemBackground
        static let secondaryBackground = UIColor.secondarySystemBackground
        static let tertiaryBackground = UIColor.tertiarySystemBackground
    }
    
    // MARK: - Disassembly Settings
    
    enum Disassembly {
        static let defaultContextLines = 5
        static let maxInstructionsDisplay = 10000
        static let instructionsPerPage = 100
    }
    
    // MARK: - Export Settings
    
    enum Export {
        static let textEncoding = String.Encoding.utf8
        static let htmlTemplate = "ReDyneExport.html"
        static let dotTemplate = "CFG.dot"
    }
    
    // MARK: - User Defaults Keys
    
    enum UserDefaultsKeys {
        static let recentFiles = "com.jian.ReDyne.recentFiles"
        static let lastOpenedPath = "com.jian.ReDyne.lastOpenedPath"
        static let preferredArchitecture = "com.jian.ReDyne.preferredArch"
        static let disassemblyDetailLevel = "com.jian.ReDyne.detailLevel"
        static let syntaxHighlightingEnabled = "com.jian.ReDyne.syntaxHighlight"
        static let useLegacyFilePicker = "com.jian.ReDyne.useLegacyFilePicker"
    }
    
    // MARK: - Architecture Support
    
    enum Architecture {
        static let supported = ["ARM64", "X86_64"]
        static let preferred = "ARM64"
    }
    
    // MARK: - Processing
    
    enum Processing {
        static let backgroundQueueLabel = "com.jian.ReDyne.backgroundQueue"
        static let maxConcurrentOperations = 1
        static let processingTimeout: TimeInterval = 120
    }
}

// MARK: - Helper Extensions

extension UserDefaults {
    
    func getRecentFiles() -> [String] {
        return array(forKey: Constants.UserDefaultsKeys.recentFiles) as? [String] ?? []
    }
    
    func addRecentFile(_ path: String, maxRecent: Int = 10) {
        var recent = getRecentFiles()
        recent.removeAll { $0 == path }
        recent.insert(path, at: 0)
        if recent.count > maxRecent {
            recent = Array(recent.prefix(maxRecent))
        }
        set(recent, forKey: Constants.UserDefaultsKeys.recentFiles)
    }
    
    func clearRecentFiles() {
        removeObject(forKey: Constants.UserDefaultsKeys.recentFiles)
    }
    
    // MARK: - Security-Scoped Bookmarks
    
    private func bookmarkKey(for path: String) -> String {
        return "bookmark_\(path)"
    }
    
    func saveFileBookmark(_ bookmarkData: Data, for path: String) {
        set(bookmarkData, forKey: bookmarkKey(for: path))
    }
    
    func getFileBookmark(for path: String) -> Data? {
        return data(forKey: bookmarkKey(for: path))
    }
    
    func removeFileBookmark(for path: String) {
        removeObject(forKey: bookmarkKey(for: path))
    }
    
    // MARK: - File Picker Preferences
    
    var useLegacyFilePicker: Bool {
        get {
            if object(forKey: Constants.UserDefaultsKeys.useLegacyFilePicker) == nil {
                return true
            }
            return bool(forKey: Constants.UserDefaultsKeys.useLegacyFilePicker)
        }
        set {
            set(newValue, forKey: Constants.UserDefaultsKeys.useLegacyFilePicker)
        }
    }
}

// MARK: - File Type Utilities

extension Constants {

    enum FileTypes {
        static let binaryExtensions = ["dylib", "so", "a", "o", "framework", "bundle"]

        static func binaryUTTypes() -> [UTType] {
            var types: [UTType] = [
                .data,
                .item,
                .executable,
                .unixExecutable
            ]

            for ext in binaryExtensions {
                if let type = UTType(filenameExtension: ext) {
                    types.append(type)
                }
            }

            return types
        }

        static func utType(forExtension ext: String) -> UTType {
            if let type = UTType(filenameExtension: ext) {
                return type
            }
            let exportedIdentifier = "public.\(ext)"
            if let exportedType = try? UTType(exportedAs: exportedIdentifier) {
                return exportedType
            }
            if let importedType = try? UTType(importedAs: exportedIdentifier) {
                return importedType
            }
            return .data
        }

        static func isSupportedBinaryExtension(_ ext: String) -> Bool {
            let lowerExt = ext.lowercased()
            return binaryExtensions.contains(lowerExt) ||
                   lowerExt == "" ||
                   lowerExt == "out" ||
                   lowerExt == "bin"
        }
    }
}

// MARK: - Formatting Utilities

extension Constants {

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static func formatAddress(_ address: UInt64, padding: Int = 16) -> String {
        return String(format: "0x%0\(padding)llX", address)
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        if interval < 1.0 {
            return String(format: "%.0f ms", interval * 1000)
        } else if interval < 60.0 {
            return String(format: "%.2f seconds", interval)
        } else {
            let minutes = Int(interval / 60)
            let seconds = Int(interval.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
    }

    // MARK: - Debug Utilities

    static func logFilePickerMode() {
        let mode = UserDefaults.standard.useLegacyFilePicker ? "Legacy (Enhanced)" : "Modern"
        let enhancedActive = EnhancedFilePicker.isActive()
        print("File Picker Mode: \(mode), Enhanced Active: \(enhancedActive)")
    }
}

