import Foundation

// MARK: - Code Signing Information

@objc class CodeSigningInfo: NSObject {
    @objc let isSigned: Bool
    @objc let isAdHocSigned: Bool
    @objc let hasEntitlements: Bool
    @objc let signatureSize: UInt32
    @objc let teamID: String
    @objc let bundleID: String
    @objc let entitlements: EntitlementsData?
    
    init(isSigned: Bool, isAdHocSigned: Bool, hasEntitlements: Bool, 
         signatureSize: UInt32, teamID: String, bundleID: String,
         entitlements: EntitlementsData? = nil) {
        self.isSigned = isSigned
        self.isAdHocSigned = isAdHocSigned
        self.hasEntitlements = hasEntitlements
        self.signatureSize = signatureSize
        self.teamID = teamID
        self.bundleID = bundleID
        self.entitlements = entitlements
        super.init()
    }
    
    @objc var signatureType: String {
        if !isSigned { return "Unsigned" }
        if isAdHocSigned { return "Ad-Hoc Signed" }
        return "Fully Signed"
    }
    
    @objc var signatureSizeString: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(signatureSize))
    }
    
    @objc var isValid: Bool {
        return isSigned
    }
}

// MARK: - Entitlements Data

@objc class EntitlementsData: NSObject {
    @objc let rawXML: String?
    @objc let parsedEntitlements: [String: String]
    
    init(rawXML: String?, parsedEntitlements: [String: String] = [:]) {
        self.rawXML = rawXML
        self.parsedEntitlements = parsedEntitlements
        super.init()
    }
    
    @objc var hasData: Bool {
        return rawXML != nil || !parsedEntitlements.isEmpty
    }
    
    @objc var entitlementCount: Int {
        return parsedEntitlements.count
    }
    
    @objc var formattedXML: String? {
        guard let xml = rawXML else { return nil }
        
        var formatted = ""
        var indentLevel = 0
        let indentString = "  "
        var inTag = false
        var currentTag = ""
        
        var i = xml.startIndex
        while i < xml.endIndex {
            let char = xml[i]
            
            if char == "<" {
                let nextIdx = xml.index(after: i)
                if nextIdx < xml.endIndex && xml[nextIdx] == "/" {
                    indentLevel = max(0, indentLevel - 1)
                    formatted += "\n" + String(repeating: indentString, count: indentLevel)
                } else if !currentTag.isEmpty && !inTag {
                    formatted += "\n" + String(repeating: indentString, count: indentLevel)
                }
                inTag = true
                currentTag = ""
                formatted.append(char)
            } else if char == ">" {
                inTag = false
                formatted.append(char)
                
                let prevIdx = xml.index(before: i)
                if prevIdx >= xml.startIndex && xml[prevIdx] == "/" {
                } else if currentTag.hasPrefix("?") {
                    formatted += "\n"
                } else if currentTag.hasPrefix("/") {
                } else {
                    indentLevel += 1
                }
                currentTag = ""
            } else if inTag {
                currentTag.append(char)
                formatted.append(char)
            } else {
                if !char.isWhitespace || !formatted.last!.isWhitespace {
                    formatted.append(char)
                }
            }
            
            i = xml.index(after: i)
        }
        
        return formatted.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    @objc func hasEntitlement(_ key: String) -> Bool {
        return parsedEntitlements[key] != nil
    }
    
    @objc func entitlementValue(forKey key: String) -> String? {
        return parsedEntitlements[key]
    }
    
    @objc var hasDebugger: Bool {
        return hasEntitlement("get-task-allow")
    }
    
    @objc var hasKeychain: Bool {
        return hasEntitlement("keychain-access-groups")
    }
    
    @objc var hasAppGroups: Bool {
        return hasEntitlement("com.apple.security.application-groups")
    }
    
    @objc var hasNetworkClient: Bool {
        return hasEntitlement("com.apple.security.network.client")
    }
    
    @objc var hasNetworkServer: Bool {
        return hasEntitlement("com.apple.security.network.server")
    }
}

// MARK: - Code Signing Analysis Result

@objc class CodeSigningAnalysis: NSObject {
    @objc let signingInfo: CodeSigningInfo
    
    init(signingInfo: CodeSigningInfo) {
        self.signingInfo = signingInfo
        super.init()
    }
    
    @objc var summary: String {
        var lines: [String] = []
        lines.append("Signature: \(signingInfo.signatureType)")
        if signingInfo.isSigned {
            lines.append("Size: \(signingInfo.signatureSizeString)")
        }
        if signingInfo.hasEntitlements {
            lines.append("Entitlements: Yes")
        }
        return lines.joined(separator: "\n")
    }
}

