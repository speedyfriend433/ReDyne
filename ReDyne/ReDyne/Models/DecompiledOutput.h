#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Header Information

@interface MachOHeaderModel : NSObject

@property (nonatomic, copy) NSString *cpuType;
@property (nonatomic, copy) NSString *fileType;
@property (nonatomic, assign) uint32_t ncmds;
@property (nonatomic, assign) uint32_t flags;
@property (nonatomic, assign) BOOL is64Bit;
@property (nonatomic, copy, nullable) NSString *uuid;
@property (nonatomic, copy, nullable) NSString *minVersion;
@property (nonatomic, copy, nullable) NSString *sdkVersion;
@property (nonatomic, assign) BOOL isEncrypted;

@end

#pragma mark - Segment Information

@interface SegmentModel : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) uint64_t vmAddress;
@property (nonatomic, assign) uint64_t vmSize;
@property (nonatomic, assign) uint64_t fileOffset;
@property (nonatomic, assign) uint64_t fileSize;
@property (nonatomic, copy) NSString *protection;

@end

#pragma mark - Section Information

@interface SectionModel : NSObject

@property (nonatomic, copy) NSString *sectionName;
@property (nonatomic, copy) NSString *segmentName;
@property (nonatomic, assign) uint64_t address;
@property (nonatomic, assign) uint64_t size;
@property (nonatomic, assign) uint32_t offset;

@end

#pragma mark - Symbol Information

@interface SymbolModel : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) uint64_t address;
@property (nonatomic, assign) uint64_t size;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *scope;
@property (nonatomic, assign) uint8_t section;
@property (nonatomic, assign) BOOL isDefined;
@property (nonatomic, assign) BOOL isExternal;
@property (nonatomic, assign) BOOL isWeak;
@property (nonatomic, assign) BOOL isFunction;

@end

#pragma mark - String Information

@interface StringModel : NSObject

@property (nonatomic, copy) NSString *content;
@property (nonatomic, assign) uint64_t address;
@property (nonatomic, assign) uint64_t offset;
@property (nonatomic, assign) uint32_t length;
@property (nonatomic, copy) NSString *section;
@property (nonatomic, assign) BOOL isCString;
@property (nonatomic, assign) BOOL isUnicode;

@end

#pragma mark - Disassembled Instruction

@interface InstructionModel : NSObject

@property (nonatomic, assign) uint64_t address;
@property (nonatomic, copy) NSString *hexBytes;
@property (nonatomic, copy) NSString *mnemonic;
@property (nonatomic, copy) NSString *operands;
@property (nonatomic, copy) NSString *fullDisassembly;
@property (nonatomic, copy, nullable) NSString *comment;
@property (nonatomic, assign) BOOL hasBranch;
@property (nonatomic, copy) NSString *category;
@property (nonatomic, copy, nullable) NSString *branchType;
@property (nonatomic, assign) BOOL hasBranchTarget;
@property (nonatomic, assign) uint64_t branchTarget;
@property (nonatomic, assign) BOOL isFunctionStart;
@property (nonatomic, assign) BOOL isFunctionEnd;

- (NSAttributedString *)attributedString;

@end

#pragma mark - Function Information

@interface FunctionModel : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) uint64_t startAddress;
@property (nonatomic, assign) uint64_t endAddress;
@property (nonatomic, assign) uint32_t instructionCount;
@property (nonatomic, strong, nullable) NSArray<InstructionModel *> *instructions;
@property (nonatomic, copy, nullable) NSString *pseudocode;

@end

#pragma mark - Complete Decompilation Output

@interface DecompiledOutput : NSObject

@property (nonatomic, strong) MachOHeaderModel *header;
@property (nonatomic, strong) NSArray<SegmentModel *> *segments;
@property (nonatomic, strong) NSArray<SectionModel *> *sections;
@property (nonatomic, strong) NSArray<SymbolModel *> *symbols;
@property (nonatomic, strong) NSArray<StringModel *> *strings;
@property (nonatomic, strong) NSArray<InstructionModel *> *instructions;
@property (nonatomic, strong) NSArray<FunctionModel *> *functions;
@property (nonatomic, strong, nullable) id xrefAnalysis;
@property (nonatomic, strong, nullable) id objcAnalysis;
@property (nonatomic, strong, nullable) id importExportAnalysis;
@property (nonatomic, strong, nullable) id codeSigningAnalysis;
@property (nonatomic, strong, nullable) id cfgAnalysis;

@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, assign) uint64_t fileSize;
@property (nonatomic, strong) NSDate *processingDate;
@property (nonatomic, assign) NSTimeInterval processingTime;

@property (nonatomic, assign) NSUInteger totalInstructions;
@property (nonatomic, assign) NSUInteger totalSymbols;
@property (nonatomic, assign) NSUInteger totalStrings;
@property (nonatomic, assign) NSUInteger totalFunctions;
@property (nonatomic, assign) NSUInteger definedSymbols;
@property (nonatomic, assign) NSUInteger undefinedSymbols;
@property (nonatomic, assign) NSUInteger totalXrefs;
@property (nonatomic, assign) NSUInteger totalCalls;
@property (nonatomic, assign) NSUInteger totalObjCClasses;
@property (nonatomic, assign) NSUInteger totalObjCMethods;
@property (nonatomic, assign) NSUInteger totalImports;
@property (nonatomic, assign) NSUInteger totalExports;
@property (nonatomic, assign) NSUInteger totalLinkedLibraries;

- (nullable NSString *)exportAsText;
- (nullable NSString *)exportAsHTML;
- (nullable NSData *)exportAsPDF;

@end

NS_ASSUME_NONNULL_END

