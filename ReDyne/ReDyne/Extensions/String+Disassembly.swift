import Foundation
import UIKit

extension String {
    
    var isARM64Register: Bool {
        let regPattern = "^[XW]([0-9]|[12][0-9]|30|SP|ZR)$"
        return self.range(of: regPattern, options: .regularExpression) != nil
    }
    
    var isImmediate: Bool {
        return self.hasPrefix("#") || self.hasPrefix("0x")
    }
    
    var isMemoryOperand: Bool {
        return self.contains("[") && self.contains("]")
    }
    
    var hexValue: UInt64? {
        let cleaned = self.replacingOccurrences(of: "0x", with: "")
                          .replacingOccurrences(of: "#", with: "")
                          .trimmingCharacters(in: .whitespaces)
        return UInt64(cleaned, radix: 16)
    }
    
    func asMonospaced(size: CGFloat = 12) -> NSAttributedString {
        let font = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        return NSAttributedString(string: self, attributes: [.font: font])
    }
    
    func highlightedAsAssembly() -> NSAttributedString {
        let attrString = NSMutableAttributedString()
        let components = self.components(separatedBy: .whitespaces)
        
        guard components.count >= 2 else {
            return NSAttributedString(string: self)
        }
        
        if let addressPart = components.first, addressPart.contains("0x") {
            let addressAttr: [NSAttributedString.Key: Any] = [
                .foregroundColor: Constants.Colors.addressColor,
                .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            ]
            attrString.append(NSAttributedString(string: addressPart + " ", attributes: addressAttr))
        }
        
        if components.count > 1 {
            let mnemonic = components[1]
            let isBranch = mnemonic.hasPrefix("B") || mnemonic.contains("RET")
            let color = isBranch ? Constants.Colors.branchColor : Constants.Colors.opcodeColor
            
            let mnemonicAttr: [NSAttributedString.Key: Any] = [
                .foregroundColor: color,
                .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .bold)
            ]
            attrString.append(NSAttributedString(string: mnemonic + " ", attributes: mnemonicAttr))
        }
        
        if components.count > 2 {
            let operands = components.dropFirst(2).joined(separator: " ")
            let operandAttr = highlightOperands(operands)
            attrString.append(operandAttr)
        }
        
        return attrString
    }
    
    private func highlightOperands(_ operands: String) -> NSAttributedString {
        let attrString = NSMutableAttributedString()
        let font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let parts = operands.components(separatedBy: CharacterSet(charactersIn: ", "))
        
        for (index, part) in parts.enumerated() {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            var color = Constants.Colors.registerColor
            
            if trimmed.isImmediate {
                color = Constants.Colors.immediateColor
            } else if trimmed.isARM64Register {
                color = Constants.Colors.registerColor
            } else if trimmed.contains("[") || trimmed.contains("]") {
                color = Constants.Colors.immediateColor
            } else if trimmed.hasPrefix("0x") {
                color = Constants.Colors.branchColor
            }
            
            let attr: [NSAttributedString.Key: Any] = [
                .foregroundColor: color,
                .font: font
            ]
            
            attrString.append(NSAttributedString(string: trimmed, attributes: attr))
            
            if index < parts.count - 1 {
                attrString.append(NSAttributedString(string: ", ", attributes: attr))
            }
        }
        
        return attrString
    }
    
    func truncated(to length: Int, trailing: String = "...") -> String {
        guard self.count > length else { return self }
        return String(self.prefix(length)) + trailing
    }
    
    func padded(toWidth width: Int, with character: Character = " ", alignment: PaddingAlignment = .left) -> String {
        guard self.count < width else { return self }
        let padding = String(repeating: character, count: width - self.count)
        
        switch alignment {
        case .left:
            return self + padding
        case .right:
            return padding + self
        case .center:
            let leftPad = padding.count / 2
            let rightPad = padding.count - leftPad
            return String(repeating: character, count: leftPad) + self + String(repeating: character, count: rightPad)
        }
    }
    
    enum PaddingAlignment {
        case left, right, center
    }
}

// MARK: - Instruction Formatting

extension String {
    
    static func formatInstruction(address: UInt64, bytes: String, mnemonic: String, operands: String, comment: String? = nil) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let addressStr = String(format: "0x%016llX: ", address)
        let addressAttr: [NSAttributedString.Key: Any] = [
            .foregroundColor: Constants.Colors.addressColor,
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        ]
        result.append(NSAttributedString(string: addressStr, attributes: addressAttr))
        
        let bytesStr = bytes.padded(toWidth: 10) + " "
        let bytesAttr: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.systemGray3,
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        ]
        result.append(NSAttributedString(string: bytesStr, attributes: bytesAttr))
        
        let isBranch = mnemonic.hasPrefix("B") || mnemonic.contains("RET")
        let mnemonicColor = isBranch ? Constants.Colors.branchColor : Constants.Colors.opcodeColor
        let mnemonicStr = mnemonic.padded(toWidth: 8) + " "
        let mnemonicAttr: [NSAttributedString.Key: Any] = [
            .foregroundColor: mnemonicColor,
            .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        ]
        result.append(NSAttributedString(string: mnemonicStr, attributes: mnemonicAttr))
        
        let operandAttr: [NSAttributedString.Key: Any] = [
            .foregroundColor: Constants.Colors.registerColor,
            .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        ]
        result.append(NSAttributedString(string: operands, attributes: operandAttr))
        
        if let comment = comment, !comment.isEmpty {
            let commentStr = "  ; " + comment
            let commentAttr: [NSAttributedString.Key: Any] = [
                .foregroundColor: Constants.Colors.commentColor,
                .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            ]
            result.append(NSAttributedString(string: commentStr, attributes: commentAttr))
        }
        
        return result
    }
}

