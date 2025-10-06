// File: ReDyne/ReDyne-Bridging-Header.h - Objective-C to Swift bridging header
// Exposes Objective-C and C headers to Swift code

#ifndef ReDyne_Bridging_Header_h
#define ReDyne_Bridging_Header_h

// Import Objective-C headers
#import "AppDelegate.h"
#import "SceneDelegate.h"

// Import Model headers
#import "DecompiledOutput.h"

// Import Service headers
#import "BinaryParserService.h"
#import "DisassemblerService.h"
#import "ObjCParserBridge.h"

// Import C headers (wrapped by Objective-C services)
// Note: Direct C usage is handled through Objective-C wrappers
#import "StringExtractor.h"
#import "MachOHeader.h"
#import "SymbolTable.h"
#import "DisassemblyEngine.h"
#import "ControlFlowGraph.h"
#import "RelocationInfo.h"
#import "ObjCParser.h"
#import "DyldInfo.h"
#import "CodeSignature.h"

#endif /* ReDyne_Bridging_Header_h */

