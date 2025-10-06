# Changelog

All notable changes to ReDyne will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2025-10-06

### 🎉 Initial Release

The first production-ready release of ReDyne, a comprehensive iOS decompiler and reverse engineering suite.

### ✨ Added

#### Core Features
- **Mach-O Binary Parsing**
  - Universal (fat) and thin binary support
  - ARM64, ARM64e, x86_64 architecture support
  - Magic number validation and format detection
  - Complete load command parsing
  - Segment and section analysis with flags

#### Disassembly Engine
- **ARM64 Disassembler**
  - 100+ instruction types supported
  - Data processing, load/store, branches, logical ops
  - Multiply/divide, compare, shifts
  - SIMD/FP operations
  - System instructions and barriers
  - Register usage tracking
  - Branch detection
- **x86_64 Disassembler**
  - ModR/M, SIB, REX prefix handling
  - Dynamic length calculation
  - Common instruction support

#### Analysis Features
- **Symbol Table Analysis**
  - Complete nlist/nlist_64 support
  - Symbol type detection (functions, objects, sections)
  - Dynamic symbol detection
  - Name demangling for Swift/C++
  - Address resolution
- **Cross-Reference Analysis**
  - Call graph generation (586+ calls per binary)
  - Jump/branch tracking (277+ per binary)
  - Data reference detection
  - Symbolic execution engine with ADRP+ADD recognition
  - Page-aligned address computation
- **Control Flow Graphs**
  - Hierarchical BFS-based layout
  - Basic block detection and analysis
  - Edge classification (true/false, loops, calls, returns)
  - Dominance-based loop detection
  - Interactive visualization with zoom (0.05x-3.0x) and pan
  - Dynamic sizing for 1-158+ node graphs
  - Color-coded nodes (entry: blue, exit: red, conditional: orange)
- **Objective-C Runtime Analysis**
  - Class extraction from `__objc_classlist`
  - Method discovery (instance and class)
  - Property parsing
  - Instance variable layouts
  - Category parsing with methods/properties
  - Protocol conformance detection
- **Import/Export Tables**
  - Dyld bind info (all 12 opcodes)
  - Dyld rebase info (all 9 opcodes)
  - Export trie traversal with ULEB128 decoding
  - Weak import detection
  - Lazy binding tracking
  - Library dependency tree
- **Code Signature Inspector**
  - SuperBlob structure parsing
  - CodeDirectory extraction (CDHash, Team ID, Signing ID)
  - Entitlement parsing and XML formatting
  - Requirements validation
  - Signature type detection (ad-hoc vs full)
- **String Analysis**
  - C-string extraction from multiple sections
  - Minimum length filtering
  - Encoding detection
  - Section-aware extraction

#### Export Capabilities
- TXT export (clean, readable)
- JSON export (structured with full metadata)
- HTML export (styled with syntax highlighting)
- PDF export (multi-page with professional typography)
- Native iOS share sheet integration

#### User Interface
- **File Management**
  - UIDocumentPicker integration
  - Recent files with security-scoped bookmarks
  - Swipe-to-delete
  - Persistent file access across app restarts
- **Results Display**
  - 11-tab interface for comprehensive analysis
  - Searchable tables
  - Copy/share functionality
  - Dark mode support
  - Adaptive layout for iPhone and iPad
- **CFG Viewer**
  - Interactive graph visualization
  - Core Graphics rendering
  - Pinch-to-zoom and pan gestures
  - Node tap for basic block inspection
  - Auto-fit for optimal viewing

#### Architecture
- C-based binary parsers for maximum performance
- Objective-C service layer for Swift bridging
- Swift UI layer with UIKit
- MVVM architecture with clear separation
- Background processing for large files
- Memory-efficient parsing

### 🛠️ Technical Improvements
- Strict prologue detection for accurate function boundaries
- Priority-based ARM64 instruction decoding (B/BL → RET/BR/BLR → STP/LDP → others)
- Memory-safe export trie traversal
- Comprehensive bounds checking in C parsers
- Efficient register state tracking
- Dynamic CFG layout with loop-back edge support

### 🐛 Bug Fixes
- Fixed EXC_BAD_ACCESS crash in dyld export parser
- Fixed arithmetic overflow in function size calculation
- Fixed instruction decoding for STP/LDP (moved to top-level check)
- Fixed RET/BR/BLR decoding (moved to top-level check)
- Fixed B/BL decoding (moved to very top of decoder)
- Fixed function truncation due to overly broad prologue detection
- Fixed CFG graph clipping for complex layouts
- Fixed zero cross-references due to incorrect branch detection
- Fixed zero CFG nodes/edges due to incorrect instruction parsing
- Fixed branch flag propagation from C to Swift

### 📚 Documentation
- Comprehensive README with feature list
- Detailed BUILD_GUIDE for developers
- Contributing guidelines with code style and architecture
- GitHub issue templates (bug reports, feature requests)
- Pull request template
- MIT License
- Architecture documentation

### 🎯 Known Limitations
- Very large binaries (>100MB) may cause memory pressure
- Some complex ObjC runtime structures not yet parsed
- x86_64 coverage prioritized but not 100%

---

## [0.1.0] - Development Versions

### Initial Development
- Basic Mach-O parsing
- Simple disassembly
- Initial UI implementation
- Core architecture established

---

## Legend

- 🎉 Major release
- ✨ New features
- 🛠️ Improvements
- 🐛 Bug fixes
- 📚 Documentation
- 🔐 Security
- ⚡ Performance
- 🎨 UI/UX
- ♻️ Refactoring
- 🗑️ Removal
- ⚠️ Deprecation

---

[Unreleased]: https://github.com/speedyfriend433/ReDyne/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/speedyfriend433/ReDyne/releases/tag/v1.0.0
[0.1.0]: https://github.com/speedyfriend433/ReDyne/releases/tag/v0.1.0

