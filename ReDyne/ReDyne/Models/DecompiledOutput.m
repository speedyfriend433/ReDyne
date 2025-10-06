#import "DecompiledOutput.h"

#pragma mark - MachOHeaderModel

@implementation MachOHeaderModel
@end

#pragma mark - SegmentModel

@implementation SegmentModel
@end

#pragma mark - SectionModel

@implementation SectionModel
@end

#pragma mark - SymbolModel

@implementation SymbolModel
@end

#pragma mark - StringModel

@implementation StringModel
@end

#pragma mark - InstructionModel

@implementation InstructionModel

- (NSAttributedString *)attributedString {
    NSMutableAttributedString *attrString = [[NSMutableAttributedString alloc] init];
    
    NSDictionary *addressAttrs = @{
        NSForegroundColorAttributeName: [UIColor systemGrayColor],
        NSFontAttributeName: [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular]
    };
    NSString *addressStr = [NSString stringWithFormat:@"0x%llx: ", self.address];
    [attrString appendAttributedString:[[NSAttributedString alloc] initWithString:addressStr attributes:addressAttrs]];
    
    NSDictionary *hexAttrs = @{
        NSForegroundColorAttributeName: [UIColor systemGray2Color],
        NSFontAttributeName: [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular]
    };
    NSString *hexStr = [NSString stringWithFormat:@"%-10s ", [self.hexBytes UTF8String]];
    [attrString appendAttributedString:[[NSAttributedString alloc] initWithString:hexStr attributes:hexAttrs]];
    
    UIColor *mnemonicColor = [UIColor systemBlueColor];
    if (self.branchType && ![self.branchType isEqualToString:@"None"]) {
        mnemonicColor = [UIColor systemOrangeColor];
    }
    NSDictionary *mnemonicAttrs = @{
        NSForegroundColorAttributeName: mnemonicColor,
        NSFontAttributeName: [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightBold]
    };
    NSString *mnemonicStr = [NSString stringWithFormat:@"%-8s ", [self.mnemonic UTF8String]];
    [attrString appendAttributedString:[[NSAttributedString alloc] initWithString:mnemonicStr attributes:mnemonicAttrs]];
    
    NSDictionary *operandAttrs = @{
        NSForegroundColorAttributeName: [UIColor labelColor],
        NSFontAttributeName: [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular]
    };
    [attrString appendAttributedString:[[NSAttributedString alloc] initWithString:self.operands attributes:operandAttrs]];
    
    if (self.comment && self.comment.length > 0) {
        NSDictionary *commentAttrs = @{
            NSForegroundColorAttributeName: [UIColor systemGray3Color],
            NSFontAttributeName: [UIFont italicSystemFontOfSize:11]
        };
        NSString *commentStr = [NSString stringWithFormat:@"  ; %@", self.comment];
        [attrString appendAttributedString:[[NSAttributedString alloc] initWithString:commentStr attributes:commentAttrs]];
    }
    
    return attrString;
}

@end

#pragma mark - FunctionModel

@implementation FunctionModel
@end

#pragma mark - DecompiledOutput

@implementation DecompiledOutput

- (instancetype)init {
    self = [super init];
    if (self) {
        _processingDate = [NSDate date];
        _segments = @[];
        _sections = @[];
        _symbols = @[];
        _strings = @[];
        _instructions = @[];
        _functions = @[];
    }
    return self;
}

#pragma mark - Export Methods

