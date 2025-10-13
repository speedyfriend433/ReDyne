import Foundation

class ConfigManager {
    static let shared = ConfigManager()

    private let defaults = UserDefaults.standard

    // Analysis options
    var maxAnalysisDepth: Int {
        get { defaults.integer(forKey: "maxAnalysisDepth") == 0 ? 10 : defaults.integer(forKey: "maxAnalysisDepth") }
        set { defaults.set(newValue, forKey: "maxAnalysisDepth") }
    }

    var enableDeepAnalysis: Bool {
        get { defaults.bool(forKey: "enableDeepAnalysis") }
        set { defaults.set(newValue, forKey: "enableDeepAnalysis") }
    }

    var includeDebugInfo: Bool {
        get { defaults.bool(forKey: "includeDebugInfo") }
        set { defaults.set(newValue, forKey: "includeDebugInfo") }
    }

    // Export options
    enum ExportFormat: String, CaseIterable {
        case txt = "TXT"
        case json = "JSON"
        case html = "HTML"
        case pdf = "PDF"
    }

    var defaultExportFormat: ExportFormat {
        get {
            if let raw = defaults.string(forKey: "defaultExportFormat"),
               let format = ExportFormat(rawValue: raw) {
                return format
            }
            return .txt
        }
        set { defaults.set(newValue.rawValue, forKey: "defaultExportFormat") }
    }

    // UI options
    var enableSyntaxHighlighting: Bool {
        get { defaults.object(forKey: "enableSyntaxHighlighting") == nil ? true : defaults.bool(forKey: "enableSyntaxHighlighting") }
        set { defaults.set(newValue, forKey: "enableSyntaxHighlighting") }
    }

    var fontSize: Int {
        get { defaults.integer(forKey: "fontSize") == 0 ? 12 : defaults.integer(forKey: "fontSize") }
        set { defaults.set(newValue, forKey: "fontSize") }
    }

    // Performance options
    var enableCaching: Bool {
        get { defaults.object(forKey: "enableCaching") == nil ? true : defaults.bool(forKey: "enableCaching") }
        set { defaults.set(newValue, forKey: "enableCaching") }
    }

    var maxCacheSizeMB: Int {
        get { defaults.integer(forKey: "maxCacheSizeMB") == 0 ? 100 : defaults.integer(forKey: "maxCacheSizeMB") }
        set { defaults.set(newValue, forKey: "maxCacheSizeMB") }
    }

    // Reset to defaults
    func resetToDefaults() {
        let keys = ["maxAnalysisDepth", "enableDeepAnalysis", "includeDebugInfo", "defaultExportFormat", "enableSyntaxHighlighting", "fontSize", "enableCaching", "maxCacheSizeMB"]
        keys.forEach { defaults.removeObject(forKey: $0) }
    }
}