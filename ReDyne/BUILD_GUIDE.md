# ReDyne Build & Configuration Guide

This guide provides step-by-step instructions for building and configuring the ReDyne iOS dylib decompiler.

## Prerequisites

- macOS 12.0 or later
- Xcode 14.0 or later
- iOS 15.0+ target device or simulator
- Basic knowledge of Xcode project configuration

## Project Structure

```
ReDyne/
├── ReDyne/                           # Main app target
│   ├── Main/                         # Entry points (AppDelegate, SceneDelegate, main.m)
│   ├── Models/                       # C and Objective-C models
│   ├── Services/                     # Objective-C service layer
│   ├── ViewControllers/              # Swift UI layer
│   ├── Utilities/                    # Swift utilities
│   ├── Extensions/                   # Swift extensions
│   ├── Assets.xcassets/              # App assets
│   ├── Info.plist                    # App configuration
│   └── ReDyne-Bridging-Header.h      # Objective-C to Swift bridge
├── ReDyneTests/                      # Unit tests
├── Documentation/                    # Architecture docs
├── README.md                         # User documentation
└── BUILD_GUIDE.md                    # This file
```

## Step 1: Open the Project

1. Navigate to the project directory:
   ```bash
   cd /Users/speedy/Desktop/r/ReDyne
   ```

2. Open the Xcode project:
   ```bash
   open ReDyne.xcodeproj
   ```

## Step 2: Configure Build Settings

### Target Configuration

1. Select the `ReDyne` target in Xcode
2. Go to **General** tab:
   - **Display Name**: ReDyne
   - **Bundle Identifier**: com.jian.ReDyne
   - **Version**: 1.0
   - **Build**: 1
   - **Deployment Target**: iOS 15.0
   - **Devices**: Universal (iPhone/iPad)

### Build Settings Configuration

Navigate to **Build Settings** tab and configure:

#### Swift Compiler - General
- **Objective-C Bridging Header**: `ReDyne/ReDyne-Bridging-Header.h`
- **Install Objective-C Compatibility Header**: Yes

#### Swift Compiler - Language
- **Swift Language Version**: Swift 5

#### Apple Clang - Language
- **C Language Dialect**: GNU11
- **C++ Language Dialect**: GNU++17 (if needed)
- **Enable Modules (C and Objective-C)**: Yes

#### Apple Clang - Language - Objective-C
- **Objective-C Automatic Reference Counting**: Yes

#### Linking
- **Other Linker Flags**: (empty, or add `-ObjC` if needed)

#### Search Paths
- **Header Search Paths**: (should be auto-configured)
  - `$(inherited)`
  - `"$(SRCROOT)/ReDyne/Models"` (if headers not found)

## Step 3: Verify File Membership

Ensure all files are added to the correct target:

### Compile Sources (Build Phases → Compile Sources)

Add all implementation files:

**C Files:**
- `ReDyne/Models/MachOHeader.c`
- `ReDyne/Models/SymbolTable.c`
- `ReDyne/Models/DisassemblyEngine.c`
- `ReDyne/Models/ControlFlowGraph.c`
- `ReDyne/Models/RelocationInfo.c`

**Objective-C Files:**
- `ReDyne/Main/main.m`
- `ReDyne/Main/AppDelegate.m`
- `ReDyne/Main/SceneDelegate.m`
- `ReDyne/Models/DecompiledOutput.m`
- `ReDyne/Services/BinaryParserService.m`
- `ReDyne/Services/DisassemblerService.m`

**Swift Files:**
- All files in `ReDyne/ViewControllers/`
- All files in `ReDyne/Utilities/`
- All files in `ReDyne/Extensions/`

### Copy Bundle Resources (Build Phases → Copy Bundle Resources)
- `ReDyne/Assets.xcassets`
- `ReDyne/Info.plist` (should be in Supporting Files, not bundled)

## Step 4: Configure Info.plist

Verify `Info.plist` contains:

```xml
<key>CFBundleIdentifier</key>
<string>com.jian.ReDyne</string>
<key>CFBundleDisplayName</key>
<string>ReDyne</string>
<key>UIApplicationSceneManifest</key>
<dict>
    <key>UIApplicationSupportsMultipleScenes</key>
    <false/>
    <key>UISceneConfigurations</key>
    <dict>
        <key>UIWindowSceneSessionRoleApplication</key>
        <array>
            <dict>
                <key>UISceneConfigurationName</key>
                <string>Default Configuration</string>
                <key>UISceneDelegateClassName</key>
                <string>ReDyne.SceneDelegate</string>
            </dict>
        </array>
    </dict>
</dict>
```

**Important**: Since we're using UIKit (not SwiftUI), remove these entries if present:
- Remove `UIApplicationSceneManifest.UIApplicationSupportsMultipleScenes` = YES
- Remove any SwiftUI-related keys

## Step 5: Build the Project

### Clean Build Folder
```
Product → Clean Build Folder (Shift+Cmd+K)
```

### Build
```
Product → Build (Cmd+B)
```

### Common Build Issues

#### Issue: "Bridging header not found"
**Solution**: 
1. Check path in Build Settings → Swift Compiler - General → Objective-C Bridging Header
2. Ensure path is: `ReDyne/ReDyne-Bridging-Header.h`
3. Verify file exists at that location

#### Issue: "Undefined symbols for architecture arm64"
**Solution**:
1. Verify all `.c` and `.m` files are in **Compile Sources**
2. Check for missing `#include` or `#import` statements
3. Ensure function declarations match implementations