- (NSString *)exportAsText {
    NSMutableString *output = [NSMutableString string];
    
    [output appendFormat:@"=== ReDyne Decompilation Report ===\n"];
    [output appendFormat:@"File: %@\n", self.fileName];
    [output appendFormat:@"Size: %llu bytes\n", self.fileSize];
    [output appendFormat:@"Processed: %@\n", self.processingDate];
    [output appendFormat:@"Processing Time: %.2f seconds\n\n", self.processingTime];
    
    [output appendString:@"--- Mach-O Header ---\n"];
    [output appendFormat:@"CPU Type: %@\n", self.header.cpuType];
    [output appendFormat:@"File Type: %@\n", self.header.fileType];
    [output appendFormat:@"Architecture: %@\n", self.header.is64Bit ? @"64-bit" : @"32-bit"];
    [output appendFormat:@"Load Commands: %u\n", self.header.ncmds];
    if (self.header.uuid) {
        [output appendFormat:@"UUID: %@\n", self.header.uuid];
    }
    [output appendFormat:@"Encrypted: %@\n\n", self.header.isEncrypted ? @"Yes" : @"No"];
    
    [output appendFormat:@"--- Segments (%lu) ---\n", (unsigned long)self.segments.count];
    for (SegmentModel *seg in self.segments) {
        [output appendFormat:@"%16s: VM=0x%llx-0x%llx File=0x%llx-0x%llx %@\n",
         [seg.name UTF8String], seg.vmAddress, seg.vmAddress + seg.vmSize,
         seg.fileOffset, seg.fileOffset + seg.fileSize, seg.protection];
    }
    [output appendString:@"\n"];
    
    [output appendFormat:@"--- Symbols (%lu) ---\n", (unsigned long)self.symbols.count];
    [output appendFormat:@"Defined: %lu, Undefined: %lu\n",
     (unsigned long)self.definedSymbols, (unsigned long)self.undefinedSymbols];
    
    NSArray *sortedSymbols = [self.symbols sortedArrayUsingComparator:^NSComparisonResult(SymbolModel *a, SymbolModel *b) {
        return [@(a.address) compare:@(b.address)];
    }];
    
    int count = 0;
    for (SymbolModel *sym in sortedSymbols) {
        if (count++ > 100) {
            [output appendFormat:@"... and %lu more symbols\n", (unsigned long)self.symbols.count - 100];
            break;
        }
        [output appendFormat:@"0x%016llx  %-10s %-10s %@\n",
         sym.address, [sym.type UTF8String], [sym.scope UTF8String], sym.name];
    }
    [output appendString:@"\n"];
    [output appendFormat:@"--- Disassembly (%lu instructions) ---\n", (unsigned long)self.totalInstructions];
    
    count = 0;
    for (InstructionModel *inst in self.instructions) {
        if (count++ > 500) {
            [output appendFormat:@"... and %lu more instructions\n", (unsigned long)self.instructions.count - 500];
            break;
        }
        [output appendFormat:@"%@\n", inst.fullDisassembly];
    }
    [output appendString:@"\n"];
    
    if (self.functions.count > 0) {
        [output appendFormat:@"--- Functions (%lu) ---\n", (unsigned long)self.functions.count];
        for (FunctionModel *func in self.functions) {
            [output appendFormat:@"%@ @ 0x%llx - 0x%llx (%u instructions)\n",
             func.name, func.startAddress, func.endAddress, func.instructionCount];
        }
        [output appendString:@"\n"];
    }
    
    [output appendString:@"=== End of Report ===\n"];
    
    return output;
}

