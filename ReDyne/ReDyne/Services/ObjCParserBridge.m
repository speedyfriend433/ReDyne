#import "ObjCParserBridge.h"
#import "MachOHeader.h"
#import "ObjCParser.h"
#import "DyldInfo.h"
#import "ReDyne-Swift.h"

@implementation ObjCParserBridge

+ (nullable id)parseObjCRuntimeAtPath:(NSString *)filePath {
    MachOContext *ctx = macho_open([filePath UTF8String], NULL);
    if (!ctx) {
        return nil;
    }
    
    if (!macho_parse_header(ctx) || !macho_parse_load_commands(ctx)) {
        macho_close(ctx);
        return nil;
    }
    
    id result = [ObjCAnalyzer analyzeWithMachOContext:ctx];
    
    macho_close(ctx);
    
    return result;
}

+ (nullable id)parseImportsExportsAtPath:(NSString *)filePath {
    MachOContext *ctx = macho_open([filePath UTF8String], NULL);
    if (!ctx) {
        return nil;
    }
    
    if (!macho_parse_header(ctx) || !macho_parse_load_commands(ctx)) {
        macho_close(ctx);
        return nil;
    }
    
    id result = [ImportExportAnalyzer analyzeWithMachOContext:ctx];
    
    macho_close(ctx);
    
    return result;
}

+ (nullable id)parseCodeSignatureAtPath:(NSString *)filePath {
    MachOContext *ctx = macho_open([filePath UTF8String], NULL);
    if (!ctx) {
        return nil;
    }
    
    if (!macho_parse_header(ctx) || !macho_parse_load_commands(ctx)) {
        macho_close(ctx);
        return nil;
    }
    
    id result = [CodeSignatureAnalyzer analyzeWithMachOContext:ctx];
    
    macho_close(ctx);
    
    return result;
}

@end
