// libFuzzer harness for ReDyne's C Mach-O parsers (macOS only: needs <mach-o/*> headers).
//
// Build (from the project directory containing ReDyne.xcodeproj):
//   clang -g -O1 -fsanitize=fuzzer,address,undefined -IReDyne/Models \
//     Fuzz/fuzz_macho.c ReDyne/Models/MachOHeader.c ReDyne/Models/SymbolTable.c ReDyne/Models/CodeSignature.c \
//     ReDyne/Models/DyldInfo.c ReDyne/Models/StringExtractor.c -o fuzz_macho
// Run:
//   mkdir corpus && ./fuzz_macho corpus -max_len=65536
// Seed corpus: any small Mach-O (e.g. `lipo -thin arm64 /usr/bin/true -output corpus/true`).

#include "../ReDyne/Models/MachOHeader.h"
#include "../ReDyne/Models/SymbolTable.h"
#include "../ReDyne/Models/CodeSignature.h"
#include "../ReDyne/Models/DyldInfo.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    char path[] = "/tmp/redyne_fuzz_XXXXXX";
    int fd = mkstemp(path);
    if (fd < 0) return 0;
    if (write(fd, data, size) != (ssize_t)size) { close(fd); unlink(path); return 0; }
    close(fd);

    char err[256] = {0};
    MachOContext *ctx = macho_open(path, err);
    if (ctx) {
        if (macho_parse_header(ctx) && macho_parse_load_commands(ctx)) {
            macho_extract_segments(ctx);
            macho_extract_sections(ctx);

            SymbolTableContext *sym = symbol_table_create(ctx);
            if (sym) { symbol_table_parse(sym); symbol_table_free(sym); }

            CodeSignatureInfo *sig = codesign_parse_signature(ctx);
            codesign_free_signature(sig);

            EntitlementsInfo *ent = codesign_parse_entitlements(ctx);
            if (ent) codesign_free_entitlements(ent);

            ImportList *imports = dyld_parse_imports(ctx);
            if (imports) dyld_free_imports(imports);
            ExportList *exports = dyld_parse_exports(ctx);
            if (exports) dyld_free_exports(exports);
        }
        macho_close(ctx);
    }
    unlink(path);
    return 0;
}
