#import <Foundation/Foundation.h>
#import "DecompiledOutput.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^ParserProgressBlock)(NSString *status, float progress);

@interface BinaryParserService : NSObject

+ (nullable DecompiledOutput *)parseBinaryAtPath:(NSString *)filePath
                                  progressBlock:(nullable ParserProgressBlock)progressBlock
                                          error:(NSError **)error;

+ (BOOL)isValidMachOAtPath:(NSString *)filePath;

+ (nullable NSDictionary *)quickInfoForFileAtPath:(NSString *)filePath;

+ (nullable NSArray<SymbolModel *> *)extractSymbolsFromPath:(NSString *)filePath
                                                      error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

