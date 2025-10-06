# ReDyne Architecture Documentation

## Overview

ReDyne is a sophisticated iOS application for decompiling and analyzing dynamic libraries (.dylib files). It employs a multi-layered architecture combining Swift for UI, Objective-C for bridging, and C for low-level binary analysis.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                          User Interface Layer (Swift)            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ FilePicker   │  │ Decompile    │  │ Results      │          │
│  │ ViewController│  │ ViewController│  │ViewController│          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│         │                  │                  │                  │
└─────────┼──────────────────┼──────────────────┼──────────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Service Layer (Objective-C)                   │
│  ┌──────────────────────────┐  ┌─────────────────────────────┐ │
│  │ BinaryParserService      │  │ DisassemblerService         │ │
│  │ - parseBinary()          │  │ - disassembleFile()         │ │
│  │ - extractSymbols()       │  │ - extractFunctions()        │ │
│  │ - isValidMachO()         │  │ - generatePseudocode()      │ │
│  └──────────────────────────┘  └─────────────────────────────┘ │
│         │                              │                         │
│         │        ┌─────────────────────┘                         │
│         │        │                                               │
└─────────┼────────┼───────────────────────────────────────────────┘
          │        │
          ▼        ▼
┌─────────────────────────────────────────────────────────────────┐
│                       Model Layer (Objective-C)                  │
│  ┌──────────────────┐  ┌──────────────────┐                    │
│  │ DecompiledOutput │  │ InstructionModel │                    │
│  │ SymbolModel      │  │ FunctionModel    │                    │
│  └──────────────────┘  └──────────────────┘                    │
└─────────────────────────────────────────────────────────────────┘
          │                  
          │                  
          ▼                  
┌─────────────────────────────────────────────────────────────────┐
│                      Core Engine Layer (C)                       │
│  ┌────────────────┐  ┌──────────────────┐  ┌─────────────────┐│
│  │ MachOHeader    │  │ SymbolTable      │  │ DisassemblyEngine││
│  │ - Parse header │  │ - Extract symbols│  │ - Decode ARM64  ││
│  │ - Load cmds    │  │ - Categorize     │  │ - Decode x86_64 ││
│  │ - Segments     │  │ - Sort/search    │  │ - Branch detect ││
│  └────────────────┘  └──────────────────┘  └─────────────────┘│
│                                                                  │
│  ┌────────────────┐  ┌──────────────────┐                      │
│  │ ControlFlowGraph│  │ RelocationInfo   │                      │
│  │ - Build CFG    │  │ - Parse rebase   │                      │
│  │ - Detect loops │  │ - Parse bindings │                      │
│  │ - Export DOT   │  │ - Apply slide    │                      │
│  └────────────────┘  └──────────────────┘                      │
└─────────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. User Interface Layer (Swift)

#### FilePickerViewController
- **Purpose**: Initial file selection interface
- **Responsibilities**:
  - Present UIDocumentPicker for file selection
  - Display recent files list
  - Validate file access and size
  - Navigate to DecompileViewController
- **Key Methods**:
  - `selectFile()`: Opens document picker
  - `processFile(at:)`: Validates and processes selected file

#### DecompileViewController
- **Purpose**: Background processing with progress display
- **Responsibilities**:
  - Execute parsing and disassembly on background queue
  - Display real-time progress updates
  - Handle cancellation
  - Navigate to ResultsViewController on completion
- **Key Methods**:
  - `startDecompilation()`: Initiates background processing
  - `updateStatus(_:progress:)`: Updates UI with progress
  - `handleError(_:)`: Error handling and display

#### ResultsViewController
- **Purpose**: Tabbed display of decompilation results
- **Responsibilities**:
  - Manage segmented control (Headers, Symbols, Disassembly, Functions)
  - Coordinate child view controllers
  - Implement search/filter functionality
  - Handle export operations
- **Key Methods**:
  - `showViewController(_:)`: Switch between tabs
  - `exportAsText()`, `exportAsHTML()`: Export functionality
