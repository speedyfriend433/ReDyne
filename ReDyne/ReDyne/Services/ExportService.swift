import Foundation
import UIKit

enum ExportFormat {
    case text
    case json
    case html
    
    var fileExtension: String {
        switch self {
        case .text: return "txt"
        case .json: return "json"
        case .html: return "html"
        }
    }
    
    var mimeType: String {
        switch self {
        case .text: return "text/plain"
        case .json: return "application/json"
        case .html: return "text/html"
        }
    }
    
    var displayName: String {
        switch self {
        case .text: return "Plain Text"
        case .json: return "JSON"
        case .html: return "HTML Report"
        }
    }
}

class ExportService {
    
    // MARK: - Public Export Methods
    
    static func export(_ output: DecompiledOutput, format: ExportFormat) -> Data? {
        switch format {
        case .text:
            return exportAsText(output)
        case .json:
            return exportAsJSON(output)
        case .html:
            return exportAsHTML(output)
        }
    }
    
    static func generateFilename(for output: DecompiledOutput, format: ExportFormat) -> String {
        let baseName = (output.fileName as NSString).deletingPathExtension
        let timestamp = DateFormatter.filenameDateFormatter.string(from: Date())
        return "\(baseName)_analysis_\(timestamp).\(format.fileExtension)"
    }
    
    // MARK: - Text Export
    
    private static func exportAsText(_ output: DecompiledOutput) -> Data? {
        var text = ""
        
        text += "═══════════════════════════════════════════════════════════════\n"
        text += "  ReDyne Decompilation Report\n"
        text += "═══════════════════════════════════════════════════════════════\n\n"
        
        text += "File: \(output.fileName)\n"
        text += "Size: \(Constants.formatBytes(Int64(output.fileSize)))\n"
        text += "Analyzed: \(DateFormatter.reportDateFormatter.string(from: output.processingDate))\n"
        text += "Processing Time: \(Constants.formatDuration(output.processingTime))\n\n"
        
        text += "───────────────────────────────────────────────────────────────\n"
        text += "MACH-O HEADER\n"
        text += "───────────────────────────────────────────────────────────────\n\n"
        text += "CPU Type: \(output.header.cpuType)\n"
        text += "File Type: \(output.header.fileType)\n"
        text += "Architecture: \(output.header.is64Bit ? "64-bit" : "32-bit")\n"
        text += "Load Commands: \(output.header.ncmds)\n"
        text += "Flags: 0x\(String(format: "%X", output.header.flags))\n"
        if let uuid = output.header.uuid {
            text += "UUID: \(uuid)\n"
        }
        text += "Encrypted: \(output.header.isEncrypted ? "Yes" : "No")\n\n"
        
        text += "───────────────────────────────────────────────────────────────\n"
        text += "SEGMENTS (\(output.segments.count))\n"
        text += "───────────────────────────────────────────────────────────────\n\n"
        for segment in output.segments {
            let paddedName = segment.name.padding(toLength: 16, withPad: " ", startingAt: 0)
            text += "\(paddedName) VM: \(Constants.formatAddress(segment.vmAddress))-\(Constants.formatAddress(segment.vmAddress + segment.vmSize))"
            text += "  File: 0x\(String(format: "%llX", segment.fileOffset))-0x\(String(format: "%llX", segment.fileOffset + segment.fileSize))"
            text += "  [\(segment.protection)]\n"
        }
        text += "\n"
        
        text += "───────────────────────────────────────────────────────────────\n"
        text += "STATISTICS\n"
        text += "───────────────────────────────────────────────────────────────\n\n"
        text += "Total Symbols: \(output.totalSymbols)\n"
        text += "  - Defined: \(output.definedSymbols)\n"
        text += "  - Undefined: \(output.undefinedSymbols)\n"
        text += "Total Strings: \(output.totalStrings)\n"
        text += "Total Instructions: \(output.totalInstructions)\n"
        text += "Total Functions: \(output.totalFunctions)\n\n"
        
        if !output.strings.isEmpty {
            text += "───────────────────────────────────────────────────────────────\n"
            text += "STRINGS (First 100 of \(output.strings.count))\n"
            text += "───────────────────────────────────────────────────────────────\n\n"
            for (index, string) in output.strings.prefix(100).enumerated() {
                text += "\(Constants.formatAddress(string.address))  [\(string.section)]  \(string.content.prefix(80))\n"
                if index >= 99 && output.strings.count > 100 {
                    text += "... and \(output.strings.count - 100) more strings\n"
                }
            }
            text += "\n"
        }
        
        if !output.symbols.isEmpty {
            text += "───────────────────────────────────────────────────────────────\n"
            text += "SYMBOLS (First 100 of \(output.symbols.count))\n"
            text += "───────────────────────────────────────────────────────────────\n\n"
            let sortedSymbols = output.symbols.sortedByAddress()
            for (index, symbol) in sortedSymbols.prefix(100).enumerated() {
                let typeStr = symbol.type.padding(toLength: 10, withPad: " ", startingAt: 0)
                text += "\(Constants.formatAddress(symbol.address))  \(typeStr)  \(symbol.name)\n"
                if index >= 99 && sortedSymbols.count > 100 {
                    text += "... and \(sortedSymbols.count - 100) more symbols\n"
                }
            }
            text += "\n"
        }
        
        text += "═══════════════════════════════════════════════════════════════\n"
        text += "End of Report - Generated by ReDyne v1.0\n"
        text += "═══════════════════════════════════════════════════════════════\n"
        
        return text.data(using: .utf8)
    }
    
