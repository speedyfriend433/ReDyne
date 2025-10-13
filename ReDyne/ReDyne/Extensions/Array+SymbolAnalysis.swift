import Foundation

extension Array where Element: AnyObject {
    
    func filterSymbols(byType type: String) -> [Element] {
        guard let symbols = self as? [SymbolModel] else { return [] }
        return symbols.filter { $0.type == type } as! [Element]
    }
    
    func filterSymbols(byScope scope: String) -> [Element] {
        guard let symbols = self as? [SymbolModel] else { return [] }
        return symbols.filter { $0.scope == scope } as! [Element]
    }
    
    func definedSymbols() -> [Element] {
        guard let symbols = self as? [SymbolModel] else { return [] }
        return symbols.filter { $0.isDefined } as! [Element]
    }
    
    func undefinedSymbols() -> [Element] {
        guard let symbols = self as? [SymbolModel] else { return [] }
        return symbols.filter { !$0.isDefined } as! [Element]
    }
    
    func functionSymbols() -> [Element] {
        guard let symbols = self as? [SymbolModel] else { return [] }
        return symbols.filter { $0.isFunction } as! [Element]
    }
    
    func searchSymbols(query: String) -> [Element] {
        guard let symbols = self as? [SymbolModel] else { return [] }
        guard !query.isEmpty else { return self }
        
        let lowercased = query.lowercased()
        return symbols.filter { symbol in
            symbol.name.lowercased().contains(lowercased)
        } as! [Element]
    }
    
    func findSymbol(atAddress address: UInt64) -> Element? {
        guard let symbols = self as? [SymbolModel] else { return nil }
        return symbols.first { $0.address == address } as? Element
    }
    
    func findClosestSymbol(toAddress address: UInt64) -> Element? {
        guard let symbols = self as? [SymbolModel] else { return nil }
        
        let sorted = symbols.sorted { $0.address < $1.address }
        var closest: SymbolModel?
        
        for symbol in sorted {
            if symbol.address <= address {
                closest = symbol
            } else {
                break
            }
        }
        
        return closest as? Element
    }
}

extension Array where Element == SymbolModel {
    
    func sortedByAddress(ascending: Bool = true) -> [SymbolModel] {
        return sorted { ascending ? $0.address < $1.address : $0.address > $1.address }
    }
    
    func sortedByName(ascending: Bool = true) -> [SymbolModel] {
        return sorted { ascending ? $0.name < $1.name : $0.name > $1.name }
    }
    
    func sortedBySize(ascending: Bool = true) -> [SymbolModel] {
        return sorted { ascending ? $0.size < $1.size : $0.size > $1.size }
    }
    
    func groupedBySection() -> [UInt8: [SymbolModel]] {
        return Dictionary(grouping: self) { $0.section }
    }
    
    func groupedByType() -> [String: [SymbolModel]] {
        return Dictionary(grouping: self) { $0.type }
    }
    
    func statistics() -> SymbolStatistics {
        var stats = SymbolStatistics()
        
        stats.total = self.count
        stats.defined = self.filter { $0.isDefined }.count
        stats.undefined = self.filter { !$0.isDefined }.count
        stats.external = self.filter { $0.isExternal }.count
        stats.functions = self.filter { $0.isFunction }.count
        stats.weak = self.filter { $0.isWeak }.count
        
        return stats
    }
}

struct SymbolStatistics {
    var total: Int = 0
    var defined: Int = 0
    var undefined: Int = 0
    var external: Int = 0
    var functions: Int = 0
    var weak: Int = 0
    
    var definedPercentage: Double {
        guard total > 0 else { return 0 }
        return Double(defined) / Double(total) * 100
    }
    
    var undefinedPercentage: Double {
        guard total > 0 else { return 0 }
        return Double(undefined) / Double(total) * 100
    }
}


// MARK: - Instruction Array Extensions

extension Array where Element == InstructionModel {
    
    func filter(byCategory category: String) -> [InstructionModel] {
        return filter { $0.category == category }
    }
    
    func branchInstructions() -> [InstructionModel] {
        return filter { $0.branchType != nil && $0.branchType != "None" }
    }
    
    func functionStarts() -> [InstructionModel] {
        return filter { $0.isFunctionStart }
    }
    
    func functionEnds() -> [InstructionModel] {
        return filter { $0.isFunctionEnd }
    }
    
    func find(atAddress address: UInt64) -> InstructionModel? {
        return first { $0.address == address }
    }
    
    func instructions(inRange range: ClosedRange<UInt64>) -> [InstructionModel] {
        return filter { range.contains($0.address) }
    }
    
    func search(mnemonic: String) -> [InstructionModel] {
        let lowercased = mnemonic.lowercased()
        return filter { $0.mnemonic.lowercased().contains(lowercased) }
    }
    
    func search(operands: String) -> [InstructionModel] {
        let lowercased = operands.lowercased()
        return filter { $0.operands.lowercased().contains(lowercased) }
    }
    
    func crossReferences(to address: UInt64) -> [InstructionModel] {
        return filter { $0.hasBranchTarget && $0.branchTarget == address }
    }
}


// MARK: - Function Array Extensions

extension Array where Element == FunctionModel {
    
    func sortedByAddress(ascending: Bool = true) -> [FunctionModel] {
        return sorted { ascending ? $0.startAddress < $1.startAddress : $0.startAddress > $1.startAddress }
    }
    
    func sortedByName(ascending: Bool = true) -> [FunctionModel] {
        return sorted { ascending ? $0.name < $1.name : $0.name > $1.name }
    }
    
    func sortedBySize(ascending: Bool = true) -> [FunctionModel] {
        return sorted { ascending ? $0.instructionCount < $1.instructionCount : $0.instructionCount > $1.instructionCount }
    }
    
    func findFunction(containing address: UInt64) -> FunctionModel? {
        return first { address >= $0.startAddress && address < $0.endAddress }
    }
    
    func search(name: String) -> [FunctionModel] {
        guard !name.isEmpty else { return self }
        let lowercased = name.lowercased()
        return filter { $0.name.lowercased().contains(lowercased) }
    }
}


// MARK: - String Array Extensions

extension Array where Element == StringModel {
    
    func sortedByAddress(ascending: Bool = true) -> [StringModel] {
        return sorted { ascending ? $0.address < $1.address : $0.address > $1.address }
    }
    
    func sortedByLength(ascending: Bool = true) -> [StringModel] {
        return sorted { ascending ? $0.length < $1.length : $0.length > $1.length }
    }
    
    func groupedBySection() -> [String: [StringModel]] {
        return Dictionary(grouping: self) { $0.section }
    }
    
    func cStringsOnly() -> [StringModel] {
        return filter { $0.isCString }
    }
    
    func search(content: String) -> [StringModel] {
        guard !content.isEmpty else { return self }
        let lowercased = content.lowercased()
        return filter { $0.content.lowercased().contains(lowercased) }
    }
    
    func find(atAddress address: UInt64) -> StringModel? {
        return first { $0.address == address }
    }
}


