#import <Foundation/Foundation.h>
#import "DecompiledOutput.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^DisassemblyProgressBlock)(NSString *status, float progress);

@interface DisassemblerService : NSObject

+ (nullable NSArray<InstructionModel *> *)disassembleFileAtPath:(NSString *)filePath
                                                  progressBlock:(nullable DisassemblyProgressBlock)progressBlock
                                                          error:(NSError **)error;

+ (nullable NSArray<InstructionModel *> *)disassembleFileAtPath:(NSString *)filePath
                                                    startAddress:(uint64_t)startAddress
                                                      endAddress:(uint64_t)endAddress
                                                           error:(NSError **)error;

+ (NSArray<FunctionModel *> *)extractFunctionsFromInstructions:(NSArray<InstructionModel *> *)instructions
                                                        symbols:(NSArray<SymbolModel *> *)symbols;

+ (nullable NSString *)generatePseudocodeForFunction:(FunctionModel *)function;

+ (nullable NSString *)buildCFGForFunction:(FunctionModel *)function;

@end

NS_ASSUME_NONNULL_END

