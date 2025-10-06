import Foundation

@objc class CodeSignatureAnalyzer: NSObject {
    
    @objc static func analyze(machOContext: OpaquePointer) -> CodeSigningAnalysis? {
        let ctx = UnsafeMutablePointer<MachOContext>(machOContext)
        
        print("Analyzing code signature...")
        
        guard let sigInfoPtr = codesign_parse_signature(ctx) else {
            print("Failed to parse signature")
            return nil
        }
        defer { codesign_free_signature(sigInfoPtr) }
        
        let sigInfo = sigInfoPtr.pointee
        var sigInfoCopy = sigInfo
        
        let teamID = withUnsafePointer(to: &sigInfoCopy.team_id.0) { String(cString: $0) }
        let bundleID = withUnsafePointer(to: &sigInfoCopy.bundle_id.0) { String(cString: $0) }
        
        var entitlementsData: EntitlementsData? = nil
        if sigInfo.has_entitlements {
            if let entInfoPtr = codesign_parse_entitlements(ctx) {
                defer { codesign_free_entitlements(entInfoPtr) }
                
                let entInfo = entInfoPtr.pointee
                let xmlString: String? = entInfo.entitlements_xml != nil ? 
                    String(cString: entInfo.entitlements_xml) : nil
                
                entitlementsData = EntitlementsData(rawXML: xmlString)
            }
        }
        
        let signingInfo = CodeSigningInfo(
            isSigned: sigInfo.is_signed,
            isAdHocSigned: sigInfo.is_adhoc_signed,
            hasEntitlements: sigInfo.has_entitlements,
            signatureSize: sigInfo.signature_size,
            teamID: teamID,
            bundleID: bundleID,
            entitlements: entitlementsData
        )
        
        let analysis = CodeSigningAnalysis(signingInfo: signingInfo)
        
        print("Code signature analysis complete")
        print("   • Signed: \(sigInfo.is_signed ? "Yes" : "No")")
        if sigInfo.is_signed {
            print("   • Type: \(sigInfo.is_adhoc_signed ? "Ad-hoc" : "Full")")
            print("   • Entitlements: \(sigInfo.has_entitlements ? "Yes" : "No")")
        }
        
        return analysis
    }
}