- **Child Controllers**:
  - `HeaderViewController`: Displays Mach-O header info
  - `SymbolsViewController`: Table of symbols with search
  - `DisassemblyViewController`: Syntax-highlighted assembly
  - `FunctionsViewController`: Function list and pseudocode

#### DiffViewController
- **Purpose**: Side-by-side comparison of two binaries
- **Responsibilities**:
  - Display synchronized text views
  - Compare symbols, disassembly, statistics
  - Highlight differences
- **Key Methods**:
  - `showSymbolComparison()`: Compare symbol tables
  - `showDisassemblyComparison()`: Compare code
  - `generateStatistics(for:)`: Compute stats

### 2. Service Layer (Objective-C)

#### BinaryParserService
- **Purpose**: High-level wrapper for C parsing functions
- **Responsibilities**:
  - Open and validate Mach-O files
  - Parse headers, load commands, segments
  - Extract symbol tables
  - Convert C structures to Objective-C models
- **Key Methods**:
  ```objc
  + (DecompiledOutput *)parseBinaryAtPath:(NSString *)filePath
                            progressBlock:(ParserProgressBlock)progressBlock
                                    error:(NSError **)error;
  ```
- **Flow**:
  1. Open file with `macho_open()`
  2. Parse header with `macho_parse_header()`
  3. Parse load commands
  4. Extract segments and sections
  5. Create symbol table context
  6. Parse symbols
  7. Convert to Objective-C models
  8. Return `DecompiledOutput`

#### DisassemblerService
- **Purpose**: Disassembly orchestration
- **Responsibilities**:
  - Load code sections
  - Disassemble instructions
  - Extract functions
  - Generate pseudocode
- **Key Methods**:
  ```objc
  + (NSArray<InstructionModel *> *)disassembleFileAtPath:(NSString *)filePath
                                           progressBlock:(DisassemblyProgressBlock)progressBlock
                                                   error:(NSError **)error;
  ```
- **Flow**:
  1. Create disassembly context
  2. Load __text section
  3. Iterate and disassemble instructions
  4. Detect function boundaries
  5. Convert to Objective-C models

### 3. Model Layer (Objective-C)

#### DecompiledOutput
- **Purpose**: Complete representation of decompilation results
- **Properties**:
  - `header`: MachOHeaderModel
  - `segments`: Array of SegmentModel
  - `sections`: Array of SectionModel
  - `symbols`: Array of SymbolModel
  - `instructions`: Array of InstructionModel
  - `functions`: Array of FunctionModel
  - Statistics (totalSymbols, totalInstructions, etc.)
- **Methods**:
  - `exportAsText()`: Generate text report
  - `exportAsHTML()`: Generate HTML report

#### SymbolModel, InstructionModel, FunctionModel
- **Purpose**: Represent parsed entities
- **Features**:
  - Objective-C properties for Swift interoperability
  - Formatting methods (e.g., `attributedString()` for syntax highlighting)

### 4. Core Engine Layer (C)

#### MachOHeader (C)
- **Purpose**: Low-level Mach-O parsing
- **Data Structures**:
  ```c
  typedef struct {
      FILE *file;
      long file_size;
      MachOHeaderInfo header;
      LoadCommandInfo *load_commands;
      SegmentInfo *segments;
      SectionInfo *sections;
      // ... dyld info, encryption, UUID
  } MachOContext;
  ```
- **Key Functions**:
  - `macho_open()`: Open and validate file
  - `macho_parse_header()`: Parse mach_header_64, handle fat binaries
  - `macho_parse_load_commands()`: Extract all load commands
  - `macho_extract_segments()`: Extract segment information
  - `macho_select_architecture()`: Choose architecture from fat binary
- **Algorithm**:
  1. Read magic number, validate
  2. Check for fat binary (0xCAFEBABE)
  3. If fat, iterate fat_arch entries, select ARM64
  4. Read mach_header_64
  5. Iterate load commands, parse by type
  6. Extract segments, sections, symbol table offsets

