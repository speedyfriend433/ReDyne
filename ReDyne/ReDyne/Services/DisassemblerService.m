#import "DisassemblerService.h"
#import "MachOHeader.h"
#import "DisassemblyEngine.h"
#import "ControlFlowGraph.h"

static NSString * const ReDyneDisassemblerErrorDomain = @"com.jian.ReDyne.Disassembler";

typedef NS_ENUM(NSInteger, ReDyneDisassemblerError) {
    ReDyneDisassemblerErrorInvalidFile = 2001,
    ReDyneDisassemblerErrorNoCodeSection = 2002,
    ReDyneDisassemblerErrorDisassemblyFailed = 2003
};

@implementation DisassemblerService

#pragma mark - Public Methods

+ (NSArray<InstructionModel *> *)disassembleFileAtPath:(NSString *)filePath
                                         progressBlock:(DisassemblyProgressBlock)progressBlock
                                                 error:(NSError **)error {
    
    if (progressBlock) {
        progressBlock(@"Opening binary...", 0.0);
    }
    
    MachOContext *macho_ctx = macho_open([filePath UTF8String], NULL);
    if (!macho_ctx || !macho_parse_header(macho_ctx) || !macho_parse_load_commands(macho_ctx)) {
        if (macho_ctx) macho_close(macho_ctx);
        if (error) {
            *error = [NSError errorWithDomain:ReDyneDisassemblerErrorDomain
                                         code:ReDyneDisassemblerErrorInvalidFile
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid Mach-O file"}];
        }
        return nil;
    }
    
    macho_extract_segments(macho_ctx);
    macho_extract_sections(macho_ctx);
    
    if (progressBlock) {
        progressBlock(@"Loading code section...", 0.2);
    }
    
    DisassemblyContext *disasm_ctx = disasm_create(macho_ctx);
    if (!disasm_ctx) {
        macho_close(macho_ctx);
        if (error) {
            *error = [NSError errorWithDomain:ReDyneDisassemblerErrorDomain
                                         code:ReDyneDisassemblerErrorDisassemblyFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create disassembly context"}];
        }
        return nil;
    }
    
    if (!disasm_load_section(disasm_ctx, "__text")) {
        NSLog(@"No __text section found. Available sections:");
        for (uint32_t i = 0; i < macho_ctx->section_count; i++) {
            NSLog(@"   • %s (segment: %s, size: %llu bytes)",
                  macho_ctx->sections[i].sectname,
                  macho_ctx->sections[i].segname,
                  macho_ctx->sections[i].size);
        }
        
        disasm_free(disasm_ctx);
        macho_close(macho_ctx);
        if (error) {
            *error = [NSError errorWithDomain:ReDyneDisassemblerErrorDomain
                                         code:ReDyneDisassemblerErrorNoCodeSection
                                     userInfo:@{NSLocalizedDescriptionKey: @"No __text section found"}];
        }
        return nil;
    }
    
    if (progressBlock) {
        progressBlock(@"Disassembling instructions...", 0.4);
    }
    
    uint32_t count = disasm_all(disasm_ctx);
    NSLog(@"Disassembled %u instructions from __text section (size: %llu bytes)",
          count, disasm_ctx->code_size);
    
    if (count == 0) {
        NSLog(@"Warning: No instructions disassembled (empty or data-only __text)");
        disasm_free(disasm_ctx);
        macho_close(macho_ctx);
        return @[];
    }
    
    if (progressBlock) {
        progressBlock(@"Building instruction models...", 0.8);
    }
    
    NSMutableArray<InstructionModel *> *instructions = [NSMutableArray arrayWithCapacity:count];
    for (uint32_t i = 0; i < count; i++) {
        InstructionModel *model = [self createInstructionModelFromDisasm:&disasm_ctx->instructions[i]];
        [instructions addObject:model];
    }
    
    if (progressBlock) {
        progressBlock(@"Complete!", 1.0);
    }
    
    disasm_free(disasm_ctx);
    macho_close(macho_ctx);
    
    return instructions;
}

+ (NSArray<InstructionModel *> *)disassembleFileAtPath:(NSString *)filePath
                                           startAddress:(uint64_t)startAddress
                                             endAddress:(uint64_t)endAddress
                                                  error:(NSError **)error {
    
    MachOContext *macho_ctx = macho_open([filePath UTF8String], NULL);
    if (!macho_ctx || !macho_parse_header(macho_ctx) || !macho_parse_load_commands(macho_ctx)) {
        if (macho_ctx) macho_close(macho_ctx);
        if (error) {
            *error = [NSError errorWithDomain:ReDyneDisassemblerErrorDomain
                                         code:ReDyneDisassemblerErrorInvalidFile
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid Mach-O file"}];
        }
        return nil;
    }
    
    macho_extract_segments(macho_ctx);
    macho_extract_sections(macho_ctx);
    
    DisassemblyContext *disasm_ctx = disasm_create(macho_ctx);
    if (!disasm_ctx || !disasm_load_section(disasm_ctx, "__text")) {
        if (disasm_ctx) disasm_free(disasm_ctx);
        macho_close(macho_ctx);
        if (error) {
            *error = [NSError errorWithDomain:ReDyneDisassemblerErrorDomain
                                         code:ReDyneDisassemblerErrorNoCodeSection
                                     userInfo:@{NSLocalizedDescriptionKey: @"No __text section found"}];
        }
        return nil;
    }
    
    uint32_t count = disasm_range(disasm_ctx, startAddress, endAddress);
    
    if (count == 0) {
        NSLog(@"Warning: No instructions in range 0x%llx-0x%llx", startAddress, endAddress);
        disasm_free(disasm_ctx);
        macho_close(macho_ctx);
        return @[];
    }
    
    NSLog(@"Disassembled %u instructions in range 0x%llx-0x%llx", count, startAddress, endAddress);
    
    NSMutableArray<InstructionModel *> *instructions = [NSMutableArray arrayWithCapacity:count];
    for (uint32_t i = 0; i < count; i++) {
        InstructionModel *model = [self createInstructionModelFromDisasm:&disasm_ctx->instructions[i]];
        [instructions addObject:model];
    }
    
    disasm_free(disasm_ctx);
    macho_close(macho_ctx);
    
    return instructions;
}

+ (NSArray<FunctionModel *> *)extractFunctionsFromInstructions:(NSArray<InstructionModel *> *)instructions
                                                        symbols:(NSArray<SymbolModel *> *)symbols {
    
    NSMutableArray<FunctionModel *> *functions = [NSMutableArray array];
    
    NSMutableDictionary<NSNumber *, SymbolModel *> *symbolsByAddress = [NSMutableDictionary dictionary];
    for (SymbolModel *sym in symbols) {
        if (sym.isFunction) {
            symbolsByAddress[@(sym.address)] = sym;
        }
    }
    
    FunctionModel *currentFunction = nil;
    NSMutableArray<InstructionModel *> *currentInstructions = nil;
    
    for (InstructionModel *inst in instructions) {
        if (inst.isFunctionStart || symbolsByAddress[@(inst.address)]) {
            if (currentFunction) {
                currentFunction.instructions = [currentInstructions copy];
                currentFunction.instructionCount = (uint32_t)currentInstructions.count;
                [functions addObject:currentFunction];
            }
            
            currentFunction = [[FunctionModel alloc] init];
            currentFunction.startAddress = inst.address;
            
            SymbolModel *sym = symbolsByAddress[@(inst.address)];
            currentFunction.name = sym ? sym.name : [NSString stringWithFormat:@"sub_%llx", inst.address];
            
            currentInstructions = [NSMutableArray array];
        }
        
        if (currentFunction) {
            [currentInstructions addObject:inst];
            currentFunction.endAddress = inst.address + 4;
            
            if (inst.isFunctionEnd) {
                currentFunction.instructions = [currentInstructions copy];
                currentFunction.instructionCount = (uint32_t)currentInstructions.count;
                [functions addObject:currentFunction];
                
                currentFunction = nil;
                currentInstructions = nil;
            }
        }
    }
    
    if (currentFunction && currentInstructions.count > 0) {
        currentFunction.endAddress = [currentInstructions lastObject].address + 4;
        currentFunction.instructions = [currentInstructions copy];
        currentFunction.instructionCount = (uint32_t)currentInstructions.count;
        [functions addObject:currentFunction];
    }
    
    return functions;
}

+ (NSString *)generatePseudocodeForFunction:(FunctionModel *)function {
    if (!function || !function.instructions) return nil;
    
    NSMutableString *pseudo = [NSMutableString string];
    
    [pseudo appendFormat:@"// Function at 0x%llx\n", function.startAddress];
    [pseudo appendFormat:@"int %@() {\n", function.name];
    
    NSInteger indent = 1;
    
    for (InstructionModel *inst in function.instructions) {
        NSString *indentStr = [@"" stringByPaddingToLength:indent * 4 withString:@" " startingAtIndex:0];
        NSString *mnem = inst.mnemonic;
        
        if ([mnem hasPrefix:@"MOV"]) {
            [pseudo appendFormat:@"%@%@ = %@;\n", indentStr,
             [self extractFirstOperand:inst.operands],
             [self extractSecondOperand:inst.operands]];
        }
        
        else if ([mnem hasPrefix:@"ADD"]) {
            [pseudo appendFormat:@"%@%@ += %@;\n", indentStr,
             [self extractFirstOperand:inst.operands],
             [self extractSecondOperand:inst.operands]];
        }
        else if ([mnem hasPrefix:@"SUB"]) {
            [pseudo appendFormat:@"%@%@ -= %@;\n", indentStr,
             [self extractFirstOperand:inst.operands],
             [self extractSecondOperand:inst.operands]];
        }
        else if ([mnem hasPrefix:@"MUL"] || [mnem hasPrefix:@"MADD"]) {
            [pseudo appendFormat:@"%@%@ *= %@;\n", indentStr,
             [self extractFirstOperand:inst.operands],
             [self extractSecondOperand:inst.operands]];
        }
        else if ([mnem hasPrefix:@"SDIV"] || [mnem hasPrefix:@"UDIV"]) {
            [pseudo appendFormat:@"%@%@ /= %@;\n", indentStr,
             [self extractFirstOperand:inst.operands],
             [self extractSecondOperand:inst.operands]];
        }

        else if ([mnem hasPrefix:@"AND"]) {
            [pseudo appendFormat:@"%@%@ &= %@;\n", indentStr,
             [self extractFirstOperand:inst.operands],
             [self extractSecondOperand:inst.operands]];
        }
        else if ([mnem hasPrefix:@"ORR"] || [mnem hasPrefix:@"OR"]) {
            [pseudo appendFormat:@"%@%@ |= %@;\n", indentStr,
             [self extractFirstOperand:inst.operands],
             [self extractSecondOperand:inst.operands]];
        }
        else if ([mnem hasPrefix:@"EOR"] || [mnem hasPrefix:@"XOR"]) {
            [pseudo appendFormat:@"%@%@ ^= %@;\n", indentStr,
             [self extractFirstOperand:inst.operands],
             [self extractSecondOperand:inst.operands]];
        }
        else if ([mnem hasPrefix:@"LSL"] || [mnem hasPrefix:@"SHL"]) {
            [pseudo appendFormat:@"%@%@ <<= %@;\n", indentStr,
             [self extractFirstOperand:inst.operands],
             [self extractSecondOperand:inst.operands]];
        }
        else if ([mnem hasPrefix:@"LSR"] || [mnem hasPrefix:@"ASR"] || [mnem hasPrefix:@"SHR"]) {
            [pseudo appendFormat:@"%@%@ >>= %@;\n", indentStr,
             [self extractFirstOperand:inst.operands],
             [self extractSecondOperand:inst.operands]];
        }

        else if ([mnem hasPrefix:@"LDR"]) {
            [pseudo appendFormat:@"%@%@ = *(%@);\n", indentStr,
             [self extractFirstOperand:inst.operands],
             [self extractMemoryOperand:inst.operands]];
        }
        else if ([mnem hasPrefix:@"STR"]) {
            [pseudo appendFormat:@"%@*(%@) = %@;\n", indentStr,
             [self extractMemoryOperand:inst.operands],
             [self extractFirstOperand:inst.operands]];
        }
        else if ([mnem hasPrefix:@"ADRP"]) {
            [pseudo appendFormat:@"%@%@ = &page_%@;\n", indentStr,
             [self extractFirstOperand:inst.operands],
             [self extractSecondOperand:inst.operands]];
        }
        else if ([mnem hasPrefix:@"ADR"]) {
            [pseudo appendFormat:@"%@%@ = &%@;\n", indentStr,
             [self extractFirstOperand:inst.operands],
             [self extractSecondOperand:inst.operands]];
        }

        else if ([mnem hasPrefix:@"STP"]) {
            [pseudo appendFormat:@"%@push(%@, %@);\n", indentStr,
             [self extractFirstOperand:inst.operands],
             [self extractSecondOperand:inst.operands]];
        }
        else if ([mnem hasPrefix:@"LDP"]) {
            [pseudo appendFormat:@"%@pop(%@, %@);\n", indentStr,
             [self extractFirstOperand:inst.operands],
             [self extractSecondOperand:inst.operands]];
        }

        else if ([mnem hasPrefix:@"CMP"]) {
            [pseudo appendFormat:@"%@compare(%@, %@);\n", indentStr,
             [self extractFirstOperand:inst.operands],
             [self extractSecondOperand:inst.operands]];
        }
        else if ([mnem hasPrefix:@"TST"]) {
            [pseudo appendFormat:@"%@test(%@ & %@);\n", indentStr,
             [self extractFirstOperand:inst.operands],
             [self extractSecondOperand:inst.operands]];
        }

        else if ([mnem hasPrefix:@"B.EQ"] && inst.hasBranchTarget) {
            [pseudo appendFormat:@"%@if (equal) goto loc_%llx;\n", indentStr, inst.branchTarget];
        }
        else if ([mnem hasPrefix:@"B.NE"] && inst.hasBranchTarget) {
            [pseudo appendFormat:@"%@if (not_equal) goto loc_%llx;\n", indentStr, inst.branchTarget];
        }
        else if ([mnem hasPrefix:@"B.LT"] && inst.hasBranchTarget) {
            [pseudo appendFormat:@"%@if (less_than) goto loc_%llx;\n", indentStr, inst.branchTarget];
        }
        else if ([mnem hasPrefix:@"B.LE"] && inst.hasBranchTarget) {
            [pseudo appendFormat:@"%@if (less_equal) goto loc_%llx;\n", indentStr, inst.branchTarget];
        }
        else if ([mnem hasPrefix:@"B.GT"] && inst.hasBranchTarget) {
            [pseudo appendFormat:@"%@if (greater_than) goto loc_%llx;\n", indentStr, inst.branchTarget];
        }
        else if ([mnem hasPrefix:@"B.GE"] && inst.hasBranchTarget) {
            [pseudo appendFormat:@"%@if (greater_equal) goto loc_%llx;\n", indentStr, inst.branchTarget];
        }
        else if ([mnem hasPrefix:@"B."] && inst.hasBranchTarget) {
            [pseudo appendFormat:@"%@if (condition) goto loc_%llx;\n", indentStr, inst.branchTarget];
        }

        else if ([mnem isEqualToString:@"B"] && inst.hasBranchTarget) {
            [pseudo appendFormat:@"%@goto loc_%llx;\n", indentStr, inst.branchTarget];
        }

        else if ([mnem isEqualToString:@"BL"] && inst.hasBranchTarget) {
            [pseudo appendFormat:@"%@call_0x%llx();\n", indentStr, inst.branchTarget];
        }
        else if ([mnem isEqualToString:@"BLR"]) {
            [pseudo appendFormat:@"%@call_indirect(%@);\n", indentStr, [self extractFirstOperand:inst.operands]];
        }

        else if ([mnem isEqualToString:@"RET"]) {
            [pseudo appendFormat:@"%@return;\n", indentStr];
        }

        else if ([mnem isEqualToString:@"NOP"]) {
            [pseudo appendFormat:@"%@/* nop */\n", indentStr];
        }

        else if ([mnem hasPrefix:@"FADD"] || [mnem hasPrefix:@"FSUB"] || 
                 [mnem hasPrefix:@"FMUL"] || [mnem hasPrefix:@"FDIV"]) {
            NSString *op = @"?";
            if ([mnem hasPrefix:@"FADD"]) op = @"+";
            else if ([mnem hasPrefix:@"FSUB"]) op = @"-";
            else if ([mnem hasPrefix:@"FMUL"]) op = @"*";
            else if ([mnem hasPrefix:@"FDIV"]) op = @"/";
            [pseudo appendFormat:@"%@%@ = %@ %@ %@;  // float\n", indentStr,
             [self extractFirstOperand:inst.operands], [self extractFirstOperand:inst.operands],
             op, [self extractSecondOperand:inst.operands]];
        }
        
        else {
            [pseudo appendFormat:@"%@// %@\n", indentStr, inst.fullDisassembly];
        }
    }
    
    [pseudo appendString:@"}\n"];
    
    return pseudo;
}

+ (NSString *)buildCFGForFunction:(FunctionModel *)function {

    NSMutableString *dot = [NSMutableString string];
    [dot appendString:@"digraph CFG {\n"];
    [dot appendFormat:@"  label=\"%@ CFG\";\n", function.name];
    [dot appendString:@"  node [shape=box, style=filled, fillcolor=lightblue];\n"];
    [dot appendString:@"  rankdir=TB;\n\n"];
    
    NSMutableArray<InstructionModel *> *instructions = [function.instructions mutableCopy];
    if (instructions.count == 0) {
        [dot appendString:@"  empty [label=\"Empty function\"];\n"];
        [dot appendString:@"}\n"];
        return dot;
    }
    
    NSMutableSet<NSNumber *> *blockStarts = [NSMutableSet set];
    [blockStarts addObject:@(0)];
    
    for (NSInteger i = 0; i < instructions.count; i++) {
        InstructionModel *inst = instructions[i];
        
        if ([inst.mnemonic hasPrefix:@"B"] && ![inst.mnemonic isEqualToString:@"BRK"]) {
            if (i + 1 < instructions.count) {
                [blockStarts addObject:@(i + 1)];
            }
            
            if (inst.hasBranchTarget) {
                for (NSInteger j = 0; j < instructions.count; j++) {
                    if (instructions[j].address == inst.branchTarget) {
                        [blockStarts addObject:@(j)];
                        break;
                    }
                }
            }
        }
    }
    
    NSArray *sortedStarts = [[blockStarts allObjects] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *blocks = [NSMutableArray array];
    
    for (NSInteger i = 0; i < sortedStarts.count; i++) {
        NSInteger startIdx = [sortedStarts[i] integerValue];
        NSInteger endIdx = (i + 1 < sortedStarts.count) 
                           ? [sortedStarts[i + 1] integerValue] - 1
                           : instructions.count - 1;
        
        NSRange range = NSMakeRange(startIdx, endIdx - startIdx + 1);
        NSArray *blockInsts = [instructions subarrayWithRange:range];
        [blocks addObject:blockInsts];
    }
    
    for (NSInteger i = 0; i < blocks.count; i++) {
        NSArray<InstructionModel *> *block = blocks[i];
        InstructionModel *first = block.firstObject;
        InstructionModel *last = block.lastObject;
        
        [dot appendFormat:@"  bb_%ld [label=\"BB %ld (0x%llx)\\n", (long)i, (long)i, first.address];
        
        NSInteger instCount = MIN(5, block.count);
        for (NSInteger j = 0; j < instCount; j++) {
            InstructionModel *inst = block[j];
            [dot appendFormat:@"%@ %@\\l", inst.mnemonic, inst.operands];
        }
        if (block.count > 5) {
            [dot appendFormat:@"... (%ld more)\\l", (long)(block.count - 5)];
        }
        [dot appendString:@"\"];\n"];
    }
    
    [dot appendString:@"\n"];
    
    for (NSInteger i = 0; i < blocks.count; i++) {
        NSArray<InstructionModel *> *block = blocks[i];
        InstructionModel *lastInst = block.lastObject;
        
        NSString *mnemonic = lastInst.mnemonic;
        
        if ([mnemonic isEqualToString:@"RET"]) {
            
        } else if ([mnemonic isEqualToString:@"B"] && lastInst.hasBranchTarget) {
            for (NSInteger j = 0; j < blocks.count; j++) {
                InstructionModel *targetFirst = [blocks[j] firstObject];
                if (targetFirst.address == lastInst.branchTarget) {
                    [dot appendFormat:@"  bb_%ld -> bb_%ld;\n", (long)i, (long)j];
                    break;
                }
            }
        } else if ([mnemonic hasPrefix:@"B."] && lastInst.hasBranchTarget) {
            for (NSInteger j = 0; j < blocks.count; j++) {
                InstructionModel *targetFirst = [blocks[j] firstObject];
                if (targetFirst.address == lastInst.branchTarget) {
                    [dot appendFormat:@"  bb_%ld -> bb_%ld [label=\"true\", color=green];\n", (long)i, (long)j];
                    break;
                }
            }
            
            if (i + 1 < blocks.count) {
                [dot appendFormat:@"  bb_%ld -> bb_%ld [label=\"false\", color=red];\n", (long)i, (long)(i + 1)];
            }
        } else {

            if (i + 1 < blocks.count) {
                [dot appendFormat:@"  bb_%ld -> bb_%ld;\n", (long)i, (long)(i + 1)];
            }
        }
    }
    
    [dot appendString:@"}\n"];
    
    return dot;
}

#pragma mark - Private Helpers

+ (InstructionModel *)createInstructionModelFromDisasm:(DisassembledInstruction *)disasm {
    InstructionModel *model = [[InstructionModel alloc] init];
    
    model.address = disasm->address;
    model.hexBytes = [NSString stringWithFormat:@"%08X", disasm->raw_bytes];
    model.mnemonic = [NSString stringWithUTF8String:disasm->mnemonic];
    model.operands = [NSString stringWithUTF8String:disasm->operands];
    model.fullDisassembly = [NSString stringWithUTF8String:disasm->full_disasm];
    
    if (disasm->comment[0] != '\0') {
        model.comment = [NSString stringWithUTF8String:disasm->comment];
    }
    
    model.category = [NSString stringWithUTF8String:disasm_category_string(disasm->category)];
    
    if (disasm->branch_type != BRANCH_NONE) {
        model.branchType = [NSString stringWithUTF8String:disasm_branch_type_string(disasm->branch_type)];
    }
    
    model.hasBranch = disasm->has_branch;
    model.hasBranchTarget = disasm->has_branch_target;
    model.branchTarget = disasm->branch_target;
    model.isFunctionStart = disasm->is_function_start;
    model.isFunctionEnd = disasm->is_function_end;
    
    return model;
}

+ (NSString *)extractFirstOperand:(NSString *)operands {
    NSArray *parts = [operands componentsSeparatedByString:@","];
    if (parts.count > 0) {
        return [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    return @"";
}

+ (NSString *)extractSecondOperand:(NSString *)operands {
    NSArray *parts = [operands componentsSeparatedByString:@","];
    if (parts.count > 1) {
        return [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    return @"";
}

+ (NSString *)extractMemoryOperand:(NSString *)operands {

    NSRange start = [operands rangeOfString:@"["];
    NSRange end = [operands rangeOfString:@"]"];
    if (start.location != NSNotFound && end.location != NSNotFound) {
        NSRange range = NSMakeRange(start.location + 1, end.location - start.location - 1);
        return [operands substringWithRange:range];
    }
    return operands;
}

@end

