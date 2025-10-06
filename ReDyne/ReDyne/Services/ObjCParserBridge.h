#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ObjCParserBridge : NSObject

+ (nullable id)parseObjCRuntimeAtPath:(NSString *)filePath;

+ (nullable id)parseImportsExportsAtPath:(NSString *)filePath;

+ (nullable id)parseCodeSignatureAtPath:(NSString *)filePath;

@end

NS_ASSUME_NONNULL_END