#### Issue: "Use of undeclared identifier" in C files
**Solution**:
1. Check that all necessary system headers are included:
   ```c
   #include <mach-o/loader.h>
   #include <mach-o/fat.h>
   #include <mach-o/nlist.h>
   ```
2. Verify header search paths include `<mach/machine.h>`

#### Issue: "Cannot find 'SymbolModel' in scope" (Swift)
**Solution**:
1. Verify bridging header includes: `#import "DecompiledOutput.h"`
2. Clean build folder and rebuild

#### Issue: "main.m: Multiple entry points"
**Solution**:
1. Ensure only one `main` function exists (should be in `main.m`)
2. Remove any `@main` or `@UIApplicationMain` from Swift files

## Step 6: Run the Application

### Select Target Device
- Choose an iOS Simulator (iPhone 14 Pro or later recommended)
- Or connect a physical iOS device (requires Developer Account for signing)

### Code Signing (Physical Device Only)

1. Select **Signing & Capabilities** tab
2. **Automatically manage signing**: Yes
3. **Team**: Select your Apple Developer team
4. Resolve any provisioning profile issues

### Run
```
Product → Run (Cmd+R)
```

## Step 7: Verify Functionality

### Initial Launch
- App should launch to FilePickerViewController
- Navigation bar title should be "ReDyne"
- Should see "Select Binary File" button

### Test with Sample File

Since iOS sandboxing prevents direct access to system libraries, you'll need to:

1. **Option A - Use Simulator**: 
   - Extract a dylib from simulator filesystem via Terminal
   - Example: `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot/usr/lib/libSystem.dylib`
   - Copy to accessible location

2. **Option B - Use File Sharing**:
   - Add a sample dylib to project
   - Or use Files app integration

3. **Test Flow**:
   - Tap "Select Binary File"
   - Choose a .dylib file
   - Verify progress screen appears
   - Check results display correctly

### Expected Results
- Header info displays (CPU type, file type, etc.)
- Symbols table populates
- Disassembly shows ARM64 instructions
- No crashes or errors

## Step 8: Running Tests

### Unit Tests

1. Select **ReDyneTests** scheme
2. Run tests:
   ```
   Product → Test (Cmd+U)
   ```

### Expected Test Results
- All tests should pass or show as expected failures
- Tests validate:
  - Error handling
  - Address formatting
  - Symbol sorting/filtering
  - Register validation
  - Instruction search

## Troubleshooting

### Runtime Issues

#### App Crashes on Launch
**Debug Steps**:
1. Check console output in Xcode
2. Enable exception breakpoints (Breakpoint Navigator → + → Exception Breakpoint)
3. Verify AppDelegate and SceneDelegate are correctly implemented
4. Check Info.plist configuration

#### "File Access Denied" Error
**Solution**:
- This is expected for direct filesystem access
- Must use UIDocumentPicker
- Verify Info.plist has document browser support keys

#### Disassembly Shows Only `.word` Instructions
**Possible Causes**:
1. Binary is encrypted (check `header.isEncrypted`)
2. Binary is not ARM64 (check `header.cpuType`)
3. __text section not found (check section parsing)

#### Memory Warnings/Crashes on Large Files
**Solutions**:
1. Reduce `MAX_FILE_SIZE` in `MachOHeader.h`
2. Limit instructions displayed in `Constants.swift`
3. Enable memory profiling in Instruments

### Performance Issues

#### Slow Parsing
- Check file size (should be < 200MB)
- Profile with Instruments (Time Profiler)
- Verify background queue is being used

#### UI Freezes
- Ensure all heavy operations on background queue
- Verify main thread updates are not blocking
- Check for retain cycles in closures

## Advanced Configuration

### Custom Architectures

To add support for additional architectures:

1. Edit `DisassemblyEngine.c`
2. Add new `Architecture` enum value
3. Implement decoding function (e.g., `disasm_arm32()`)
4. Update `disasm_create()` to detect architecture

### Custom Export Formats

1. Add method in `DecompiledOutput.m`:
   ```objc
   - (NSData *)exportAsJSON {
       // Implementation
   }
   ```
2. Add menu option in `ResultsViewController.swift`

### Logging Configuration

Enable verbose logging:

1. Add to `ErrorHandler.swift`:
   ```swift
   static let debugLogging = true
   ```
2. Check console for detailed output

## Deployment

### App Store Considerations

**Important**: This app's functionality (reverse engineering) may not be suitable for App Store distribution. Consider:

- Enterprise distribution
- TestFlight beta
- Ad-hoc distribution

### Building for Release

1. Set build configuration to **Release**
2. Enable optimization (`-Os` or `-O2`)
3. Archive:
   ```
   Product → Archive
   ```
4. Distribute via Organizer

## Additional Resources

- **README.md**: User-facing documentation
- **Architecture.md**: Technical architecture details
- **Apple Documentation**: 
  - [Mach-O File Format](https://developer.apple.com/documentation/kernel/mach-o_file_format_reference)
  - [UIKit Documentation](https://developer.apple.com/documentation/uikit)

## Getting Help

### Common Questions

**Q: Can I decompile App Store apps?**
A: No, App Store apps are encrypted. Only unencrypted binaries can be decompiled.

**Q: Why doesn't it work with all dylib files?**
A: Some limitations:
- Must be unencrypted
- Must be ARM64 or x86_64
- Must be valid Mach-O format
- File size < 200MB

**Q: How do I add more instruction support?**
A: Edit `DisassemblyEngine.c`, add new opcode patterns in `disasm_arm64()` function.

### Contact & Contributions

For issues or contributions, refer to the project repository or documentation.

---

**Version**: 1.0  
**Last Updated**: October 2025