#### SymbolTable (C)
- **Purpose**: Symbol extraction and categorization
- **Data Structures**:
  ```c
  typedef struct {
      char *name;
      uint64_t address;
      SymbolType type;
      SymbolScope scope;
      bool is_defined, is_external, is_weak;
  } SymbolInfo;
  
  typedef struct {
      MachOContext *macho_ctx;
      SymbolInfo *symbols;
      char *string_table;
      uint32_t *defined_indices, *undefined_indices;
      uint32_t *function_indices;
  } SymbolTableContext;
  ```
- **Key Functions**:
  - `symbol_table_create()`: Initialize context
  - `symbol_table_parse()`: Parse nlist_64 entries
  - `symbol_table_load_strings()`: Load string table
  - `symbol_table_categorize()`: Classify symbols
  - `symbol_table_extract_functions()`: Identify function symbols
  - `symbol_table_find_by_name()`, `_by_address()`: Search
- **Algorithm**:
  1. Read string table from stroff/strsize
  2. Seek to symtab_offset
  3. Read nsyms nlist_64 structures
  4. For each nlist:
     - Extract n_strx (string table index)
     - Determine type from n_type & N_TYPE
     - Determine scope from n_type & (N_EXT | N_PEXT)
     - Check n_desc for weak symbols
  5. Categorize into defined/undefined/external
  6. Identify functions (N_SECT type, address > 0)

#### DisassemblyEngine (C)
- **Purpose**: ARM64/x86_64 instruction decoding
- **Data Structures**:
  ```c
  typedef struct {
      uint64_t address;
      uint32_t raw_bytes;
      char mnemonic[32], operands[128];
      InstructionCategory category;
      BranchType branch_type;
      uint64_t branch_target;
      bool is_function_start, is_function_end;
  } DisassembledInstruction;
  
  typedef struct {
      MachOContext *macho_ctx;
      Architecture arch;
      uint8_t *code_data;
      uint64_t code_size, code_base_addr;
      DisassembledInstruction *instructions;
  } DisassemblyContext;
  ```
- **Key Functions**:
  - `disasm_create()`: Initialize context, determine architecture
  - `disasm_load_section()`: Load __text section into memory
  - `disasm_arm64()`: Decode ARM64 instruction (core function)
  - `disasm_all()`: Linear sweep disassembly
  - `disasm_detect_functions()`: Find function boundaries