    // MARK: - JSON Export
    
    private static func exportAsJSON(_ output: DecompiledOutput) -> Data? {
        var json: [String: Any] = [:]
        
        json["metadata"] = [
            "generator": "ReDyne v1.0",
            "generated_at": ISO8601DateFormatter().string(from: output.processingDate),
            "processing_time_seconds": output.processingTime
        ]
        
        json["file"] = [
            "name": output.fileName,
            "path": output.filePath,
            "size_bytes": output.fileSize
        ]
        
        json["header"] = [
            "cpu_type": output.header.cpuType,
            "file_type": output.header.fileType,
            "architecture": output.header.is64Bit ? "64-bit" : "32-bit",
            "is_64bit": output.header.is64Bit,
            "load_commands_count": output.header.ncmds,
            "flags": String(format: "0x%X", output.header.flags),
            "uuid": output.header.uuid ?? "",
            "is_encrypted": output.header.isEncrypted
        ]
        
        json["segments"] = output.segments.map { segment in
            return [
                "name": segment.name,
                "vm_address": String(format: "0x%llX", segment.vmAddress),
                "vm_size": segment.vmSize,
                "file_offset": segment.fileOffset,
                "file_size": segment.fileSize,
                "protection": segment.protection
            ]
        }
        
        json["statistics"] = [
            "total_symbols": output.totalSymbols,
            "defined_symbols": output.definedSymbols,
            "undefined_symbols": output.undefinedSymbols,
            "total_strings": output.totalStrings,
            "total_instructions": output.totalInstructions,
            "total_functions": output.totalFunctions
        ]
        
        json["strings"] = output.strings.map { string in
            return [
                "address": String(format: "0x%llX", string.address),
                "offset": string.offset,
                "length": string.length,
                "section": string.section,
                "is_cstring": string.isCString,
                "content": string.content
            ]
        }
        
        json["symbols"] = output.symbols.map { symbol in
            return [
                "name": symbol.name,
                "address": String(format: "0x%llX", symbol.address),
                "size": symbol.size,
                "type": symbol.type,
                "scope": symbol.scope,
                "is_defined": symbol.isDefined,
                "is_external": symbol.isExternal,
                "is_function": symbol.isFunction
            ]
        }
        
        if !output.functions.isEmpty {
            json["functions"] = output.functions.map { function in
                return [
                    "name": function.name,
                    "start_address": String(format: "0x%llX", function.startAddress),
                    "end_address": String(format: "0x%llX", function.endAddress),
                    "instruction_count": function.instructionCount
                ]
            }
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            return jsonData
        } catch {
            print("JSON export error: \(error)")
            return nil
        }
    }
    
    // MARK: - HTML Export
    
