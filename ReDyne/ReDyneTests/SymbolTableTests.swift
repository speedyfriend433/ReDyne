import XCTest
@testable import ReDyne

class SymbolTableTests: XCTestCase {
    
    var mockSymbols: [SymbolModel] = []
    
    override func setUpWithError() throws {
        let symbol1 = SymbolModel()
        symbol1.name = "_malloc"
        symbol1.address = 0x100001000
        symbol1.type = "Section"
        symbol1.scope = "External"
        symbol1.isDefined = false
        symbol1.isExternal = true
        symbol1.isFunction = true
        
        let symbol2 = SymbolModel()
        symbol2.name = "_main"
        symbol2.address = 0x100002000
        symbol2.type = "Section"
        symbol2.scope = "Global"
        symbol2.isDefined = true
        symbol2.isFunction = true
        
        let symbol3 = SymbolModel()
        symbol3.name = "_helper_func"
        symbol3.address = 0x100003000
        symbol3.type = "Section"
        symbol3.scope = "Local"
        symbol3.isDefined = true
        symbol3.isFunction = true
        
        mockSymbols = [symbol1, symbol2, symbol3]
    }
    
    override func tearDownWithError() throws {
        mockSymbols = []
    }
    
    func testSymbolSorting() throws {
        let sorted = mockSymbols.sortedByAddress()
        
        XCTAssertEqual(sorted[0].address, 0x100001000)
        XCTAssertEqual(sorted[1].address, 0x100002000)
        XCTAssertEqual(sorted[2].address, 0x100003000)
    }
    
    func testSymbolSortingByName() throws {
        let sorted = mockSymbols.sortedByName()
        
        XCTAssertEqual(sorted[0].name, "_helper_func")
        XCTAssertEqual(sorted[1].name, "_main")
        XCTAssertEqual(sorted[2].name, "_malloc")
    }
    
    func testSymbolFiltering() throws {
        let defined = mockSymbols.definedSymbols()
        
        XCTAssertEqual((defined as! [SymbolModel]).count, 2)
    }
    
    func testSymbolSearch() throws {
        let results = mockSymbols.searchSymbols(query: "main")
        
        XCTAssertEqual((results as! [SymbolModel]).count, 1)
        XCTAssertEqual((results as! [SymbolModel])[0].name, "_main")
    }
    
    func testSymbolStatistics() throws {
        let stats = mockSymbols.statistics()
        
        XCTAssertEqual(stats.total, 3)
        XCTAssertEqual(stats.defined, 2)
        XCTAssertEqual(stats.undefined, 1)
        XCTAssertEqual(stats.functions, 3)
    }
    
    func testFindSymbolByAddress() throws {
        let symbol = mockSymbols.findSymbol(atAddress: 0x100002000)
        
        XCTAssertNotNil(symbol)
        XCTAssertEqual((symbol as! SymbolModel).name, "_main")
    }
    
    func testFindClosestSymbol() throws {
        let symbol = mockSymbols.findClosestSymbol(toAddress: 0x100002500)
        
        XCTAssertNotNil(symbol)
        XCTAssertEqual((symbol as! SymbolModel).name, "_main")
    }
}