- **ARM64 Decoding Algorithm** (`disasm_arm64()`):
  1. Read 4-byte instruction
  2. Extract op0 field (bits 28:25)
  3. Match against instruction families:
     - **Data Processing - Immediate** (op0 = 100x):
       - ADD/SUB immediate: bits 23-22 = 10, decode Rd, Rn, imm12
       - MOV wide immediate: MOVZ/MOVN/MOVK
     - **Branches** (op0 = 101x):
       - B/BL: bits 31 = link, imm26 * 4 = offset
       - B.cond: bits 24-0 = cond, imm19 * 4 = offset
       - CBZ/CBNZ: imm19, Rt
       - BR/BLR/RET: opc field, Rn
     - **Load/Store** (op0 = x1x0):
       - LDR/STR unsigned offset: size, Rt, Rn, imm12
       - STP/LDP: pre/post/signed offset, Rt, Rt2, Rn, imm7
     - **Data Processing - Register**:
       - Logical shifted register: AND/ORR/EOR
  4. Format operands:
     - Registers: X0-X30, SP (64-bit) or W0-W30, WSP (32-bit)
     - Immediates: #value
     - Branch targets: address + offset
  5. Detect function prologue/epilogue:
     - Prologue: STP X29, X30, [SP, #-XX]!
     - Epilogue: LDP X29, X30, [SP], #XX or RET
  6. Return DisassembledInstruction

#### ControlFlowGraph (C)
- **Purpose**: Control flow analysis
- **Data Structures**:
  ```c
  typedef struct BasicBlock {
      uint64_t start_address, end_address;
      struct BasicBlock **successors, **predecessors;
      EdgeType *successor_edge_types;
      bool is_entry, is_exit, is_loop_header;
  } BasicBlock;
  
  typedef struct {
      DisassemblyContext *disasm_ctx;
      BasicBlock *blocks;
      BasicBlock *entry_block, **exit_blocks;
  } CFGContext;
  ```
- **Key Functions**:
  - `cfg_build_function()`: Build CFG for function
  - `cfg_add_block()`: Create basic block
  - `cfg_add_edge()`: Connect blocks
  - `cfg_detect_loops()`: Identify back edges
  - `cfg_export_dot()`: Generate Graphviz DOT format
- **Algorithm**:
  1. **Identify Leaders** (basic block starts):
     - First instruction
     - Branch targets
     - Instructions after branches
  2. **Create Basic Blocks**:
     - From each leader to next leader or branch
  3. **Build Edges**:
     - Unconditional branch → target
     - Conditional branch → target (true), fall-through (false)
     - Call → target (call edge), fall-through (return edge)
     - Return → exit
  4. **Detect Loops**:
     - Back edge: successor address ≤ current block address
     - Mark loop header

#### RelocationInfo (C)
- **Purpose**: Parse dyld rebase/bind information (stub for future extension)
- **Data Structures**:
  ```c
  typedef struct {
      uint64_t address;
      RebaseType type;
  } RebaseEntry;
  
  typedef struct {
      uint64_t address;
      char *symbol_name;
      int32_t library_ordinal;
  } BindEntry;
  
  typedef struct {
      MachOContext *macho_ctx;
      RebaseEntry *rebases;
      BindEntry *binds, *lazy_binds, *weak_binds;
      ExportEntry *exports;
  } RelocationContext;
  ```
- **Key Functions** (stubs):
  - `reloc_parse_rebase()`: Parse rebase opcodes
  - `reloc_parse_bind()`: Parse bind opcodes
  - `reloc_parse_exports()`: Parse export trie
  - `reloc_apply_slide()`: ASLR adjustment

## Data Flow

### Parsing Flow
```
File Selection → BinaryParserService.parseBinary()
    ↓
macho_open() → Validate magic, get file size
    ↓
macho_parse_header() → Read mach_header_64, handle fat binary
    ↓
macho_parse_load_commands() → Iterate LC_* commands
    ↓
macho_extract_segments() → Extract segment_command_64
    ↓
macho_extract_sections() → Extract section_64
    ↓
symbol_table_create() → Initialize symbol context
    ↓
symbol_table_parse() → Read nlist_64, parse symbols
    ↓
symbol_table_categorize() → Classify symbols
    ↓
Convert to Objective-C models (SymbolModel, SegmentModel)
    ↓
Return DecompiledOutput
```

### Disassembly Flow
```
DisassemblerService.disassembleFile()
    ↓
disasm_create() → Initialize context, detect architecture
    ↓
disasm_load_section("__text") → Load code into memory
    ↓
disasm_all() → Linear sweep:
    ↓
    for each 4-byte chunk:
        ↓
        disasm_arm64() → Decode instruction
            ↓
            Match opcode patterns
            ↓
            Format mnemonic and operands
            ↓
            Detect branches, function boundaries
            ↓
            Return DisassembledInstruction
    ↓
disasm_detect_functions() → Find prologue/epilogue
    ↓
Convert to InstructionModel
    ↓
Return array of InstructionModel
```

### CFG Building Flow
```
cfg_create()
    ↓
cfg_build_function(start, end)
    ↓
Phase 1: Identify Leaders
    - Mark first instruction
    - Mark branch targets
    - Mark post-branch instructions
    ↓
Phase 2: Create Blocks
    - From leader to leader
    ↓
Phase 3: Build Edges
    - Analyze last instruction of each block
    - Add edges based on branch type
    ↓
cfg_detect_loops()
    - Find back edges
    ↓
cfg_export_dot()
    - Generate Graphviz output
```

## Threading & Concurrency

### Background Processing
- **Queue**: `DispatchQueue(label: "com.jian.ReDyne.backgroundQueue", qos: .userInitiated)`
- **Operations**:
  - Parsing: BinaryParserService runs on background queue
  - Disassembly: DisassemblerService runs on background queue
  - UI Updates: Progress callbacks dispatched to main queue

### Cancellation
- Uses `DispatchWorkItem` for cancellable tasks
- User can cancel via DecompileViewController cancel button
- Cleanup: All C contexts properly freed on cancellation

## Memory Management

### C Code
- **Manual Memory**: All C structures use malloc/free
- **Context Cleanup**: Each module has `_free()` function
- **File Handles**: `fclose()` in cleanup paths

### Objective-C
- **ARC**: Automatic Reference Counting for all Objective-C objects
- **C Interop**: Careful bridging with manual cleanup

### Swift
- **ARC**: Automatic
- **Large Data**: Lazy loading for instruction arrays (paginated display)

## Error Handling

### C Level
- Return `NULL` or `false` on errors
- Optional error message buffers

### Objective-C Level
- `NSError **` output parameters
- Error domains: `com.jian.ReDyne.BinaryParser`, `com.jian.ReDyne.Disassembler`

### Swift Level
- `ReDyneError` enum with `LocalizedError` conformance
- `ErrorHandler` utility for display and logging
- Graceful degradation (e.g., continue without disassembly if it fails)

## Performance Optimization

### Parsing
- **Streaming**: File read in chunks, not entire file in memory
- **Lazy Loading**: Symbols parsed on demand
- **Caching**: Recent files list cached in UserDefaults

### Disassembly
- **Linear Sweep**: Single pass through code section
- **Preallocated Arrays**: Estimated capacity for instructions
- **Chunked Display**: Only first 10,000 instructions displayed

### UI
- **Table View Recycling**: Dequeue reusable cells
- **Background Processing**: All heavy lifting off main thread
- **Progress Updates**: Throttled to avoid excessive UI updates

## Testing Strategy

### Unit Tests
- **MachOParserTests**: Validate header parsing, error handling
- **SymbolTableTests**: Test symbol sorting, filtering, search
- **DisassemblyTests**: Test instruction decoding, register validation

### Integration Tests
- **End-to-End**: Parse sample dylib, verify output

### Manual Testing
- **Sample Files**: Test with libSystem.dylib, framework binaries
- **Edge Cases**: Encrypted binaries, stripped binaries, fat binaries

## Future Enhancements

### Short Term
- Complete x86_64 disassembly support
- Implement full dyld info parsing (rebase/bind/export)
- Add more ARM64 instructions (SIMD, crypto)

### Medium Term
- Recursive descent disassembly (vs. linear sweep)
- Advanced pseudocode generation (data flow analysis)
- String and constant extraction

### Long Term
- Full decompilation to C (type inference, variable recovery)
- Interactive CFG visualization
- Plugin system for custom analysis

## Dependencies

### Apple Frameworks
- **Foundation**: Core utilities, file I/O, data structures
- **UIKit**: User interface components
- **UniformTypeIdentifiers**: File type handling

### System Headers
- `<mach-o/loader.h>`: Mach-O structures (mach_header, load_command, etc.)
- `<mach-o/fat.h>`: Fat binary structures
- `<mach-o/nlist.h>`: Symbol table structures
- `<mach/machine.h>`: CPU type constants

## Build Configuration

### Compiler Flags
- **C Files**: Compiled with Clang, no special flags needed
- **Objective-C**: ARC enabled, modules enabled
- **Swift**: Bridging header configured

### Optimization
- **Debug**: `-O0` for debugging
- **Release**: `-Os` for size, or `-O2` for speed

## Security Considerations

### Sandboxing
- App runs in iOS sandbox
- File access via UIDocumentPicker (user-granted)
- No network access required

### Binary Validation
- Magic number validation prevents crashes on invalid files
- File size limits prevent DoS
- Encryption detection prevents wasted processing

### Privacy
- All processing local, no data sent externally
- No analytics or tracking
- File paths stored in UserDefaults (local only)

---

**Document Version**: 1.0  
**Last Updated**: October 2025

