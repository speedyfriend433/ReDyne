#import "BinaryParserService.h"
#import "MachOHeader.h"
#import "SymbolTable.h"
#import "StringExtractor.h"

static NSString * const ReDyneBinaryParserErrorDomain = @"com.jian.ReDyne.BinaryParser";

typedef NS_ENUM(NSInteger, ReDyneBinaryParserError) {
    ReDyneBinaryParserErrorInvalidFile = 1001,
    ReDyneBinaryParserErrorInvalidMachO = 1002,
    ReDyneBinaryParserErrorParsingFailed = 1003,
    ReDyneBinaryParserErrorEncrypted = 1004,
    ReDyneBinaryParserErrorTooLarge = 1005
};

@implementation BinaryParserService

#pragma mark - Public Methods

+ (DecompiledOutput *)parseBinaryAtPath:(NSString *)filePath
                         progressBlock:(ParserProgressBlock)progressBlock
                                 error:(NSError **)error {
    
    NSDate *startTime = [NSDate date];
    
    if (progressBlock) {
        progressBlock(@"Opening file...", 0.0);
    }
    
    char error_msg[256] = {0};
    MachOContext *macho_ctx = macho_open([filePath UTF8String], error_msg);
    if (!macho_ctx) {
        if (error) {
            *error = [NSError errorWithDomain:ReDyneBinaryParserErrorDomain
                                         code:ReDyneBinaryParserErrorInvalidFile
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:error_msg]}];
        }
        return nil;
    }
    
    if (progressBlock) {
        progressBlock(@"Parsing header...", 0.1);
    }
    
    if (!macho_parse_header(macho_ctx)) {
        macho_close(macho_ctx);
        if (error) {
            *error = [NSError errorWithDomain:ReDyneBinaryParserErrorDomain
                                         code:ReDyneBinaryParserErrorInvalidMachO
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid Mach-O header"}];
        }
        return nil;
    }
    
    if (progressBlock) {
        progressBlock(@"Parsing load commands...", 0.2);
    }
    
    if (!macho_parse_load_commands(macho_ctx)) {
        macho_close(macho_ctx);
        if (error) {
            *error = [NSError errorWithDomain:ReDyneBinaryParserErrorDomain
                                         code:ReDyneBinaryParserErrorParsingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse load commands"}];
        }
        return nil;
    }
    
    if (macho_ctx->is_encrypted) {
        macho_close(macho_ctx);
        if (error) {
            *error = [NSError errorWithDomain:ReDyneBinaryParserErrorDomain
                                         code:ReDyneBinaryParserErrorEncrypted
                                     userInfo:@{NSLocalizedDescriptionKey: @"Binary is encrypted and cannot be decompiled"}];
        }
        return nil;
    }
    
    if (progressBlock) {
        progressBlock(@"Extracting segments...", 0.3);
    }
    
    macho_extract_segments(macho_ctx);
    macho_extract_sections(macho_ctx);
    
    DecompiledOutput *output = [[DecompiledOutput alloc] init];
    output.filePath = filePath;
    output.fileName = [filePath lastPathComponent];
    output.fileSize = macho_ctx->file_size;
    output.header = [self createHeaderModelFromContext:macho_ctx];
    
    NSMutableArray *segments = [NSMutableArray array];
    for (uint32_t i = 0; i < macho_ctx->segment_count; i++) {
        SegmentModel *seg = [self createSegmentModelFromInfo:&macho_ctx->segments[i]];
        [segments addObject:seg];
    }
    output.segments = segments;
    
    NSMutableArray *sections = [NSMutableArray array];
    for (uint32_t i = 0; i < macho_ctx->section_count; i++) {
        SectionModel *sect = [self createSectionModelFromInfo:&macho_ctx->sections[i]];
        [sections addObject:sect];
    }
    output.sections = sections;
    
    if (progressBlock) {
        progressBlock(@"Parsing symbol table...", 0.5);
    }
    
    SymbolTableContext *sym_ctx = symbol_table_create(macho_ctx);
    if (sym_ctx) {
        symbol_table_parse(sym_ctx);
        symbol_table_categorize(sym_ctx);
        symbol_table_extract_functions(sym_ctx);
        
        NSMutableArray *symbols = [NSMutableArray array];
        for (uint32_t i = 0; i < sym_ctx->symbol_count; i++) {
            SymbolModel *sym = [self createSymbolModelFromInfo:&sym_ctx->symbols[i]];
            [symbols addObject:sym];
        }
        output.symbols = symbols;
        
        output.totalSymbols = sym_ctx->symbol_count;
        output.definedSymbols = sym_ctx->defined_count;
        output.undefinedSymbols = sym_ctx->undefined_count;
        output.totalFunctions = sym_ctx->function_count;
        
        symbol_table_free(sym_ctx);
    }
    
    if (progressBlock) {
        progressBlock(@"Extracting strings...", 0.7);
    }
    
    StringContext *str_ctx = string_context_create(1024);
    if (str_ctx) {
        for (uint32_t i = 0; i < macho_ctx->section_count; i++) {
            SectionInfo *sect = &macho_ctx->sections[i];
            if (strcmp(sect->sectname, "__cstring") == 0) {
                string_extract_cstrings(str_ctx, macho_ctx->file, sect->offset, sect->size, sect->addr);
            }
        }
        
        for (uint32_t i = 0; i < macho_ctx->segment_count; i++) {
            SegmentInfo *seg = &macho_ctx->segments[i];
            if ((seg->initprot & 0x01) && seg->filesize > 0) {
                uint8_t *data = malloc(seg->filesize);
                if (data) {
                    fseek(macho_ctx->file, seg->fileoff, SEEK_SET);
                    if (fread(data, 1, seg->filesize, macho_ctx->file) == seg->filesize) {
                        string_extract_from_data(str_ctx, data, seg->filesize, seg->vmaddr, seg->segname, 4);
                    }
                    free(data);
                }
            }
        }
        
        string_context_sort(str_ctx);
        
        NSMutableArray *strings = [NSMutableArray array];
        for (uint32_t i = 0; i < str_ctx->count; i++) {
            StringModel *str = [self createStringModelFromInfo:&str_ctx->strings[i]];
            [strings addObject:str];
        }
        output.strings = strings;
        output.totalStrings = str_ctx->count;
        
        string_context_free(str_ctx);
    }
    
    if (progressBlock) {
        progressBlock(@"Complete!", 1.0);
    }
    
    output.processingTime = [[NSDate date] timeIntervalSinceDate:startTime];
    
    macho_close(macho_ctx);
    
    return output;
}

+ (BOOL)isValidMachOAtPath:(NSString *)filePath {
    MachOContext *ctx = macho_open([filePath UTF8String], NULL);
    if (!ctx) return NO;
    
    BOOL valid = macho_parse_header(ctx);
    macho_close(ctx);
    
    return valid;
}

+ (NSDictionary *)quickInfoForFileAtPath:(NSString *)filePath {
    MachOContext *ctx = macho_open([filePath UTF8String], NULL);
    if (!ctx) return nil;
    
    if (!macho_parse_header(ctx)) {
        macho_close(ctx);
        return nil;
    }
    
    NSDictionary *info = @{
        @"cpuType": [NSString stringWithUTF8String:macho_cpu_type_string(ctx->header.cputype)],
        @"fileType": [NSString stringWithUTF8String:macho_filetype_string(ctx->header.filetype)],
        @"is64Bit": @(ctx->header.is_64bit),
        @"fileSize": @(ctx->file_size),
        @"isEncrypted": @(ctx->is_encrypted)
    };
    
    macho_close(ctx);
    return info;
}

+ (NSArray<SymbolModel *> *)extractSymbolsFromPath:(NSString *)filePath error:(NSError **)error {
    MachOContext *macho_ctx = macho_open([filePath UTF8String], NULL);
    if (!macho_ctx) {
        if (error) {
            *error = [NSError errorWithDomain:ReDyneBinaryParserErrorDomain
                                         code:ReDyneBinaryParserErrorInvalidFile
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to open file"}];
        }
        return nil;
    }
    
    if (!macho_parse_header(macho_ctx) || !macho_parse_load_commands(macho_ctx)) {
        macho_close(macho_ctx);
        if (error) {
            *error = [NSError errorWithDomain:ReDyneBinaryParserErrorDomain
                                         code:ReDyneBinaryParserErrorParsingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse Mach-O"}];
        }
        return nil;
    }
    
    SymbolTableContext *sym_ctx = symbol_table_create(macho_ctx);
    if (!sym_ctx || !symbol_table_parse(sym_ctx)) {
        if (sym_ctx) symbol_table_free(sym_ctx);
        macho_close(macho_ctx);
        return @[];
    }
    
    NSMutableArray *symbols = [NSMutableArray array];
    for (uint32_t i = 0; i < sym_ctx->symbol_count; i++) {
        SymbolModel *sym = [self createSymbolModelFromInfo:&sym_ctx->symbols[i]];
        [symbols addObject:sym];
    }
    
    symbol_table_free(sym_ctx);
    macho_close(macho_ctx);
    
    return symbols;
}

#pragma mark - Private Helper Methods

+ (MachOHeaderModel *)createHeaderModelFromContext:(MachOContext *)ctx {
    MachOHeaderModel *model = [[MachOHeaderModel alloc] init];
    
    const char *cpu_type = macho_cpu_type_string(ctx->header.cputype);
    const char *cpu_subtype = macho_cpu_subtype_string(ctx->header.cputype, ctx->header.cpusubtype);
    
    if (cpu_subtype && strlen(cpu_subtype) > 0) {
        model.cpuType = [NSString stringWithFormat:@"%s (%s)", cpu_type, cpu_subtype];
    } else {
        model.cpuType = [NSString stringWithUTF8String:cpu_type];
    }
    
    model.fileType = [NSString stringWithUTF8String:macho_filetype_string(ctx->header.filetype)];
    model.ncmds = ctx->header.ncmds;
    model.flags = ctx->header.flags;
    model.is64Bit = ctx->header.is_64bit;
    model.isEncrypted = ctx->is_encrypted;
    
    if (ctx->has_uuid) {
        NSMutableString *uuidStr = [NSMutableString string];
        for (int i = 0; i < 16; i++) {
            [uuidStr appendFormat:@"%02X", ctx->uuid[i]];
            if (i == 3 || i == 5 || i == 7 || i == 9) [uuidStr appendString:@"-"];
        }
        model.uuid = uuidStr;
    }
    
    return model;
}

+ (SegmentModel *)createSegmentModelFromInfo:(SegmentInfo *)info {
    SegmentModel *model = [[SegmentModel alloc] init];
    
    model.name = [NSString stringWithUTF8String:info->segname];
    model.vmAddress = info->vmaddr;
    model.vmSize = info->vmsize;
    model.fileOffset = info->fileoff;
    model.fileSize = info->filesize;
    
    // Format protection string
    NSMutableString *prot = [NSMutableString string];
    if (info->initprot & 0x01) [prot appendString:@"r"];
    if (info->initprot & 0x02) [prot appendString:@"w"];
    if (info->initprot & 0x04) [prot appendString:@"x"];
    model.protection = prot.length > 0 ? prot : @"---";
    
    return model;
}

+ (SectionModel *)createSectionModelFromInfo:(SectionInfo *)info {
    SectionModel *model = [[SectionModel alloc] init];
    
    model.sectionName = [NSString stringWithUTF8String:info->sectname];
    model.segmentName = [NSString stringWithUTF8String:info->segname];
    model.address = info->addr;
    model.size = info->size;
    model.offset = info->offset;
    
    return model;
}

+ (SymbolModel *)createSymbolModelFromInfo:(SymbolInfo *)info {
    SymbolModel *model = [[SymbolModel alloc] init];
    
    model.name = info->name ? [NSString stringWithUTF8String:info->name] : @"";
    model.address = info->address;
    model.size = info->size;
    model.type = [NSString stringWithUTF8String:symbol_type_string(info->type)];
    model.scope = [NSString stringWithUTF8String:symbol_scope_string(info->scope)];
    model.section = info->section;
    model.isDefined = info->is_defined;
    model.isExternal = info->is_external;
    model.isWeak = info->is_weak;
    model.isFunction = (info->type == SYMBOL_TYPE_SECTION && info->address > 0);
    
    return model;
}

+ (StringModel *)createStringModelFromInfo:(StringInfo *)info {
    StringModel *model = [[StringModel alloc] init];
    
    model.content = info->content ? [NSString stringWithUTF8String:info->content] : @"";
    model.address = info->address;
    model.offset = info->offset;
    model.length = info->length;
    model.section = [NSString stringWithUTF8String:info->section];
    model.isCString = info->is_cstring;
    model.isUnicode = info->is_unicode;
    
    return model;
}

@end

