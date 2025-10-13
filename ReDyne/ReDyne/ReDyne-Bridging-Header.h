#ifndef ReDyne_Bridging_Header_h
#define ReDyne_Bridging_Header_h

#import "AppDelegate.h"
#import "SceneDelegate.h"
#import "DecompiledOutput.h"
#import "BinaryParserService.h"
#import "DisassemblerService.h"
#import "ObjCParserBridge.h"
#import "StringExtractor.h"
#import "MachOHeader.h"
#import "SymbolTable.h"
#import "DisassemblyEngine.h"
#import "ControlFlowGraph.h"
#import "RelocationInfo.h"
#import "ObjCParser.h"
#import "DyldInfo.h"
#import "CodeSignature.h"
#import "EnhancedFilePicker.h"
#import "PseudocodeGenerator.h"
#import "ARM64InstructionDecoder.h"
#import "ClassDumpC.h"
#import "ObjCRuntimeC.h"

ObjCRuntimeInfo* objc_analyze_binary(const char* binaryPath);
void objc_free_runtime_info(ObjCRuntimeInfo *info);

ImportList* dyld_parse_imports(MachOContext *ctx);
ExportList* dyld_parse_exports(MachOContext *ctx);
LibraryList* dyld_parse_libraries(MachOContext *ctx);
void dyld_free_imports(ImportList *list);
void dyld_free_exports(ExportList *list);
void dyld_free_libraries(LibraryList *list);

#endif

