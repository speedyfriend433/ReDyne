import Foundation
import UIKit

enum ReDyneError: LocalizedError {
    case invalidFile
    case invalidMachO(reason: String)
    case parseFailure(detail: String)
    case encryptedBinary
    case fileTooLarge(size: Int64, limit: Int64)
    case noCodeSection
    case disassemblyFailed
    case unsupportedArchitecture(arch: String)
    case fileAccessDenied
    case outOfMemory
    
    var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "Invalid or corrupted file"
        case .invalidMachO(let reason):
            return "Invalid Mach-O binary: \(reason)"
        case .parseFailure(let detail):
            return "Failed to parse binary: \(detail)"
        case .encryptedBinary:
            return "Binary is encrypted"
        case .fileTooLarge(let size, let limit):
            return "File too large: \(size) bytes (limit: \(limit) bytes)"
        case .noCodeSection:
            return "No executable code section found"
        case .disassemblyFailed:
            return "Disassembly process failed"
        case .unsupportedArchitecture(let arch):
            return "Unsupported architecture: \(arch)"
        case .fileAccessDenied:
            return "File access denied"
        case .outOfMemory:
            return "Out of memory"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidFile:
            return "Please select a valid dylib or Mach-O binary file."
        case .invalidMachO:
            return "Ensure the file is a valid iOS/macOS dynamic library (.dylib)."
        case .parseFailure:
            return "The binary may be corrupted or use an unsupported format."
        case .encryptedBinary:
            return "Encrypted binaries cannot be decompiled. Try decrypting first or select an unencrypted binary."
        case .fileTooLarge:
            return "Try selecting a smaller binary file (limit: 200MB)."
        case .noCodeSection:
            return "This binary doesn't contain executable code to disassemble."
        case .disassemblyFailed:
            return "Try restarting the app or selecting a different binary."
        case .unsupportedArchitecture:
            return "Only ARM64 and x86_64 architectures are currently supported."
        case .fileAccessDenied:
            return "Grant file access permissions in Settings."
        case .outOfMemory:
            return "Close other apps to free up memory and try again."
        }
    }
    
    var failureReason: String? {
        switch self {
        case .invalidFile:
            return "The file could not be opened or read."
        case .invalidMachO:
            return "Magic number validation failed."
        case .parseFailure:
            return "Binary structure could not be parsed."
        case .encryptedBinary:
            return "The binary's code section is encrypted."
        case .fileTooLarge:
            return "File size exceeds maximum processing limit."
        case .noCodeSection:
            return "No __text section found in binary."
        case .disassemblyFailed:
            return "Instruction decoding failed."
        case .unsupportedArchitecture:
            return "CPU architecture not supported by disassembler."
        case .fileAccessDenied:
            return "Sandbox restrictions prevent file access."
        case .outOfMemory:
            return "Insufficient memory for processing."
        }
    }
}

class ErrorHandler {
    
    static func showError(_ error: Error, in viewController: UIViewController, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(
            title: "Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        
        if let localError = error as? ReDyneError, let recovery = localError.recoverySuggestion {
            alert.message = "\(error.localizedDescription)\n\n\(recovery)"
        }
        
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completion?()
        })
        
        viewController.present(alert, animated: true)
    }
    
    static func convert(_ error: NSError) -> ReDyneError {
        guard error.domain == "com.jian.ReDyne.BinaryParser" ||
              error.domain == "com.jian.ReDyne.Disassembler" else {
            return .parseFailure(detail: error.localizedDescription)
        }
        
        let errorMessage = error.localizedDescription
        
        switch error.code {
        case 1001, 2001:
            if errorMessage.contains("0x") || errorMessage.contains("magic") {
                return .invalidMachO(reason: errorMessage)
            }
            return .invalidFile
        case 1002:
            return .invalidMachO(reason: errorMessage)
        case 1003, 2003:
            return .parseFailure(detail: errorMessage)
        case 1004:
            return .encryptedBinary
        case 1005:
            if errorMessage.contains("bytes") {
                return .parseFailure(detail: errorMessage)
            }
            return .fileTooLarge(size: 0, limit: 200_000_000)
        case 2002:
            return .noCodeSection
        default:
            return .parseFailure(detail: errorMessage)
        }
    }
    
    static func log(_ error: Error, function: String = #function, file: String = #file, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        print("❌ ERROR [\(fileName):\(line) \(function)]: \(error.localizedDescription)")
        
        if let localError = error as? ReDyneError, let reason = localError.failureReason {
            print("   Reason: \(reason)")
        }
        
        if let nsError = error as NSError? {
            print("   Domain: \(nsError.domain)")
            print("   Code: \(nsError.code)")
            if let userInfo = nsError.userInfo as? [String: Any], !userInfo.isEmpty {
                print("   UserInfo: \(userInfo)")
            }
        }
    }
}

