// Standalone regression test for RelocationInfo.c limits (macOS: needs <mach-o/*> headers).
//
// Build (from the project directory containing ReDyne.xcodeproj):
//   clang -g -fsanitize=address,undefined -IReDyne/Models Fuzz/relocation_limits_test.c \
//     ReDyne/Models/RelocationInfo.c ReDyne/Models/MachOHeader.c -o relocation_limits_test
//   ./relocation_limits_test        # exits non-zero on failure
//
// Checks: large rebase/bind streams are no longer silently truncated at the old fixed
// array sizes (10000 / 1000), an oversized dyld-info blob is rejected instead of
// allocated, and a self-referencing export trie terminates quickly.

#include "../ReDyne/Models/RelocationInfo.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void uleb(uint8_t **p, uint64_t v) {
    do { uint8_t b = v & 0x7f; v >>= 7; if (v) b |= 0x80; *(*p)++ = b; } while (v);
}

#define CHECK(cond) do { if (!(cond)) { fprintf(stderr, "FAIL: %s (line %d)\n", #cond, __LINE__); failures++; } } while (0)

int main(void) {
    int failures = 0;
    const size_t file_size = 1 << 20;
    uint8_t *buf = calloc(1, file_size), *p = buf;

    uint8_t *rebase = p;                       // 50000 pointer rebases
    *p++ = 0x11; *p++ = 0x20; uleb(&p, 0); *p++ = 0x62; uleb(&p, 50000); *p++ = 0;
    size_t rebase_size = (size_t)(p - rebase);

    uint8_t *bind = p;                         // 5000 binds of "_x"
    *p++ = 0x11; *p++ = 0x40; memcpy(p, "_x", 3); p += 3; *p++ = 0x51;
    for (int i = 0; i < 5000; i++) { *p++ = 0x72; uleb(&p, 0); *p++ = 0x90; }
    *p++ = 0;
    size_t bind_size = (size_t)(p - bind);

    uint8_t *trie = p;                         // root with 255 children that all loop back to root
    *p++ = 0; *p++ = 255;
    for (int i = 0; i < 255; i++) { *p++ = 'a'; *p++ = 0; *p++ = 0; }
    size_t trie_size = (size_t)(p - trie);

    char path[] = "/tmp/redyne_reloc_XXXXXX";
    int fd = mkstemp(path);
    FILE *f = fdopen(fd, "wb");
    fwrite(buf, 1, file_size, f);
    fclose(f);

    MachOContext m;
    memset(&m, 0, sizeof m);
    m.file = fopen(path, "rb");
    m.file_size = (long)file_size;
    m.header.is_64bit = true;
    m.has_dyld_info = true;
    m.rebase_off = (uint64_t)(rebase - buf); m.rebase_size = (uint32_t)rebase_size;
    m.bind_off = (uint64_t)(bind - buf);     m.bind_size = (uint32_t)bind_size;
    m.export_off = (uint64_t)(trie - buf);   m.export_size = (uint32_t)trie_size;
    m.segment_count = 1;
    m.segments = calloc(1, sizeof(SegmentInfo));
    m.segments[0].vmsize = 0x100000;

    RelocationContext *c = reloc_create(&m);
    CHECK(reloc_parse_rebase(c));
    CHECK(reloc_parse_bind(c));
    CHECK(reloc_parse_exports(c));              // must return, not hang
    CHECK(c->rebase_count == 50000);
    CHECK(c->bind_count == 5000);
    CHECK(!c->truncated);

    m.bind_size = 0xF0000000u;                  // claims far more than the file holds
    RelocationContext *c2 = reloc_create(&m);
    CHECK(!reloc_parse_bind(c2));

    reloc_free(c); reloc_free(c2);
    fclose(m.file); free(m.segments); free(buf); unlink(path);
    puts(failures ? "relocation limits: FAILED" : "relocation limits: ok");
    return failures ? 1 : 0;
}
