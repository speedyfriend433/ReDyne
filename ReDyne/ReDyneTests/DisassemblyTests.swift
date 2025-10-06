import XCTest
@testable import ReDyne

class DisassemblyTests: XCTestCase {
    
    var mockInstructions: [InstructionModel] = []
    
    override func setUpWithError() throws {
        let inst1 = InstructionModel()
        inst1.address = 0x100001000
        inst1.mnemonic = "MOV"
        inst1.operands = "X0, #42"
        inst1.category = "Data Processing"
        
        let inst2 = InstructionModel()
        inst2.address = 0x100001004
        inst2.mnemonic = "BL"
        inst2.operands = "0x100002000"
        inst2.category = "Branch"
        inst2.branchType = "Call"
        inst2.hasBranchTarget = true
        inst2.branchTarget = 0x100002000
        
        let inst3 = InstructionModel()
        inst3.address = 0x100001008
        inst3.mnemonic = "RET"
        inst3.operands = ""
        inst3.category = "Branch"
        inst3.branchType = "Return"
        inst3.isFunctionEnd = true
        
        mockInstructions = [inst1, inst2, inst3]
    }
    
    override func tearDownWithError() throws {
        mockInstructions = []
    }
    
    func testInstructionFiltering() throws {
        let branches = mockInstructions.branchInstructions()
        
        XCTAssertEqual(branches.count, 2)
        XCTAssertTrue(branches.contains { $0.mnemonic == "BL" })
        XCTAssertTrue(branches.contains { $0.mnemonic == "RET" })
    }
    
    func testInstructionSearch() throws {
        let movs = mockInstructions.search(mnemonic: "MOV")
        
        XCTAssertEqual(movs.count, 1)
        XCTAssertEqual(movs[0].mnemonic, "MOV")
    }
    
    func testFindInstructionAtAddress() throws {
        let inst = mockInstructions.find(atAddress: 0x100001004)
        
        XCTAssertNotNil(inst)
        XCTAssertEqual(inst?.mnemonic, "BL")
    }
    
    func testInstructionRange() throws {
        let range = mockInstructions.instructions(inRange: 0x100001000...0x100001004)
        
        XCTAssertEqual(range.count, 2)
    }
    
    func testFunctionEndDetection() throws {
        let ends = mockInstructions.functionEnds()
        
        XCTAssertEqual(ends.count, 1)
        XCTAssertEqual(ends[0].mnemonic, "RET")
    }
    
    func testRegisterValidation() throws {
        XCTAssertTrue("X0".isARM64Register)
        XCTAssertTrue("W15".isARM64Register)
        XCTAssertTrue("SP".isARM64Register)
        XCTAssertFalse("R0".isARM64Register)
        XCTAssertFalse("invalid".isARM64Register)
    }
    
    func testImmediateDetection() throws {
        XCTAssertTrue("#42".isImmediate)
        XCTAssertTrue("0x100".isImmediate)
        XCTAssertFalse("X0".isImmediate)
    }
    
    func testHexValueExtraction() throws {
        XCTAssertEqual("0x100".hexValue, 0x100)
        XCTAssertEqual("#42".hexValue, 0x42)
        XCTAssertNil("invalid".hexValue)
    }
    
    func testStringPadding() throws {
        let padded = "test".padded(toWidth: 10)
        
        XCTAssertEqual(padded.count, 10)
        XCTAssertTrue(padded.hasPrefix("test"))
    }
}