    private static func exportAsHTML(_ output: DecompiledOutput) -> Data? {
        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(output.fileName) - ReDyne Analysis</title>
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    padding: 20px;
                    color: #333;
                }
                .container {
                    max-width: 1200px;
                    margin: 0 auto;
                    background: white;
                    border-radius: 16px;
                    box-shadow: 0 20px 60px rgba(0,0,0,0.3);
                    overflow: hidden;
                }
                .header {
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    color: white;
                    padding: 40px;
                    text-align: center;
                }
                .header h1 {
                    font-size: 36px;
                    font-weight: 700;
                    margin-bottom: 10px;
                    text-shadow: 0 2px 4px rgba(0,0,0,0.2);
                }
                .header p {
                    font-size: 14px;
                    opacity: 0.9;
                }
                .content {
                    padding: 40px;
                }
                .section {
                    margin-bottom: 40px;
                }
                .section-title {
                    font-size: 24px;
                    font-weight: 600;
                    color: #667eea;
                    margin-bottom: 20px;
                    padding-bottom: 10px;
                    border-bottom: 3px solid #667eea;
                }
                .info-grid {
                    display: grid;
                    grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
                    gap: 15px;
                    margin-bottom: 20px;
                }
                .info-item {
                    background: #f8f9fa;
                    padding: 15px;
                    border-radius: 8px;
                    border-left: 4px solid #667eea;
                }
                .info-label {
                    font-size: 12px;
                    color: #666;
                    text-transform: uppercase;
                    font-weight: 600;
                    letter-spacing: 0.5px;
                    margin-bottom: 5px;
                }
                .info-value {
                    font-size: 16px;
                    color: #333;
                    font-weight: 500;
                    font-family: 'SF Mono', 'Monaco', monospace;
                }
                .table-container {
                    overflow-x: auto;
                    border-radius: 8px;
                    border: 1px solid #e0e0e0;
                }
                table {
                    width: 100%;
                    border-collapse: collapse;
                    font-size: 13px;
                }
                thead {
                    background: #667eea;
                    color: white;
                }
                th {
                    padding: 12px 15px;
                    text-align: left;
                    font-weight: 600;
                    text-transform: uppercase;
                    font-size: 11px;
                    letter-spacing: 0.5px;
                }
                td {
                    padding: 10px 15px;
                    border-bottom: 1px solid #f0f0f0;
                }
                tbody tr:hover {
                    background: #f8f9fa;
                }
                .mono {
                    font-family: 'SF Mono', 'Monaco', 'Courier New', monospace;
                    font-size: 12px;
                    background: #f8f9fa;
                    padding: 2px 6px;
                    border-radius: 4px;
                }
                .badge {
                    display: inline-block;
                    padding: 4px 12px;
                    border-radius: 12px;
                    font-size: 11px;
                    font-weight: 600;
                    text-transform: uppercase;
                }
                .badge-success { background: #d4edda; color: #155724; }
                .badge-warning { background: #fff3cd; color: #856404; }
                .badge-info { background: #d1ecf1; color: #0c5460; }
                .stats-grid {
                    display: grid;
                    grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
                    gap: 20px;
                }
                .stat-card {
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    color: white;
                    padding: 20px;
                    border-radius: 12px;
                    text-align: center;
                    box-shadow: 0 4px 12px rgba(102, 126, 234, 0.3);
                }
                .stat-value {
                    font-size: 32px;
                    font-weight: 700;
                    margin-bottom: 5px;
                }
                .stat-label {
                    font-size: 12px;
                    opacity: 0.9;
                    text-transform: uppercase;
                    letter-spacing: 0.5px;
                }
                .footer {
                    background: #f8f9fa;
                    padding: 20px;
                    text-align: center;
                    color: #666;
                    font-size: 13px;
                    border-top: 1px solid #e0e0e0;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>⚙️ ReDyne Analysis Report</h1>
                    <p>\(output.fileName)</p>
                </div>
                
                <div class="content">
                    <div class="section">
                        <h2 class="section-title">📄 File Information</h2>
                        <div class="info-grid">
                            <div class="info-item">
                                <div class="info-label">Filename</div>
                                <div class="info-value">\(output.fileName)</div>
                            </div>
                            <div class="info-item">
                                <div class="info-label">File Size</div>
                                <div class="info-value">\(Constants.formatBytes(Int64(output.fileSize)))</div>
                            </div>
                            <div class="info-item">
                                <div class="info-label">Analysis Date</div>
                                <div class="info-value">\(DateFormatter.reportDateFormatter.string(from: output.processingDate))</div>
                            </div>
                            <div class="info-item">
                                <div class="info-label">Processing Time</div>
                                <div class="info-value">\(Constants.formatDuration(output.processingTime))</div>
                            </div>
                        </div>
                    </div>
                    
                    <div class="section">
                        <h2 class="section-title">🔧 Mach-O Header</h2>
                        <div class="info-grid">
                            <div class="info-item">
                                <div class="info-label">CPU Type</div>
                                <div class="info-value">\(output.header.cpuType)</div>
                            </div>
                            <div class="info-item">
                                <div class="info-label">File Type</div>
                                <div class="info-value">\(output.header.fileType)</div>
                            </div>
                            <div class="info-item">
                                <div class="info-label">Architecture</div>
                                <div class="info-value">\(output.header.is64Bit ? "64-bit" : "32-bit")</div>
                            </div>
                            <div class="info-item">
                                <div class="info-label">Load Commands</div>
                                <div class="info-value">\(output.header.ncmds)</div>
                            </div>
                            <div class="info-item">
                                <div class="info-label">Flags</div>
                                <div class="info-value">0x\(String(format: "%X", output.header.flags))</div>
                            </div>
                            <div class="info-item">
                                <div class="info-label">Encrypted</div>
                                <div class="info-value">\(output.header.isEncrypted ? "🔒 Yes" : "🔓 No")</div>
                            </div>
                        </div>
                    </div>
                    
                    <div class="section">
                        <h2 class="section-title">📊 Statistics</h2>
                        <div class="stats-grid">
                            <div class="stat-card">
                                <div class="stat-value">\(output.totalSymbols)</div>
                                <div class="stat-label">Symbols</div>
                            </div>
                            <div class="stat-card">
                                <div class="stat-value">\(output.totalStrings)</div>
                                <div class="stat-label">Strings</div>
                            </div>
                            <div class="stat-card">
                                <div class="stat-value">\(output.totalInstructions)</div>
                                <div class="stat-label">Instructions</div>
                            </div>
                            <div class="stat-card">
                                <div class="stat-value">\(output.totalFunctions)</div>
                                <div class="stat-label">Functions</div>
                            </div>
                            <div class="stat-card">
                                <div class="stat-value">\(output.segments.count)</div>
                                <div class="stat-label">Segments</div>
                            </div>
                            <div class="stat-card">
                                <div class="stat-value">\(output.sections.count)</div>
                                <div class="stat-label">Sections</div>
                            </div>
                        </div>
                    </div>
                    
                    <div class="section">
                        <h2 class="section-title">📦 Segments (\(output.segments.count))</h2>
                        <div class="table-container">
                            <table>
                                <thead>
                                    <tr>
                                        <th>Name</th>
                                        <th>VM Address</th>
                                        <th>VM Size</th>
                                        <th>File Offset</th>
                                        <th>Protection</th>
                                    </tr>
                                </thead>
                                <tbody>
        """
        
        for segment in output.segments {
            html += """
                                    <tr>
                                        <td><strong>\(segment.name)</strong></td>
                                        <td><span class="mono">\(Constants.formatAddress(segment.vmAddress))</span></td>
                                        <td>\(Constants.formatBytes(Int64(segment.vmSize)))</td>
                                        <td><span class="mono">0x\(String(format: "%llX", segment.fileOffset))</span></td>
                                        <td><span class="badge badge-info">\(segment.protection)</span></td>
                                    </tr>
            """
        }
        
        html += """
                                </tbody>
                            </table>
                        </div>
                    </div>
                    
                    <div class="section">
                        <h2 class="section-title">🔤 Strings (First 50 of \(output.totalStrings))</h2>
                        <div class="table-container">
                            <table>
                                <thead>
                                    <tr>
                                        <th>Address</th>
                                        <th>Section</th>
                                        <th>Content</th>
                                    </tr>
                                </thead>
                                <tbody>
        """
        
        for string in output.strings.prefix(50) {
            let escapedContent = string.content
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .prefix(100)
            html += """
                                    <tr>
                                        <td><span class="mono">\(Constants.formatAddress(string.address))</span></td>
                                        <td><span class="badge badge-success">\(string.section)</span></td>
                                        <td>\(escapedContent)</td>
                                    </tr>
            """
        }
        
        html += """
                                </tbody>
                            </table>
                        </div>
                    </div>
                </div>
                
                <div class="footer">
                    Generated by <strong>ReDyne v1.0</strong> • Epic Mach-O Decompiler
                </div>
            </div>
        </body>
        </html>
        """
        
        return html.data(using: .utf8)
    }
}

// MARK: - Date Formatter Extensions

extension DateFormatter {
    static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
    
    static let reportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

