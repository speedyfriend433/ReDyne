# Contributing to ReDyne

First off, thank you for considering contributing to ReDyne! It's people like you that make ReDyne such a great tool for the iOS reverse engineering community.

## 🌟 Ways to Contribute

### 1. Report Bugs
- Check if the bug has already been reported in [Issues](https://github.com/speedyfriend433/ReDyne/issues)
- If not, create a new issue with:
  - Clear, descriptive title
  - iOS version and device model
  - Steps to reproduce
  - Expected vs actual behavior
  - Sample binary (if possible and safe to share)
  - Screenshots or console output

### 2. Suggest Features
- Open an issue with `[Feature Request]` in the title
- Describe the feature and its use case
- Explain why it would be useful
- Link to relevant documentation or specifications

### 3. Submit Pull Requests
- Fork the repo and create a branch from `main`
- Make your changes
- Write clear commit messages
- Test thoroughly on both device and simulator
- Submit a PR with a clear description

### 4. Improve Documentation
- Fix typos or unclear instructions
- Add examples or tutorials
- Translate documentation
- Add screenshots or diagrams

## 🔧 Development Setup

### Prerequisites
- Xcode 15.0+
- macOS 14.0+ (Sonoma)
- Active Apple Developer account (for device testing)
- Understanding of C, Objective-C, or Swift

### Getting Started

1. **Fork and Clone**
   ```bash
   git clone https://github.com/speedyfriend433/ReDyne.git
   cd ReDyne
   ```

2. **Open in Xcode**
   ```bash
   open ReDyne.xcodeproj
   ```

3. **Build**
   - Select a simulator or connected device
   - Press `Cmd+B` to build
   - Press `Cmd+R` to run

4. **Test Your Changes**
   - Test on multiple iOS versions if possible
   - Test with various Mach-O binaries
   - Check both ARM64 and x86_64 architectures
   - Verify UI on different device sizes

## 📝 Code Style Guidelines

### Swift
```swift
// Use camelCase for variables and functions
let fileSize: Int64 = 1024
func parseHeader() { }

// Use PascalCase for types
class MachOParser { }
struct SegmentInfo { }

// Use meaningful names
// Good
let instructionCount = disassembler.countInstructions()

// Bad
let x = d.cnt()

// Use guard for early returns
guard let data = fileData else { return }

// Use clear types
let offset: UInt64 = 0x1000
```

### Objective-C
```objc
// Use descriptive method names
- (BOOL)parseSymbolTable:(const uint8_t *)data 
                  length:(size_t)length
                   error:(NSError **)error;

// Use nullability annotations
- (nullable NSArray<SymbolModel *> *)symbols;

// Use modern syntax
NSArray *symbols = @[@"sym1", @"sym2"];
NSDictionary *info = @{@"key": @"value"};
```

### C
```c
// Use descriptive names with prefixes
bool macho_parse_header(const uint8_t *data, size_t size);

// Use explicit types
uint32_t offset = 0x1000;
uint64_t address = 0x100000000;

// Handle errors explicitly
if (!data || size < sizeof(struct mach_header_64)) {
    return false;
}

// Clean up resources
void cleanup(Context *ctx) {
    if (ctx->buffer) {
        free(ctx->buffer);
        ctx->buffer = NULL;
    }
}

// Document complex logic
// Parse LC_SEGMENT_64 command
// Format: cmd (4) | cmdsize (4) | segname (16) | ...
```

### Comments
```swift
// Use // for single-line comments
// TODO: Add support for ARM64e

// Use /** */ for documentation
/**
 Parses a Mach-O binary and extracts metadata.
 
 - Parameter url: The file URL to parse
 - Returns: A MachOInfo object or nil if parsing fails
 - Throws: MachOError if the file is invalid
 */
func parse(url: URL) throws -> MachOInfo
```

## 🏗️ Architecture Guidelines

### Adding New Features

#### 1. C-Level Parsers (`ReDyne/Models/*.c`)
For low-level binary parsing:

```c
// Create header file
typedef struct {
    uint64_t address;
    uint32_t size;
} MyStructure;

bool parse_my_structure(const uint8_t *data, size_t size, 
                       MyStructure *out);

// Create implementation
#include "MyStructure.h"

bool parse_my_structure(const uint8_t *data, size_t size,
                       MyStructure *out) {
    if (!data || !out || size < 8) return false;
    
    out->address = *(uint64_t*)data;
    out->size = *(uint32_t*)(data + 8);
    
    return true;
}
```

#### 2. Objective-C Bridges (`ReDyne/Services/*.m`)
To expose C to Swift:

```objc
// Header
@interface MyService : NSObject
- (nullable NSArray<MyModel *> *)parseData:(NSData *)data;
@end

// Implementation
@implementation MyService
- (nullable NSArray<MyModel *> *)parseData:(NSData *)data {
    MyStructure str;
    if (!parse_my_structure(data.bytes, data.length, &str)) {
        return nil;
    }
    
    MyModel *model = [[MyModel alloc] init];
    model.address = str.address;
    model.size = str.size;
    
    return @[model];
}
@end
```

#### 3. Swift Services (`ReDyne/Services/*.swift`)
For high-level analysis:

```swift
class MyAnalyzer {
    func analyze(_ data: Data) -> [MyResult] {
        let service = MyService()
        guard let models = service.parseData(data) else {
            return []
        }
        
        return models.map { model in
            MyResult(address: model.address, size: model.size)
        }
    }
}
```

#### 4. View Controllers (`ReDyne/ViewControllers/*.swift`)
For UI:

```swift
class MyViewController: UIViewController {
    private let analyzer = MyAnalyzer()
    private var results: [MyResult] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        // Setup code
    }
    
    func analyzeData(_ data: Data) {
        results = analyzer.analyze(data)
        tableView.reloadData()
    }
}
```

## 🧪 Testing

### Manual Testing Checklist
- [ ] Test on iOS 16, 17, and 18 (if available)
- [ ] Test on iPhone and iPad
- [ ] Test in Light and Dark mode
- [ ] Test with various file sizes (1KB to 100MB)
- [ ] Test with ARM64, ARM64e, x86_64 binaries
- [ ] Test with fat/universal binaries
- [ ] Test error cases (invalid files, corrupted data)
- [ ] Test memory usage (Instruments)
- [ ] Test UI responsiveness

### Sample Binaries for Testing
Use system dylibs from iOS:
- `/usr/lib/libobjc.A.dylib` - Large, complex
- `/System/Library/Frameworks/UIKit.framework/UIKit` - Fat binary
- `/usr/lib/system/libsystem_c.dylib` - Pure C
- Your own test binaries

## 🐛 Debugging Tips

### Xcode Debugging
```bash
# Enable malloc debugging
Edit Scheme → Run → Diagnostics → Enable:
- Address Sanitizer
- Undefined Behavior Sanitizer
- Malloc Scribble
```

### Console Logging
```swift
// Use ErrorHandler for consistent logging
ErrorHandler.log(error)

// Use print() for debug output
print("🔍 Parsing at offset: \(offset)")
```

### Common Issues

**"File Not Found" on device:**
- Ensure security-scoped bookmarks are working
- Check file picker delegate implementation

**Crash on large files:**
- Check memory allocations
- Use autoreleasepool for Objective-C loops
- Profile with Instruments

**UI freezing:**
- Move parsing to background queue
- Use DispatchQueue.global()
- Update UI on main queue

## 📦 Pull Request Process

1. **Create a Feature Branch**
   ```bash
   git checkout -b feature/my-new-feature
   ```

2. **Make Your Changes**
   - Follow code style guidelines
   - Add comments for complex logic
   - Update README if needed

3. **Test Thoroughly**
   - Run on device and simulator
   - Test edge cases
   - Check for memory leaks

4. **Commit with Clear Messages**
   ```bash
   git commit -m "Add support for LC_BUILD_VERSION parsing"
   ```

5. **Push to Your Fork**
   ```bash
   git push origin feature/my-new-feature
   ```

6. **Open a Pull Request**
   - Describe what you changed and why
   - Link to related issues
   - Add screenshots if UI changed
   - Wait for review

## 🔍 Code Review Process

### What We Look For
- ✅ Code follows style guidelines
- ✅ No memory leaks or crashes
- ✅ Handles errors gracefully
- ✅ Performance is acceptable
- ✅ UI is responsive and adaptive
- ✅ Changes are well-tested
- ✅ Documentation is updated

### Review Timeline
- Initial review within 3-7 days
- Follow-up reviews within 2-3 days
- Merge after approval and passing checks

## 💡 Areas Needing Help

High-priority areas where contributions are especially welcome:

1. **Instruction Decoders**
   - More x86_64 instructions
   - SIMD/NEON instruction details
   - Instruction semantics documentation

2. **Pseudocode Generation**
   - Pattern matching for common idioms
   - Type inference
   - Variable naming

3. **UI/UX Improvements**
   - Dark mode refinements
   - iPad optimization
   - Accessibility features

4. **Documentation**
   - Code examples
   - Tutorial articles
   - API documentation

5. **Testing**
   - Unit tests
   - Integration tests
   - Performance benchmarks

## 📞 Questions?

- Open a [Discussion](https://github.com/speedyfriend433/ReDyne/discussions)
- Email: speedyfriend433@gmail.com
- Check existing [Issues](https://github.com/speedyfriend433/ReDyne/issues)

## 🙏 Thank You!

Every contribution, no matter how small, is valued and appreciated. Together we're building the best iOS decompiler for the community!

---

**Happy Coding! 🚀**


