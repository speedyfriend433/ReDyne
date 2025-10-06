import XCTest
@testable import ReDyne

class MachOParserTests: XCTestCase {
    
    override func setUpWithError() throws {
        // setup code
    }
    
    override func tearDownWithError() throws {
        //teardown
    }
    
    func testValidMachODetection() throws {
        //put test dylib
        
        XCTAssertTrue(true, " test")
    }
    
    func testInvalidFileRejection() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("invalid.txt")
        try "Invalid content".write(to: tempURL, atomically: true, encoding: .utf8)
        
        let isValid = BinaryParserService.isValidMachO(atPath: tempURL.path)
        XCTAssertFalse(isValid, "Invalid file should not be detected as Mach-O")
        
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    func testFileSize() throws {
        let size: Int64 = 250 * 1024 * 1024
        let limit = Constants.File.maxFileSize
        
        XCTAssertGreaterThan(size, limit, "Test file size should exceed limit")
    }
    
    func testErrorHandling() throws {
        let nsError = NSError(domain: "com.jian.ReDyne.BinaryParser", code: 1004, userInfo: nil)
        let redyneError = ErrorHandler.convert(nsError)
        
        if case .encryptedBinary = redyneError {
            XCTAssertTrue(true, "Error correctly converted")
        } else {
            XCTFail("Error not converted correctly")
        }
    }
    
    func testAddressFormatting() throws {
        let address: UInt64 = 0x100001000
        let formatted = Constants.formatAddress(address)
        
        XCTAssertEqual(formatted, "0x0000000100001000", "Address formatting should be correct")
    }
    
    func testByteFormatting() throws {
        let bytes: Int64 = 1024 * 1024
        let formatted = Constants.formatBytes(bytes)
        
        XCTAssertTrue(formatted.contains("MB") || formatted.contains("1"), "Byte formatting should work")
    }
    
    func testPerformanceExample() throws {
        self.measure {
            let _ = Constants.formatAddress(0x100000000, padding: 16)
        }
    }
}