- (NSString *)exportAsHTML {
    NSMutableString *html = [NSMutableString string];
    
    [html appendString:@"<!DOCTYPE html>\n<html>\n<head>\n"];
    [html appendString:@"<meta charset=\"UTF-8\">\n"];
    [html appendFormat:@"<title>%@ - ReDyne Decompilation</title>\n", self.fileName];
    [html appendString:@"<style>\n"];
    [html appendString:@"body { font-family: 'SF Mono', 'Courier New', monospace; background: #1e1e1e; color: #d4d4d4; padding: 20px; }\n"];
    [html appendString:@"h1 { color: #569cd6; }\n"];
    [html appendString:@"h2 { color: #4ec9b0; border-bottom: 1px solid #444; }\n"];
    [html appendString:@".header-info { background: #2d2d30; padding: 15px; border-radius: 5px; margin: 10px 0; }\n"];
    [html appendString:@".segment { background: #252526; padding: 10px; margin: 5px 0; border-left: 3px solid #007acc; }\n"];
    [html appendString:@".symbol { padding: 3px 0; font-size: 11px; }\n"];
    [html appendString:@".instruction { padding: 2px 0; }\n"];
    [html appendString:@".address { color: #808080; }\n"];
    [html appendString:@".mnemonic { color: #569cd6; font-weight: bold; }\n"];
    [html appendString:@".branch { color: #ce9178; font-weight: bold; }\n"];
    [html appendString:@".operand { color: #b5cea8; }\n"];
    [html appendString:@".comment { color: #6a9955; font-style: italic; }\n"];
    [html appendString:@"</style>\n</head>\n<body>\n"];
    
    [html appendFormat:@"<h1>ReDyne Decompilation: %@</h1>\n", self.fileName];
    
    [html appendString:@"<div class=\"header-info\">\n"];
    [html appendFormat:@"<strong>CPU Type:</strong> %@<br>\n", self.header.cpuType];
    [html appendFormat:@"<strong>File Type:</strong> %@<br>\n", self.header.fileType];
    [html appendFormat:@"<strong>Architecture:</strong> %@<br>\n", self.header.is64Bit ? @"64-bit" : @"32-bit"];
    [html appendFormat:@"<strong>Total Symbols:</strong> %lu<br>\n", (unsigned long)self.totalSymbols];
    [html appendFormat:@"<strong>Total Instructions:</strong> %lu<br>\n", (unsigned long)self.totalInstructions];
    [html appendFormat:@"<strong>Processed:</strong> %@\n", self.processingDate];
    [html appendString:@"</div>\n"];
    
    [html appendString:@"<h2>Segments</h2>\n"];
    for (SegmentModel *seg in self.segments) {
        [html appendFormat:@"<div class=\"segment\"><strong>%@</strong> VM: 0x%llx-0x%llx</div>\n",
         seg.name, seg.vmAddress, seg.vmAddress + seg.vmSize];
    }
    
    [html appendString:@"<h2>Disassembly (First 200 instructions)</h2>\n"];
    [html appendString:@"<div class=\"disassembly\">\n"];
    
    int count = 0;
    for (InstructionModel *inst in self.instructions) {
        if (count++ > 200) break;
        
        BOOL isBranch = inst.branchType && ![inst.branchType isEqualToString:@"None"];
        [html appendFormat:@"<div class=\"instruction\"><span class=\"address\">0x%llx:</span> ",
         inst.address];
        [html appendFormat:@"<span class=\"%@\">%@</span> ",
         isBranch ? @"branch" : @"mnemonic", inst.mnemonic];
        [html appendFormat:@"<span class=\"operand\">%@</span>", inst.operands];
        if (inst.comment.length > 0) {
            [html appendFormat:@" <span class=\"comment\">; %@</span>", inst.comment];
        }
        [html appendString:@"</div>\n"];
    }
    
    [html appendString:@"</div>\n"];
    [html appendString:@"</body>\n</html>"];
    
    return html;
}

- (NSData *)exportAsPDF {
    NSMutableData *pdfData = [NSMutableData data];
    CGRect pageRect = CGRectMake(0, 0, 612, 792);
    CGRect contentRect = CGRectInset(pageRect, 40, 60);
    
    UIGraphicsBeginPDFContextToData(pdfData, pageRect, @{});
    UIGraphicsBeginPDFPage();
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    CGFloat yPosition = contentRect.origin.y;
    
    NSDictionary *titleAttrs = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:24],
        NSForegroundColorAttributeName: [UIColor blackColor]
    };
    NSString *title = @"ReDyne Decompilation Report";
    [title drawAtPoint:CGPointMake(contentRect.origin.x, yPosition) withAttributes:titleAttrs];
    yPosition += 40;
    
    CGContextSetStrokeColorWithColor(context, [UIColor grayColor].CGColor);
    CGContextSetLineWidth(context, 1.0);
    CGContextMoveToPoint(context, contentRect.origin.x, yPosition);
    CGContextAddLineToPoint(context, CGRectGetMaxX(contentRect), yPosition);
    CGContextStrokePath(context);
    yPosition += 20;
    
    NSDictionary *bodyAttrs = @{
        NSFontAttributeName: [UIFont systemFontOfSize:11],
        NSForegroundColorAttributeName: [UIColor blackColor]
    };
    NSDictionary *boldAttrs = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:11],
        NSForegroundColorAttributeName: [UIColor blackColor]
    };
    
    [[NSString stringWithFormat:@"File: %@", self.fileName] drawAtPoint:CGPointMake(contentRect.origin.x, yPosition) withAttributes:boldAttrs];
    yPosition += 18;
    
    [[NSString stringWithFormat:@"Size: %llu bytes (%.2f MB)", self.fileSize, self.fileSize / 1024.0 / 1024.0]
     drawAtPoint:CGPointMake(contentRect.origin.x, yPosition) withAttributes:bodyAttrs];
    yPosition += 18;
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    [[NSString stringWithFormat:@"Analyzed: %@", [formatter stringFromDate:self.processingDate]]
     drawAtPoint:CGPointMake(contentRect.origin.x, yPosition) withAttributes:bodyAttrs];
    yPosition += 25;
    
    [@"MACH-O HEADER" drawAtPoint:CGPointMake(contentRect.origin.x, yPosition) withAttributes:titleAttrs];
    yPosition += 25;
    
    [[NSString stringWithFormat:@"CPU Type: %@", self.header.cpuType]
     drawAtPoint:CGPointMake(contentRect.origin.x, yPosition) withAttributes:bodyAttrs];
    yPosition += 18;
    
    [[NSString stringWithFormat:@"File Type: %@", self.header.fileType]
     drawAtPoint:CGPointMake(contentRect.origin.x, yPosition) withAttributes:bodyAttrs];
    yPosition += 18;
    
    [[NSString stringWithFormat:@"Architecture: %@", self.header.is64Bit ? @"64-bit" : @"32-bit"]
     drawAtPoint:CGPointMake(contentRect.origin.x, yPosition) withAttributes:bodyAttrs];
    yPosition += 18;
    
    [[NSString stringWithFormat:@"Encrypted: %@", self.header.isEncrypted ? @"Yes" : @"No"]
     drawAtPoint:CGPointMake(contentRect.origin.x, yPosition) withAttributes:bodyAttrs];
    yPosition += 25;
    
    [@"STATISTICS" drawAtPoint:CGPointMake(contentRect.origin.x, yPosition) withAttributes:titleAttrs];
    yPosition += 25;
    
    [[NSString stringWithFormat:@"Total Instructions: %lu", (unsigned long)self.totalInstructions]
     drawAtPoint:CGPointMake(contentRect.origin.x, yPosition) withAttributes:bodyAttrs];
    yPosition += 18;
    
    [[NSString stringWithFormat:@"Total Symbols: %lu", (unsigned long)self.totalSymbols]
     drawAtPoint:CGPointMake(contentRect.origin.x, yPosition) withAttributes:bodyAttrs];
    yPosition += 18;
    
    [[NSString stringWithFormat:@"Total Functions: %lu", (unsigned long)self.totalFunctions]
     drawAtPoint:CGPointMake(contentRect.origin.x, yPosition) withAttributes:bodyAttrs];
    yPosition += 18;
    
    [[NSString stringWithFormat:@"Total Strings: %lu", (unsigned long)self.totalStrings]
     drawAtPoint:CGPointMake(contentRect.origin.x, yPosition) withAttributes:bodyAttrs];
    yPosition += 18;
    
    if (self.totalXrefs > 0) {
        [[NSString stringWithFormat:@"Total Cross-References: %lu", (unsigned long)self.totalXrefs]
         drawAtPoint:CGPointMake(contentRect.origin.x, yPosition) withAttributes:bodyAttrs];
        yPosition += 18;
    }
    
    if (self.totalObjCClasses > 0) {
        [[NSString stringWithFormat:@"Objective-C Classes: %lu", (unsigned long)self.totalObjCClasses]
         drawAtPoint:CGPointMake(contentRect.origin.x, yPosition) withAttributes:bodyAttrs];
        yPosition += 18;
    }
    
    if (yPosition > CGRectGetMaxY(contentRect) - 100) {
        UIGraphicsBeginPDFPage();
        yPosition = contentRect.origin.y;
    } else {
        yPosition += 20;
    }
    
    [@"SEGMENTS" drawAtPoint:CGPointMake(contentRect.origin.x, yPosition) withAttributes:titleAttrs];
    yPosition += 25;
    
    for (SegmentModel *segment in self.segments) {
        if (yPosition > CGRectGetMaxY(contentRect) - 30) {
            UIGraphicsBeginPDFPage();
            yPosition = contentRect.origin.y;
        }
        
        [[NSString stringWithFormat:@"%@: 0x%llx-0x%llx (%llu bytes)",
          segment.name, segment.vmAddress, segment.vmAddress + segment.vmSize, segment.vmSize]
         drawAtPoint:CGPointMake(contentRect.origin.x, yPosition) withAttributes:bodyAttrs];
        yPosition += 18;
    }
    
    yPosition = CGRectGetMaxY(pageRect) - 40;
    NSDictionary *footerAttrs = @{
        NSFontAttributeName: [UIFont systemFontOfSize:9],
        NSForegroundColorAttributeName: [UIColor grayColor]
    };
    [@"Generated by ReDyne - iOS Decompiler" drawAtPoint:CGPointMake(contentRect.origin.x, yPosition) withAttributes:footerAttrs];
    
    UIGraphicsEndPDFContext();
    
    return pdfData;
}

@end

