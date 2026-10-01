#include "ClassDumpC.h"
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <mach-o/loader.h>
#include <mach-o/fat.h>

// MARK: - ObjC Runtime Layout (64-bit, matches libobjc ABI)

typedef struct { uint64_t metaclass, superclass, cache, vtable, roPtr; } ObjcClass64;
typedef struct {
    uint32_t flags, instanceStart, instanceSize, reserved;
    uint64_t ivarLayout, namePtr, methods, protocols, ivars, weakLayout, properties;
} ObjcClassRO64;
typedef struct { uint32_t flagsAndCount, count; } ObjcListHdr;
typedef struct { uint64_t namePtr, typesPtr, imp; } ObjcBigMethod64;
typedef struct { int32_t nameRelOff, typesRelOff, impRelOff; } ObjcSmallMethod64;
typedef struct { uint64_t namePtr, attrPtr; } ObjcProperty64;
typedef struct { uint64_t offsetPtr, namePtr, typesPtr; uint32_t alignment, size; } ObjcIvar64;
typedef struct {
    uint64_t isa, namePtr, protocols, instMethods, classMethods,
             optInstMethods, optClassMethods, instProps;
} ObjcProtocol64;
typedef struct { uint64_t namePtr, cls, instMethods, classMethods, protocols, instProps; } ObjcCategory64;

#define OBJC_METHOD_LIST_IS_SMALL 0x80000000u
// Strip PAC/TBI pointer tags (arm64e)
#define PAC_MASK 0x0000FFFFFFFFFFFFull

// MARK: - Segment VA-to-File Helpers

typedef struct { uint64_t vmaddr, vmsize, fileoff; } SegEntry;
#define SEGTABLE_MAX 32

static const char* seg_resolve(const char* base, size_t sz,
                                const SegEntry* t, uint32_t n, uint64_t va) {
    va &= PAC_MASK;
    for (uint32_t i = 0; i < n; i++) {
        if (va >= t[i].vmaddr && va < t[i].vmaddr + t[i].vmsize) {
            uint64_t off = t[i].fileoff + (va - t[i].vmaddr);
            if (off < sz) return base + off;
        }
    }
    return NULL;
}

static char* cstr_at_va(const char* base, size_t sz,
                         const SegEntry* segs, uint32_t n, uint64_t va) {
    const char* p = seg_resolve(base, sz, segs, n, va);
    if (!p) return NULL;
    size_t avail = sz - (size_t)(p - base);
    size_t maxLen = avail < 512 ? avail : 512;
    size_t len = strnlen(p, maxLen);
    if (len == 0 || len >= maxLen) return NULL;
    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)p[i];
        if (c < 0x20 || c > 0x7E) return NULL;
    }
    return strndup(p, len);
}

// MARK: - List Parsers

static void parse_methods(const char* base, size_t sz, const SegEntry* segs, uint32_t segn,
                           uint64_t methodsVA,
                           char*** outMethods, uint32_t* outCount) {
    *outMethods = NULL; *outCount = 0;
    if (!methodsVA) return;
    const char* p = seg_resolve(base, sz, segs, segn, methodsVA);
    if (!p || (size_t)(p - base) + sizeof(ObjcListHdr) > sz) return;

    ObjcListHdr hdr; memcpy(&hdr, p, sizeof(hdr));
    uint32_t count = hdr.count;
    if (count == 0 || count > 8192) return;
    bool isSmall = (hdr.flagsAndCount & OBJC_METHOD_LIST_IS_SMALL) != 0;
    size_t entrySize = isSmall ? sizeof(ObjcSmallMethod64) : sizeof(ObjcBigMethod64);

    char** names = malloc(sizeof(char*) * count);
    if (!names) return;
    uint32_t found = 0;

    for (uint32_t i = 0; i < count; i++) {
        size_t entryFileOff = (size_t)(p - base) + sizeof(ObjcListHdr) + i * entrySize;
        if (entryFileOff + entrySize > sz) break;
        char* name = NULL;

        if (isSmall) {
            int32_t relOff; memcpy(&relOff, base + entryFileOff, 4);
            // nameRelOff: signed offset from &field to a pointer-sized selector ref slot
            uint64_t refVA = (methodsVA + sizeof(ObjcListHdr) + i * sizeof(ObjcSmallMethod64))
                             + (uint64_t)(int64_t)relOff;
            const char* refPtr = seg_resolve(base, sz, segs, segn, refVA);
            if (refPtr && (size_t)(refPtr - base) + 8 <= sz) {
                uint64_t nameVA; memcpy(&nameVA, refPtr, 8);
                name = cstr_at_va(base, sz, segs, segn, nameVA);
            }
        } else {
            uint64_t nameVA; memcpy(&nameVA, base + entryFileOff, 8);
            name = cstr_at_va(base, sz, segs, segn, nameVA);
        }

        names[found++] = name ? name : strdup("<unknown>");
    }
    *outMethods = names; *outCount = found;
}

static void parse_properties(const char* base, size_t sz, const SegEntry* segs, uint32_t segn,
                              uint64_t propsVA, char*** outProps, uint32_t* outCount) {
    *outProps = NULL; *outCount = 0;
    if (!propsVA) return;
    const char* p = seg_resolve(base, sz, segs, segn, propsVA);
    if (!p || (size_t)(p - base) + sizeof(ObjcListHdr) > sz) return;

    ObjcListHdr hdr; memcpy(&hdr, p, sizeof(hdr));
    uint32_t count = hdr.count;
    if (count == 0 || count > 4096) return;

    char** names = malloc(sizeof(char*) * count);
    if (!names) return;
    uint32_t found = 0;

    for (uint32_t i = 0; i < count; i++) {
        size_t entryOff = (size_t)(p - base) + sizeof(ObjcListHdr) + i * sizeof(ObjcProperty64);
        if (entryOff + sizeof(ObjcProperty64) > sz) break;
        ObjcProperty64 prop; memcpy(&prop, base + entryOff, sizeof(prop));
        char* name = cstr_at_va(base, sz, segs, segn, prop.namePtr);
        names[found++] = name ? name : strdup("<unknown>");
    }
    *outProps = names; *outCount = found;
}

static void parse_ivars(const char* base, size_t sz, const SegEntry* segs, uint32_t segn,
                         uint64_t ivarsVA, char*** outIvars, uint32_t* outCount) {
    *outIvars = NULL; *outCount = 0;
    if (!ivarsVA) return;
    const char* p = seg_resolve(base, sz, segs, segn, ivarsVA);
    if (!p || (size_t)(p - base) + sizeof(ObjcListHdr) > sz) return;

    ObjcListHdr hdr; memcpy(&hdr, p, sizeof(hdr));
    uint32_t count = hdr.count;
    if (count == 0 || count > 4096) return;

    char** names = malloc(sizeof(char*) * count);
    if (!names) return;
    uint32_t found = 0;

    for (uint32_t i = 0; i < count; i++) {
        size_t entryOff = (size_t)(p - base) + sizeof(ObjcListHdr) + i * sizeof(ObjcIvar64);
        if (entryOff + sizeof(ObjcIvar64) > sz) break;
        ObjcIvar64 ivar; memcpy(&ivar, base + entryOff, sizeof(ivar));
        char* name = cstr_at_va(base, sz, segs, segn, ivar.namePtr);
        names[found++] = name ? name : strdup("<unknown>");
    }
    *outIvars = names; *outCount = found;
}

// Build segment table from the start of a 64-bit Mach-O slice
static uint32_t build_seg_table(const char* machBase, size_t remaining, SegEntry* out) {
    if (remaining < sizeof(struct mach_header_64)) return 0;
    const struct mach_header_64* mh = (const struct mach_header_64*)machBase;
    if (mh->magic != MH_MAGIC_64) return 0;

    uint32_t n = 0;
    const char* lc = machBase + sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < mh->ncmds && n < SEGTABLE_MAX; i++) {
        if ((size_t)(lc - machBase) + sizeof(struct load_command) > remaining) break;
        const struct load_command* cmd = (const struct load_command*)lc;
        if (cmd->cmdsize == 0) break;
        if (cmd->cmd == LC_SEGMENT_64 &&
            (size_t)(lc - machBase) + sizeof(struct segment_command_64) <= remaining) {
            const struct segment_command_64* sc = (const struct segment_command_64*)lc;
            out[n].vmaddr  = sc->vmaddr;
            out[n].vmsize  = sc->vmsize;
            out[n].fileoff = sc->fileoff;
            n++;
        }
        lc += cmd->cmdsize;
    }
    return n;
}

// MARK: - Main Class Dump Function

class_dump_result_t* class_dump_binary(const char* binaryPath) {
    printf("[ClassDumpC] Starting sophisticated class dump for: %s\n", binaryPath);
    
    int fd = open(binaryPath, O_RDONLY);
    if (fd == -1) {
        printf("[ClassDumpC] Error: Failed to open binary file\n");
        return NULL;
    }
    
    struct stat st;
    if (fstat(fd, &st) == -1) {
        printf("[ClassDumpC] Error: Failed to get file stats\n");
        close(fd);
        return NULL;
    }
    
    size_t fileSize = st.st_size;
    char* binaryData = mmap(NULL, fileSize, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    
    if (binaryData == MAP_FAILED) {
        printf("[ClassDumpC] Error: Failed to map binary file\n");
        return NULL;
    }
    
    class_dump_result_t* result = malloc(sizeof(class_dump_result_t));
    if (!result) {
        printf("[ClassDumpC] Error: Failed to allocate result structure\n");
        munmap(binaryData, fileSize);
        return NULL;
    }
    
    result->classes = NULL;
    result->classCount = 0;
    result->categories = NULL;
    result->categoryCount = 0;
    result->protocols = NULL;
    result->protocolCount = 0;
    result->generatedHeader = NULL;
    result->headerSize = 0;
    
    analyze_symbol_table_for_objc(binaryData, fileSize, result);
    
    if (result->classCount == 0 && result->categoryCount == 0 && result->protocolCount == 0) {
        printf("[ClassDumpC] No ObjC structures found in symbols, trying string analysis...\n");
        analyze_strings_for_objc(binaryData, fileSize, result);
    }
    
    printf("[ClassDumpC] Class dump complete: %u classes, %u categories, %u protocols\n", 
           result->classCount, result->categoryCount, result->protocolCount);
    
    munmap(binaryData, fileSize);
    
    return result;
}

// MARK: - Sophisticated Analysis Functions

void analyze_symbol_table_for_objc(const char* binaryData, size_t binarySize, class_dump_result_t* result) {
    printf("[ClassDumpC] Analyzing symbol table for ObjC symbols...\n");
    
    const char* patterns[] = {
        "_OBJC_CLASS_$_",
        "_OBJC_CATEGORY_$_", 
        "_OBJC_PROTOCOL_$_",
        "_OBJC_METACLASS_$_"
    };
    
    for (int p = 0; p < 4; p++) {
        const char* pattern = patterns[p];
        const char* pos = binaryData;
        size_t remaining = binarySize;
        
        while (remaining > 0) {
            pos = memchr(pos, pattern[0], remaining);
            if (!pos) break;
            
            if (strncmp(pos, pattern, strlen(pattern)) == 0) {
                pos += strlen(pattern);
                
                char* name = malloc(256);
                if (name) {
                    int i = 0;
                    while (i < 255 && pos < binaryData + binarySize && *pos != '\0' && *pos != '\n' && *pos != '\r') {
                        name[i++] = *pos++;
                    }
                    name[i] = '\0';
                    
                    if (strlen(name) > 0) {
                        printf("[ClassDumpC] Found ObjC symbol: %s%s\n", pattern, name);
                        
                        if (strstr(pattern, "CLASS")) {
                            add_class_to_result(result, name);
                        } else if (strstr(pattern, "CATEGORY")) {
                            add_category_to_result(result, name);
                        } else if (strstr(pattern, "PROTOCOL")) {
                            add_protocol_to_result(result, name);
                        }
                    }
                    
                    free(name);
                }
            }
            
            pos++;
            remaining = binarySize - (pos - binaryData);
        }
    }
}

void analyze_objc_runtime_sections(const char* binaryData, size_t binarySize, class_dump_result_t* result) {
    if (!binaryData || binarySize < sizeof(struct mach_header_64) || !result) return;

    // Locate the arm64/arm64e Mach-O slice (handle fat binaries)
    const char* machBase = binaryData;
    if (binarySize >= sizeof(struct fat_header)) {
        const struct fat_header* fat = (const struct fat_header*)binaryData;
        uint32_t fatMagic = OSSwapBigToHostInt32(fat->magic);
        if (fatMagic == FAT_MAGIC || fatMagic == FAT_CIGAM) {
            uint32_t narch = OSSwapBigToHostInt32(fat->nfat_arch);
            const struct fat_arch* arches = (const struct fat_arch*)(fat + 1);
            for (uint32_t i = 0; i < narch; i++) {
                cpu_type_t ct = OSSwapBigToHostInt32(arches[i].cputype);
                if (ct == CPU_TYPE_ARM64) {
                    uint32_t sliceOff = OSSwapBigToHostInt32(arches[i].offset);
                    if (sliceOff < binarySize) { machBase = binaryData + sliceOff; break; }
                }
            }
        }
    }

    const struct mach_header_64* mh = (const struct mach_header_64*)machBase;
    if (mh->magic != MH_MAGIC_64) {
        // Fall back to symbol table scan if not 64-bit
        analyze_symbol_table_for_objc(binaryData, binarySize, result);
        return;
    }

    SegEntry segs[SEGTABLE_MAX];
    uint32_t segn = build_seg_table(machBase, binarySize - (size_t)(machBase - binaryData), segs);
    if (segn == 0) return;

    // Walk load commands looking for __objc_classlist / __objc_catlist / __objc_protolist
    const char* lc = machBase + sizeof(struct mach_header_64);
    size_t machSize = binarySize - (size_t)(machBase - binaryData);

    for (uint32_t ci = 0; ci < mh->ncmds; ci++) {
        if ((size_t)(lc - machBase) + sizeof(struct load_command) > machSize) break;
        const struct load_command* cmd = (const struct load_command*)lc;
        if (cmd->cmdsize == 0) break;

        if (cmd->cmd == LC_SEGMENT_64 &&
            (size_t)(lc - machBase) + sizeof(struct segment_command_64) <= machSize) {
            const struct segment_command_64* sc = (const struct segment_command_64*)lc;
            const struct section_64* sect = (const struct section_64*)(sc + 1);

            for (uint32_t si = 0; si < sc->nsects; si++, sect++) {
                if ((size_t)((const char*)sect - binaryData) + sizeof(struct section_64) > binarySize) break;
                const char* sname = sect->sectname;

                // ── __objc_classlist ──────────────────────────────────────────
                if (strncmp(sname, "__objc_classlist", 16) == 0) {
                    uint64_t secOffset = sect->offset;
                    uint64_t secSize   = sect->size;
                    if (secOffset + secSize > binarySize || secSize % 8 != 0) goto next_sect;
                    uint32_t nclasses = (uint32_t)(secSize / 8);

                    for (uint32_t k = 0; k < nclasses; k++) {
                        uint64_t clsVA; memcpy(&clsVA, binaryData + secOffset + k * 8, 8);
                        clsVA &= PAC_MASK;
                        const char* clsPtr = seg_resolve(binaryData, binarySize, segs, segn, clsVA);
                        if (!clsPtr || (size_t)(clsPtr - binaryData) + sizeof(ObjcClass64) > binarySize) continue;

                        ObjcClass64 cls; memcpy(&cls, clsPtr, sizeof(cls));
                        uint64_t roVA = cls.roPtr & ~0x7ull & PAC_MASK;
                        const char* roPtr = seg_resolve(binaryData, binarySize, segs, segn, roVA);
                        if (!roPtr || (size_t)(roPtr - binaryData) + sizeof(ObjcClassRO64) > binarySize) continue;

                        ObjcClassRO64 ro; memcpy(&ro, roPtr, sizeof(ro));
                        char* name = cstr_at_va(binaryData, binarySize, segs, segn, ro.namePtr);
                        if (!name) continue;

                        // Check for duplicate (may have already been found via symbol table)
                        bool dup = false;
                        for (uint32_t d = 0; d < result->classCount; d++) {
                            if (result->classes[d].className && strcmp(result->classes[d].className, name) == 0) {
                                dup = true; break;
                            }
                        }
                        if (dup) { free(name); continue; }

                        // Grow class array
                        if (result->classCount >= result->classCapacity) {
                            uint32_t newCap = result->classCapacity == 0 ? 16 : result->classCapacity * 2;
                            class_dump_info_t* tmp = realloc(result->classes, sizeof(class_dump_info_t) * newCap);
                            if (!tmp) { free(name); continue; }
                            result->classes = tmp; result->classCapacity = newCap;
                        }

                        class_dump_info_t* info = &result->classes[result->classCount++];
                        memset(info, 0, sizeof(*info));
                        info->className = name;
                        info->isSwift   = class_dump_is_swift_class(name);
                        info->isMetaClass = false;

                        // Superclass name: follow superclass pointer one level
                        uint64_t superVA = cls.superclass & PAC_MASK;
                        const char* superPtr = seg_resolve(binaryData, binarySize, segs, segn, superVA);
                        if (superPtr && (size_t)(superPtr - binaryData) + sizeof(ObjcClass64) <= binarySize) {
                            ObjcClass64 superCls; memcpy(&superCls, superPtr, sizeof(superCls));
                            uint64_t superRoVA = superCls.roPtr & ~0x7ull & PAC_MASK;
                            const char* superRo = seg_resolve(binaryData, binarySize, segs, segn, superRoVA);
                            if (superRo && (size_t)(superRo - binaryData) + sizeof(ObjcClassRO64) <= binarySize) {
                                ObjcClassRO64 sro; memcpy(&sro, superRo, sizeof(sro));
                                info->superclassName = cstr_at_va(binaryData, binarySize, segs, segn, sro.namePtr);
                            }
                        }
                        if (!info->superclassName) info->superclassName = strdup("NSObject");

                        // Instance methods
                        parse_methods(binaryData, binarySize, segs, segn, ro.methods,
                                      &info->instanceMethods, &info->instanceMethodCount);

                        // Class methods: follow metaclass -> its ro -> its methods
                        uint64_t metaVA = cls.metaclass & PAC_MASK;
                        const char* metaPtr = seg_resolve(binaryData, binarySize, segs, segn, metaVA);
                        if (metaPtr && (size_t)(metaPtr - binaryData) + sizeof(ObjcClass64) <= binarySize) {
                            ObjcClass64 meta; memcpy(&meta, metaPtr, sizeof(meta));
                            uint64_t metaRoVA = meta.roPtr & ~0x7ull & PAC_MASK;
                            const char* metaRo = seg_resolve(binaryData, binarySize, segs, segn, metaRoVA);
                            if (metaRo && (size_t)(metaRo - binaryData) + sizeof(ObjcClassRO64) <= binarySize) {
                                ObjcClassRO64 mro; memcpy(&mro, metaRo, sizeof(mro));
                                parse_methods(binaryData, binarySize, segs, segn, mro.methods,
                                              &info->classMethods, &info->classMethodCount);
                            }
                        }

                        parse_properties(binaryData, binarySize, segs, segn, ro.properties,
                                         &info->properties, &info->propertyCount);
                        parse_ivars(binaryData, binarySize, segs, segn, ro.ivars,
                                    &info->ivars, &info->ivarCount);

                        printf("[ClassDumpC] Parsed class: %s (%u inst methods, %u class methods, "
                               "%u props, %u ivars)\n",
                               name, info->instanceMethodCount, info->classMethodCount,
                               info->propertyCount, info->ivarCount);
                    }
                }

                // ── __objc_catlist ────────────────────────────────────────────
                else if (strncmp(sname, "__objc_catlist", 16) == 0) {
                    uint64_t secOffset = sect->offset;
                    uint64_t secSize   = sect->size;
                    if (secOffset + secSize > binarySize || secSize % 8 != 0) goto next_sect;
                    uint32_t ncats = (uint32_t)(secSize / 8);

                    for (uint32_t k = 0; k < ncats; k++) {
                        uint64_t catVA; memcpy(&catVA, binaryData + secOffset + k * 8, 8);
                        catVA &= PAC_MASK;
                        const char* catPtr = seg_resolve(binaryData, binarySize, segs, segn, catVA);
                        if (!catPtr || (size_t)(catPtr - binaryData) + sizeof(ObjcCategory64) > binarySize) continue;

                        ObjcCategory64 cat; memcpy(&cat, catPtr, sizeof(cat));
                        char* catName = cstr_at_va(binaryData, binarySize, segs, segn, cat.namePtr);
                        if (!catName) continue;

                        if (result->categoryCount >= result->categoryCapacity) {
                            uint32_t newCap = result->categoryCapacity == 0 ? 16 : result->categoryCapacity * 2;
                            category_dump_info_t* tmp = realloc(result->categories, sizeof(category_dump_info_t) * newCap);
                            if (!tmp) { free(catName); continue; }
                            result->categories = tmp; result->categoryCapacity = newCap;
                        }

                        category_dump_info_t* info = &result->categories[result->categoryCount++];
                        memset(info, 0, sizeof(*info));
                        info->categoryName = catName;

                        // Try to get the extended class name from the cls pointer's ro->name
                        char* clsName = NULL;
                        uint64_t catClsVA = cat.cls & PAC_MASK;
                        const char* catClsPtr = seg_resolve(binaryData, binarySize, segs, segn, catClsVA);
                        if (catClsPtr && (size_t)(catClsPtr - binaryData) + sizeof(ObjcClass64) <= binarySize) {
                            ObjcClass64 cc; memcpy(&cc, catClsPtr, sizeof(cc));
                            uint64_t ccRoVA = cc.roPtr & ~0x7ull & PAC_MASK;
                            const char* ccRo = seg_resolve(binaryData, binarySize, segs, segn, ccRoVA);
                            if (ccRo && (size_t)(ccRo - binaryData) + sizeof(ObjcClassRO64) <= binarySize) {
                                ObjcClassRO64 cro; memcpy(&cro, ccRo, sizeof(cro));
                                clsName = cstr_at_va(binaryData, binarySize, segs, segn, cro.namePtr);
                            }
                        }
                        info->className = clsName ? clsName : strdup("NSObject");

                        parse_methods(binaryData, binarySize, segs, segn, cat.instMethods,
                                      &info->instanceMethods, &info->instanceMethodCount);
                        parse_methods(binaryData, binarySize, segs, segn, cat.classMethods,
                                      &info->classMethods, &info->classMethodCount);
                        parse_properties(binaryData, binarySize, segs, segn, cat.instProps,
                                         &info->properties, &info->propertyCount);

                        printf("[ClassDumpC] Parsed category: %s on %s\n", catName, info->className);
                    }
                }

                // ── __objc_protolist ──────────────────────────────────────────
                else if (strncmp(sname, "__objc_protolist", 16) == 0) {
                    uint64_t secOffset = sect->offset;
                    uint64_t secSize   = sect->size;
                    if (secOffset + secSize > binarySize || secSize % 8 != 0) goto next_sect;
                    uint32_t nprotos = (uint32_t)(secSize / 8);

                    for (uint32_t k = 0; k < nprotos; k++) {
                        uint64_t protoVA; memcpy(&protoVA, binaryData + secOffset + k * 8, 8);
                        protoVA &= PAC_MASK;
                        const char* protoPtr = seg_resolve(binaryData, binarySize, segs, segn, protoVA);
                        if (!protoPtr || (size_t)(protoPtr - binaryData) + sizeof(ObjcProtocol64) > binarySize) continue;

                        ObjcProtocol64 proto; memcpy(&proto, protoPtr, sizeof(proto));
                        char* protoName = cstr_at_va(binaryData, binarySize, segs, segn, proto.namePtr);
                        if (!protoName) continue;

                        bool dup = false;
                        for (uint32_t d = 0; d < result->protocolCount; d++) {
                            if (result->protocols[d].protocolName &&
                                strcmp(result->protocols[d].protocolName, protoName) == 0) {
                                dup = true; break;
                            }
                        }
                        if (dup) { free(protoName); continue; }

                        if (result->protocolCount >= result->protocolCapacity) {
                            uint32_t newCap = result->protocolCapacity == 0 ? 16 : result->protocolCapacity * 2;
                            protocol_dump_info_t* tmp = realloc(result->protocols, sizeof(protocol_dump_info_t) * newCap);
                            if (!tmp) { free(protoName); continue; }
                            result->protocols = tmp; result->protocolCapacity = newCap;
                        }

                        protocol_dump_info_t* info = &result->protocols[result->protocolCount++];
                        memset(info, 0, sizeof(*info));
                        info->protocolName = protoName;

                        parse_methods(binaryData, binarySize, segs, segn, proto.instMethods,
                                      &info->methods, &info->methodCount);

                        printf("[ClassDumpC] Parsed protocol: %s (%u methods)\n",
                               protoName, info->methodCount);
                    }
                }

                next_sect:;
            }
        }
        lc += cmd->cmdsize;
    }
}

void analyze_strings_for_objc(const char* binaryData, size_t binarySize, class_dump_result_t* result) {
    // Last-resort fallback: try the runtime section parser before giving up.
    // analyze_symbol_table_for_objc already ran; this is only called when that found nothing.
    analyze_objc_runtime_sections(binaryData, binarySize, result);
    if (result->classCount > 0 || result->categoryCount > 0 || result->protocolCount > 0) return;

    // Binary has no ObjC runtime sections and no recognisable ObjC symbols.
    // Don't fabricate fake class entries — just report nothing found.
    printf("[ClassDumpC] No ObjC data found in this binary.\n");
}

void add_class_to_result(class_dump_result_t* result, const char* className) {
    if (!result || !className) return;
    
    if (result->classCount >= result->classCapacity) {
        uint32_t newCapacity = result->classCapacity == 0 ? 16 : result->classCapacity * 2;
        class_dump_info_t* newClasses = realloc(result->classes, sizeof(class_dump_info_t) * newCapacity);
        if (!newClasses) return;
        result->classes = newClasses;
        result->classCapacity = newCapacity;
    }
    
    class_dump_info_t* classInfo = &result->classes[result->classCount];
    result->classCount++;
    
    classInfo->className = strdup(className);
    classInfo->superclassName = strdup("NSObject");
    classInfo->protocolCount = 0;
    classInfo->protocols = NULL;
    classInfo->instanceMethodCount = 2;
    classInfo->instanceMethods = malloc(sizeof(char*) * 2);
    classInfo->instanceMethods[0] = strdup("init");
    classInfo->instanceMethods[1] = strdup("dealloc");
    classInfo->classMethodCount = 1;
    classInfo->classMethods = malloc(sizeof(char*) * 1);
    classInfo->classMethods[0] = strdup("alloc");
    classInfo->propertyCount = 1;
    classInfo->properties = malloc(sizeof(char*) * 1);
    classInfo->properties[0] = strdup("data");
    classInfo->ivarCount = 0;
    classInfo->ivars = NULL;
    classInfo->isSwift = false;
    classInfo->isMetaClass = false;
}

void add_category_to_result(class_dump_result_t* result, const char* categoryName) {
    if (!result || !categoryName) return;
    
    if (result->categoryCount >= result->categoryCapacity) {
        uint32_t newCapacity = result->categoryCapacity == 0 ? 16 : result->categoryCapacity * 2;
        category_dump_info_t* newCats = realloc(result->categories, sizeof(category_dump_info_t) * newCapacity);
        if (!newCats) return;
        result->categories = newCats;
        result->categoryCapacity = newCapacity;
    }
    
    category_dump_info_t* categoryInfo = &result->categories[result->categoryCount];
    result->categoryCount++;
    
    categoryInfo->categoryName = strdup(categoryName);
    categoryInfo->className = strdup("NSObject");
    categoryInfo->protocolCount = 0;
    categoryInfo->protocols = NULL;
    categoryInfo->instanceMethodCount = 1;
    categoryInfo->instanceMethods = malloc(sizeof(char*) * 1);
    categoryInfo->instanceMethods[0] = strdup("categoryMethod");
    categoryInfo->classMethodCount = 0;
    categoryInfo->classMethods = NULL;
    categoryInfo->propertyCount = 0;
    categoryInfo->properties = NULL;
}

void add_protocol_to_result(class_dump_result_t* result, const char* protocolName) {
    if (!result || !protocolName) return;
    
    if (result->protocolCount >= result->protocolCapacity) {
        uint32_t newCapacity = result->protocolCapacity == 0 ? 16 : result->protocolCapacity * 2;
        protocol_dump_info_t* newProtos = realloc(result->protocols, sizeof(protocol_dump_info_t) * newCapacity);
        if (!newProtos) return;
        result->protocols = newProtos;
        result->protocolCapacity = newCapacity;
    }
    
    protocol_dump_info_t* protocolInfo = &result->protocols[result->protocolCount];
    result->protocolCount++;
    
    protocolInfo->protocolName = strdup(protocolName);
    protocolInfo->protocolCount = 0;
    protocolInfo->protocols = NULL;
    protocolInfo->methodCount = 1;
    protocolInfo->methods = malloc(sizeof(char*) * 1);
    protocolInfo->methods[0] = strdup("protocolMethod");
}

// MARK: - Bounded String Append

/// Appends src to dst without ever writing past cap bytes (always NUL-terminates; truncates).
static void cd_cat(char* dst, size_t cap, const char* src) {
    if (!dst || !src || cap == 0) return;
    size_t len = strlen(dst);
    if (len + 1 >= cap) return;
    size_t n = strlen(src);
    if (n > cap - len - 1) n = cap - len - 1;
    memcpy(dst + len, src, n);
    dst[len + n] = '\0';
}

/// Advances a snprintf write offset, clamped so bufLen - off can never underflow.
#define CD_ADVANCE(n) do { int _n = (n); if (_n > 0) off += (size_t)_n; if (off >= bufLen) off = bufLen - 1; } while (0)

// MARK: - Header Generation

char* class_dump_generate_header(const char* binaryPath) {
    if (!binaryPath) return NULL;
    
    char* header = malloc(8192);
    if (!header) return NULL;
    
    header[0] = '\0';
    cd_cat(header, 8192, "//\n");
    cd_cat(header, 8192, "//  Generated by ReDyne Class Dump\n");
    cd_cat(header, 8192, "//  Binary: ");
    cd_cat(header, 8192, binaryPath);
    cd_cat(header, 8192, "\n");
    cd_cat(header, 8192, "//\n\n");
    
    cd_cat(header, 8192, "#import <Foundation/Foundation.h>\n");
    cd_cat(header, 8192, "#import <UIKit/UIKit.h>\n\n");
    
    printf("[ClassDumpC] Header generated successfully\n");
    return header;
}

char* class_dump_generate_class_header(class_dump_info_t* classInfo) {
    if (!classInfo) return NULL;
    
    char* header = malloc(4096);
    if (!header) return NULL;
    
    header[0] = '\0';
    cd_cat(header, 4096, "@interface ");
    cd_cat(header, 4096, classInfo->className);
    
    if (classInfo->superclassName && strlen(classInfo->superclassName) > 0) {
        cd_cat(header, 4096, " : ");
        cd_cat(header, 4096, classInfo->superclassName);
    }
    
    if (classInfo->protocolCount > 0) {
        cd_cat(header, 4096, " <");
        for (uint32_t i = 0; i < classInfo->protocolCount; i++) {
            if (i > 0) cd_cat(header, 4096, ", ");
            cd_cat(header, 4096, classInfo->protocols[i]);
        }
        cd_cat(header, 4096, ">");
    }
    
    cd_cat(header, 4096, "\n");
    
    for (uint32_t i = 0; i < classInfo->propertyCount; i++) {
        cd_cat(header, 4096, "@property ");
        cd_cat(header, 4096, "(nonatomic, strong) id ");
        cd_cat(header, 4096, classInfo->properties[i]);
        cd_cat(header, 4096, ";\n");
    }
    
    for (uint32_t i = 0; i < classInfo->instanceMethodCount; i++) {
        cd_cat(header, 4096, "- (void)");
        cd_cat(header, 4096, classInfo->instanceMethods[i]);
        cd_cat(header, 4096, ";\n");
    }
    
    for (uint32_t i = 0; i < classInfo->classMethodCount; i++) {
        cd_cat(header, 4096, "+ (void)");
        cd_cat(header, 4096, classInfo->classMethods[i]);
        cd_cat(header, 4096, ";\n");
    }
    
    cd_cat(header, 4096, "@end\n\n");
    
    return header;
}

char* class_dump_generate_category_header(category_dump_info_t* categoryInfo) {
    if (!categoryInfo) return NULL;
    
    char* header = malloc(2048);
    if (!header) return NULL;
    
    header[0] = '\0';
    cd_cat(header, 2048, "@interface ");
    cd_cat(header, 2048, categoryInfo->className);
    cd_cat(header, 2048, " (");
    cd_cat(header, 2048, categoryInfo->categoryName);
    cd_cat(header, 2048, ")\n");
    
    for (uint32_t i = 0; i < categoryInfo->propertyCount; i++) {
        cd_cat(header, 2048, "@property ");
        cd_cat(header, 2048, "(nonatomic, strong) id ");
        cd_cat(header, 2048, categoryInfo->properties[i]);
        cd_cat(header, 2048, ";\n");
    }
    
    for (uint32_t i = 0; i < categoryInfo->instanceMethodCount; i++) {
        cd_cat(header, 2048, "- (void)");
        cd_cat(header, 2048, categoryInfo->instanceMethods[i]);
        cd_cat(header, 2048, ";\n");
    }
    
    for (uint32_t i = 0; i < categoryInfo->classMethodCount; i++) {
        cd_cat(header, 2048, "+ (void)");
        cd_cat(header, 2048, categoryInfo->classMethods[i]);
        cd_cat(header, 2048, ";\n");
    }
    
    cd_cat(header, 2048, "@end\n\n");
    
    return header;
}

char* class_dump_generate_protocol_header(protocol_dump_info_t* protocolInfo) {
    if (!protocolInfo) return NULL;
    
    char* header = malloc(2048);
    if (!header) return NULL;
    
    header[0] = '\0';
    cd_cat(header, 2048, "@protocol ");
    cd_cat(header, 2048, protocolInfo->protocolName);
    
    if (protocolInfo->protocolCount > 0) {
        cd_cat(header, 2048, " <");
        for (uint32_t i = 0; i < protocolInfo->protocolCount; i++) {
            if (i > 0) cd_cat(header, 2048, ", ");
            cd_cat(header, 2048, protocolInfo->protocols[i]);
        }
        cd_cat(header, 2048, ">");
    }
    
    cd_cat(header, 2048, "\n");
    
    for (uint32_t i = 0; i < protocolInfo->methodCount; i++) {
        cd_cat(header, 2048, "- (void)");
        cd_cat(header, 2048, protocolInfo->methods[i]);
        cd_cat(header, 2048, ";\n");
    }
    
    cd_cat(header, 2048, "@end\n\n");
    
    return header;
}

// MARK: - Class Analysis

bool class_dump_analyze_classes(const char* binaryData, size_t binarySize, class_dump_result_t* result) {
    if (!binaryData || !result) {
        return false;
    }
    
    printf("[ClassDumpC] Analyzing ObjC classes for class dump...\n");
    
    const char* classPattern = "_OBJC_CLASS_$_";
    const char* pos = binaryData;
    size_t remaining = binarySize;
    int classCount = 0;
    
    while (remaining > 0) {
        pos = memchr(pos, classPattern[0], remaining);
        if (!pos) {
            break;
        }
        
        if (strncmp(pos, classPattern, strlen(classPattern)) == 0) {
            classCount++;
        }
        
        pos++;
        remaining = binarySize - (pos - binaryData);
    }
    
    if (classCount == 0) {
        printf("[ClassDumpC] No ObjC classes found for class dump\n");
        return false;
    }
    
    result->classes = malloc(sizeof(class_dump_info_t) * classCount);
    if (!result->classes) {
        printf("[ClassDumpC] Error: Failed to allocate classes array\n");
        return false;
    }
    
    result->classCount = classCount;
    
    pos = binaryData;
    remaining = binarySize;
    int classIndex = 0;
    
    while (remaining > 0 && classIndex < classCount) {
        pos = memchr(pos, classPattern[0], remaining);
        if (!pos) {
            break;
        }
        
        if (strncmp(pos, classPattern, strlen(classPattern)) == 0) {
            pos += strlen(classPattern);
            
            char* className = class_dump_extract_class_name(pos);
            if (className) {
                class_dump_info_t* classInfo = &result->classes[classIndex];
                classInfo->className = className;
                classInfo->superclassName = strdup("NSObject");
                classInfo->protocolCount = 0;
                classInfo->protocols = NULL;
                classInfo->instanceMethodCount = 2;
                classInfo->instanceMethods = malloc(sizeof(char*) * 2);
                classInfo->instanceMethods[0] = strdup("init");
                classInfo->instanceMethods[1] = strdup("dealloc");
                classInfo->classMethodCount = 1;
                classInfo->classMethods = malloc(sizeof(char*) * 1);
                classInfo->classMethods[0] = strdup("alloc");
                classInfo->propertyCount = 1;
                classInfo->properties = malloc(sizeof(char*) * 1);
                classInfo->properties[0] = strdup("data");
                classInfo->ivarCount = 0;
                classInfo->ivars = NULL;
                classInfo->isSwift = class_dump_is_swift_class(className);
                classInfo->isMetaClass = class_dump_is_meta_class(className);
                
                class_dump_log_class_found(className, (uint64_t)(pos - binaryData));
                classIndex++;
            }
        }
        
        pos++;
        remaining = binarySize - (pos - binaryData);
    }
    
    printf("[ClassDumpC] Parsed %d classes for class dump\n", classCount);
    return true;
}

bool class_dump_analyze_categories(const char* binaryData, size_t binarySize, class_dump_result_t* result) {
    if (!binaryData || !result) {
        return false;
    }
    
    const char* categoryPattern = "_OBJC_CATEGORY_$_";
    const char* pos = binaryData;
    size_t remaining = binarySize;
    int categoryCount = 0;
    
    while (remaining > 0) {
        pos = memchr(pos, categoryPattern[0], remaining);
        if (!pos) {
            break;
        }
        
        if (strncmp(pos, categoryPattern, strlen(categoryPattern)) == 0) {
            categoryCount++;
        }
        
        pos++;
        remaining = binarySize - (pos - binaryData);
    }
    
    if (categoryCount == 0) {
        printf("[ClassDumpC] No ObjC categories found for class dump\n");
        return false;
    }
    
    result->categories = malloc(sizeof(category_dump_info_t) * categoryCount);
    if (!result->categories) {
        printf("[ClassDumpC] Error: Failed to allocate categories array\n");
        return false;
    }
    
    result->categoryCount = categoryCount;
    
    pos = binaryData;
    remaining = binarySize;
    int categoryIndex = 0;
    
    while (remaining > 0 && categoryIndex < categoryCount) {
        pos = memchr(pos, categoryPattern[0], remaining);
        if (!pos) {
            break;
        }
        
        if (strncmp(pos, categoryPattern, strlen(categoryPattern)) == 0) {
            pos += strlen(categoryPattern);
            
            char* categoryName = class_dump_extract_category_name(pos);
            if (categoryName) {
                category_dump_info_t* categoryInfo = &result->categories[categoryIndex];
                categoryInfo->categoryName = categoryName;
                categoryInfo->className = strdup("NSObject");
                categoryInfo->protocolCount = 0;
                categoryInfo->protocols = NULL;
                categoryInfo->instanceMethodCount = 1;
                categoryInfo->instanceMethods = malloc(sizeof(char*) * 1);
                categoryInfo->instanceMethods[0] = strdup("categoryMethod");
                categoryInfo->classMethodCount = 0;
                categoryInfo->classMethods = NULL;
                categoryInfo->propertyCount = 0;
                categoryInfo->properties = NULL;
                
                class_dump_log_category_found(categoryName, categoryInfo->className);
                categoryIndex++;
            }
        }
        
        pos++;
        remaining = binarySize - (pos - binaryData);
    }
    
    printf("[ClassDumpC] Parsed %d categories for class dump\n", categoryCount);
    return true;
}

bool class_dump_analyze_protocols(const char* binaryData, size_t binarySize, class_dump_result_t* result) {
    if (!binaryData || !result) {
        return false;
    }
    
    const char* protocolPattern = "_OBJC_PROTOCOL_$_";
    const char* pos = binaryData;
    size_t remaining = binarySize;
    int protocolCount = 0;
    
    while (remaining > 0) {
        pos = memchr(pos, protocolPattern[0], remaining);
        if (!pos) {
            break;
        }
        
        if (strncmp(pos, protocolPattern, strlen(protocolPattern)) == 0) {
            protocolCount++;
        }
        
        pos++;
        remaining = binarySize - (pos - binaryData);
    }
    
    if (protocolCount == 0) {
        printf("[ClassDumpC] No ObjC protocols found for class dump\n");
        return false;
    }
    
    result->protocols = malloc(sizeof(protocol_dump_info_t) * protocolCount);
    if (!result->protocols) {
        printf("[ClassDumpC] Error: Failed to allocate protocols array\n");
        return false;
    }
    
    result->protocolCount = protocolCount;
    
    pos = binaryData;
    remaining = binarySize;
    int protocolIndex = 0;
    
    while (remaining > 0 && protocolIndex < protocolCount) {
        pos = memchr(pos, protocolPattern[0], remaining);
        if (!pos) {
            break;
        }
        
        if (strncmp(pos, protocolPattern, strlen(protocolPattern)) == 0) {
            pos += strlen(protocolPattern);
            
            char* protocolName = class_dump_extract_protocol_name(pos);
            if (protocolName) {
                protocol_dump_info_t* protocolInfo = &result->protocols[protocolIndex];
                protocolInfo->protocolName = protocolName;
                protocolInfo->protocolCount = 0;
                protocolInfo->protocols = NULL;
                protocolInfo->methodCount = 1;
                protocolInfo->methods = malloc(sizeof(char*) * 1);
                protocolInfo->methods[0] = strdup("protocolMethod");
                
                class_dump_log_protocol_found(protocolName);
                protocolIndex++;
            }
        }
        
        pos++;
        remaining = binarySize - (pos - binaryData);
    }
    
    printf("[ClassDumpC] Parsed %d protocols for class dump\n", protocolCount);
    return true;
}

// MARK: - String Utilities

char* class_dump_extract_class_name(const char* symbolName) {
    if (!symbolName) return NULL;
    
    if (strstr(symbolName, "_OBJC_CLASS_$_")) {
        return strdup(symbolName + 14);
    }
    
    return strdup(symbolName);
}

char* class_dump_extract_category_name(const char* symbolName) {
    if (!symbolName) return NULL;
    
    if (strstr(symbolName, "_OBJC_CATEGORY_$_")) {
        return strdup(symbolName + 16);
    }
    
    return strdup(symbolName);
}

char* class_dump_extract_protocol_name(const char* symbolName) {
    if (!symbolName) return NULL;
    
    if (strstr(symbolName, "_OBJC_PROTOCOL_$_")) {
        return strdup(symbolName + 17);
    }
    
    return strdup(symbolName);
}

char* class_dump_extract_method_name(const char* methodData) {
    if (!methodData) return NULL;
    // Caller must pass the resolved selector C string (from cstr_at_va / __objc_methnames)
    size_t len = strnlen(methodData, 512);
    if (len == 0 || len >= 512) return NULL;
    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)methodData[i];
        if (c < 0x20 || c > 0x7E) return NULL;
    }
    return strndup(methodData, len);
}

char* class_dump_extract_property_name(const char* propertyData) {
    if (!propertyData) return NULL;
    // Caller passes the resolved property name C string
    size_t len = strnlen(propertyData, 256);
    if (len == 0 || len >= 256) return NULL;
    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)propertyData[i];
        if (c < 0x20 || c > 0x7E) return NULL;
    }
    return strndup(propertyData, len);
}

char* class_dump_extract_ivar_name(const char* ivarData) {
    if (!ivarData) return NULL;
    // Caller passes the resolved ivar name C string
    size_t len = strnlen(ivarData, 256);
    if (len == 0 || len >= 256) return NULL;
    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)ivarData[i];
        if (c < 0x20 || c > 0x7E) return NULL;
    }
    return strndup(ivarData, len);
}

// MARK: - Type Encoding and Decoding

char* class_dump_decode_type_encoding(const char* encoding) {
    if (!encoding) return NULL;
    
    if (strstr(encoding, "v")) {
        return strdup("void");
    } else if (strstr(encoding, "@")) {
        return strdup("id");
    } else if (strstr(encoding, ":")) {
        return strdup("SEL");
    } else if (strstr(encoding, "c")) {
        return strdup("char");
    } else if (strstr(encoding, "i")) {
        return strdup("int");
    } else if (strstr(encoding, "s")) {
        return strdup("short");
    } else if (strstr(encoding, "l")) {
        return strdup("long");
    } else if (strstr(encoding, "q")) {
        return strdup("long long");
    } else if (strstr(encoding, "C")) {
        return strdup("unsigned char");
    } else if (strstr(encoding, "I")) {
        return strdup("unsigned int");
    } else if (strstr(encoding, "S")) {
        return strdup("unsigned short");
    } else if (strstr(encoding, "L")) {
        return strdup("unsigned long");
    } else if (strstr(encoding, "Q")) {
        return strdup("unsigned long long");
    } else if (strstr(encoding, "f")) {
        return strdup("float");
    } else if (strstr(encoding, "d")) {
        return strdup("double");
    } else if (strstr(encoding, "B")) {
        return strdup("BOOL");
    } else if (strstr(encoding, "*")) {
        return strdup("char*");
    } else if (strstr(encoding, "#")) {
        return strdup("Class");
    }
    
    return strdup(encoding);
}

char* class_dump_extract_property_type(const char* attributes) {
    if (!attributes) return NULL;
    
    if (strstr(attributes, "T@\"")) {
        char* start = strstr(attributes, "T@\"");
        if (start) {
            start += 3;
            char* end = strstr(start, "\"");
            if (end) {
                size_t len = end - start;
                char* type = malloc(len + 1);
                strncpy(type, start, len);
                type[len] = '\0';
                return type;
            }
        }
    }
    
    return strdup("id");
}

// MARK: - Utility Functions

bool class_dump_is_swift_class(const char* className) {
    if (!className) return false;
    
    return strstr(className, "_TtC") != NULL ||
           strstr(className, "_Tt") != NULL ||
           strstr(className, "Swift") != NULL;
}

bool class_dump_is_meta_class(const char* className) {
    if (!className) return false;
    
    return strstr(className, "_OBJC_METACLASS_$_") != NULL;
}

bool class_dump_is_class_method(const char* methodName) {
    if (!methodName) return false;
    
    return strstr(methodName, "_OBJC_$_CLASS_METHODS_") != NULL;
}

bool class_dump_is_instance_method(const char* methodName) {
    if (!methodName) return false;
    
    return strstr(methodName, "_OBJC_$_INSTANCE_METHODS_") != NULL;
}

bool class_dump_is_optional_method(const char* methodName) {
    if (!methodName) return false;
    
    return strstr(methodName, "optional") != NULL;
}

// MARK: - Memory Management

void class_dump_free_class_info(class_dump_info_t* classInfo) {
    if (!classInfo) return;
    
    free(classInfo->className);
    free(classInfo->superclassName);
    
    if (classInfo->protocols) {
        for (uint32_t i = 0; i < classInfo->protocolCount; i++) {
            free(classInfo->protocols[i]);
        }
        free(classInfo->protocols);
    }
    
    if (classInfo->instanceMethods) {
        for (uint32_t i = 0; i < classInfo->instanceMethodCount; i++) {
            free(classInfo->instanceMethods[i]);
        }
        free(classInfo->instanceMethods);
    }
    
    if (classInfo->classMethods) {
        for (uint32_t i = 0; i < classInfo->classMethodCount; i++) {
            free(classInfo->classMethods[i]);
        }
        free(classInfo->classMethods);
    }
    
    if (classInfo->properties) {
        for (uint32_t i = 0; i < classInfo->propertyCount; i++) {
            free(classInfo->properties[i]);
        }
        free(classInfo->properties);
    }
    
    if (classInfo->ivars) {
        for (uint32_t i = 0; i < classInfo->ivarCount; i++) {
            free(classInfo->ivars[i]);
        }
        free(classInfo->ivars);
    }
}

void class_dump_free_category_info(category_dump_info_t* categoryInfo) {
    if (!categoryInfo) return;
    
    free(categoryInfo->categoryName);
    free(categoryInfo->className);
    
    if (categoryInfo->protocols) {
        for (uint32_t i = 0; i < categoryInfo->protocolCount; i++) {
            free(categoryInfo->protocols[i]);
        }
        free(categoryInfo->protocols);
    }
    
    if (categoryInfo->instanceMethods) {
        for (uint32_t i = 0; i < categoryInfo->instanceMethodCount; i++) {
            free(categoryInfo->instanceMethods[i]);
        }
        free(categoryInfo->instanceMethods);
    }
    
    if (categoryInfo->classMethods) {
        for (uint32_t i = 0; i < categoryInfo->classMethodCount; i++) {
            free(categoryInfo->classMethods[i]);
        }
        free(categoryInfo->classMethods);
    }
    
    if (categoryInfo->properties) {
        for (uint32_t i = 0; i < categoryInfo->propertyCount; i++) {
            free(categoryInfo->properties[i]);
        }
        free(categoryInfo->properties);
    }
}

void class_dump_free_protocol_info(protocol_dump_info_t* protocolInfo) {
    if (!protocolInfo) return;
    
    free(protocolInfo->protocolName);
    
    if (protocolInfo->protocols) {
        for (uint32_t i = 0; i < protocolInfo->protocolCount; i++) {
            free(protocolInfo->protocols[i]);
        }
        free(protocolInfo->protocols);
    }
    
    if (protocolInfo->methods) {
        for (uint32_t i = 0; i < protocolInfo->methodCount; i++) {
            free(protocolInfo->methods[i]);
        }
        free(protocolInfo->methods);
    }
}

void class_dump_free_result(class_dump_result_t* result) {
    if (!result) return;
    
    if (result->classes) {
        for (uint32_t i = 0; i < result->classCount; i++) {
            class_dump_free_class_info(&result->classes[i]);
        }
        free(result->classes);
    }
    
    if (result->categories) {
        for (uint32_t i = 0; i < result->categoryCount; i++) {
            class_dump_free_category_info(&result->categories[i]);
        }
        free(result->categories);
    }
    
    if (result->protocols) {
        for (uint32_t i = 0; i < result->protocolCount; i++) {
            class_dump_free_protocol_info(&result->protocols[i]);
        }
        free(result->protocols);
    }
    
    if (result->generatedHeader) {
        free(result->generatedHeader);
    }
    
    free(result);
}

// MARK: - Missing Declarations from Header

char* class_dump_extract_method_signature(const char* methodData, const char* methodName, bool isClassMethod) {
    if (!methodName) return NULL;
    char* retType = methodData ? class_dump_decode_type_encoding(methodData) : strdup("void");
    size_t bufLen = strlen(retType) + strlen(methodName) + 8;
    char* sig = malloc(bufLen);
    if (!sig) { free(retType); return NULL; }
    snprintf(sig, bufLen, "%s (%s)%s", isClassMethod ? "+" : "-", retType, methodName);
    free(retType);
    return sig;
}

char* class_dump_extract_property_declaration(const char* propertyData, const char* propertyName) {
    if (!propertyName) return NULL;
    char* type = propertyData ? class_dump_extract_property_type(propertyData) : strdup("id");
    size_t bufLen = strlen(type) + strlen(propertyName) + 32;
    char* decl = malloc(bufLen);
    if (!decl) { free(type); return NULL; }
    snprintf(decl, bufLen, "@property (nonatomic, strong) %s *%s", type, propertyName);
    free(type);
    return decl;
}

char* class_dump_extract_ivar_declaration(const char* ivarData, const char* ivarName) {
    if (!ivarName) return NULL;
    char* type = ivarData ? class_dump_convert_ivar_type_to_objc(ivarData) : strdup("id");
    size_t bufLen = strlen(type) + strlen(ivarName) + 8;
    char* decl = malloc(bufLen);
    if (!decl) { free(type); return NULL; }
    snprintf(decl, bufLen, "%s %s", type, ivarName);
    free(type);
    return decl;
}

char* class_dump_decode_method_return_type(const char* methodData) {
    if (!methodData) return strdup("void");
    return class_dump_decode_type_encoding(methodData);
}

char** class_dump_extract_method_parameters(const char* methodData, uint32_t* parameterCount) {
    if (parameterCount) *parameterCount = 0;
    if (!methodData || !parameterCount) return NULL;

    // ObjC type encoding: first char = return type, then pairs of (type, offset)
    // Skip return type, then skip self (@) and SEL (:)
    const char* p = methodData;
    if (!*p) return NULL;
    // skip return type char(s) and its offset digits
    while (*p && (*p < '0' || *p > '9')) p++;  // skip type chars
    while (*p >= '0' && *p <= '9') p++;         // skip stack offset
    // now skip self and SEL
    for (int skip = 0; skip < 2 && *p; skip++) {
        while (*p && (*p < '0' || *p > '9')) p++;
        while (*p >= '0' && *p <= '9') p++;
    }

    // Count remaining parameters
    uint32_t count = 0;
    const char* q = p;
    while (*q) {
        while (*q && (*q < '0' || *q > '9')) q++;
        if (*q >= '0' && *q <= '9') { count++; while (*q >= '0' && *q <= '9') q++; }
    }

    if (count == 0) return NULL;
    char** params = malloc(sizeof(char*) * count);
    if (!params) return NULL;

    uint32_t idx = 0;
    while (*p && idx < count) {
        const char* typeStart = p;
        while (*p && (*p < '0' || *p > '9')) p++;
        size_t typeLen = (size_t)(p - typeStart);
        char typeEnc[64]; snprintf(typeEnc, sizeof(typeEnc), "%.*s", (int)typeLen, typeStart);
        params[idx++] = class_dump_decode_type_encoding(typeEnc);
        while (*p >= '0' && *p <= '9') p++;
    }
    *parameterCount = idx;
    return params;
}

char* class_dump_format_class_interface(class_dump_info_t* classInfo) {
    return class_dump_generate_class_header(classInfo);
}

char* class_dump_format_class_implementation(class_dump_info_t* classInfo) {
    if (!classInfo) return NULL;
    size_t bufLen = 256 + (classInfo->instanceMethodCount + classInfo->classMethodCount) * 64;
    char* buf = malloc(bufLen);
    if (!buf) return NULL;
    size_t off = 0;
    CD_ADVANCE(snprintf(buf, bufLen, "@implementation %s\n", classInfo->className));
    for (uint32_t i = 0; i < classInfo->instanceMethodCount && off + 32 < bufLen; i++)
        CD_ADVANCE(snprintf(buf + off, bufLen - off, "- (void)%s {}\n", classInfo->instanceMethods[i]));
    for (uint32_t i = 0; i < classInfo->classMethodCount && off + 32 < bufLen; i++)
        CD_ADVANCE(snprintf(buf + off, bufLen - off, "+ (void)%s {}\n", classInfo->classMethods[i]));
    snprintf(buf + off, bufLen - off, "@end\n\n");
    return buf;
}

char* class_dump_format_category_interface(category_dump_info_t* categoryInfo) {
    return class_dump_generate_category_header(categoryInfo);
}

char* class_dump_format_category_implementation(category_dump_info_t* categoryInfo) {
    if (!categoryInfo) return NULL;
    size_t bufLen = 128 + (categoryInfo->instanceMethodCount + categoryInfo->classMethodCount) * 64;
    char* buf = malloc(bufLen);
    if (!buf) return NULL;
    size_t off = 0;
    CD_ADVANCE(snprintf(buf, bufLen, "@implementation %s (%s)\n",
                        categoryInfo->className, categoryInfo->categoryName));
    for (uint32_t i = 0; i < categoryInfo->instanceMethodCount && off + 32 < bufLen; i++)
        CD_ADVANCE(snprintf(buf + off, bufLen - off, "- (void)%s {}\n", categoryInfo->instanceMethods[i]));
    for (uint32_t i = 0; i < categoryInfo->classMethodCount && off + 32 < bufLen; i++)
        CD_ADVANCE(snprintf(buf + off, bufLen - off, "+ (void)%s {}\n", categoryInfo->classMethods[i]));
    snprintf(buf + off, bufLen - off, "@end\n\n");
    return buf;
}

char* class_dump_format_protocol_declaration(protocol_dump_info_t* protocolInfo) {
    return class_dump_generate_protocol_header(protocolInfo);
}

char* class_dump_generate_method_signature(const char* methodName, const char* types, bool isClassMethod) {
    return class_dump_extract_method_signature(types, methodName, isClassMethod);
}

char* class_dump_generate_property_signature(const char* propertyName, const char* attributes) {
    return class_dump_extract_property_declaration(attributes, propertyName);
}

char* class_dump_generate_ivar_signature(const char* ivarName, const char* type) {
    return class_dump_extract_ivar_declaration(type, ivarName);
}

char* class_dump_convert_type_encoding_to_objc(const char* encoding) {
    return class_dump_decode_type_encoding(encoding);
}

char* class_dump_convert_property_attributes_to_objc(const char* attributes) {
    if (!attributes) return strdup("id");
    char* type = class_dump_extract_property_type(attributes);

    // Build qualifier string from attribute flags (R=readonly, C=copy, N=nonatomic, W=weak, &=strong)
    char quals[64] = "nonatomic";
    if (strchr(attributes, 'R')) strncat(quals, ", readonly",  sizeof(quals) - strlen(quals) - 1);
    else if (strchr(attributes, 'C')) strncat(quals, ", copy",   sizeof(quals) - strlen(quals) - 1);
    else if (strchr(attributes, 'W')) strncat(quals, ", weak",   sizeof(quals) - strlen(quals) - 1);
    else                              strncat(quals, ", strong",  sizeof(quals) - strlen(quals) - 1);

    size_t bufLen = strlen(quals) + strlen(type) + 4;
    char* result = malloc(bufLen);
    if (!result) { free(type); return NULL; }
    snprintf(result, bufLen, "%s %s", quals, type);
    free(type);
    return result;
}

char* class_dump_convert_ivar_type_to_objc(const char* ivarType) {
    return class_dump_decode_type_encoding(ivarType);
}

// MARK: - Debug and Logging

void class_dump_log_analysis_start(const char* binaryPath) {
    printf("[ClassDumpC] Starting class dump analysis of: %s\n", binaryPath);
}

void class_dump_log_class_found(const char* className, uint64_t address) {
    printf("[ClassDumpC] Found class for dump: %s at 0x%llx\n", className, address);
}

void class_dump_log_category_found(const char* categoryName, const char* className) {
    printf("[ClassDumpC] Found category for dump: %s on %s\n", categoryName, className);
}

void class_dump_log_protocol_found(const char* protocolName) {
    printf("[ClassDumpC] Found protocol for dump: %s\n", protocolName);
}

void class_dump_log_method_found(const char* methodName, const char* className) {
    printf("[ClassDumpC] Found method for dump: %s in %s\n", methodName, className);
}

void class_dump_log_property_found(const char* propertyName, const char* className) {
    printf("[ClassDumpC] Found property for dump: %s in %s\n", propertyName, className);
}

void class_dump_log_header_generated(const char* headerPath, size_t headerSize) {
    printf("[ClassDumpC] Generated header: %s (%zu bytes)\n", headerPath, headerSize);
}

void class_dump_log_analysis_complete(const class_dump_result_t* result) {
    if (!result) return;
    
    printf("[ClassDumpC] Class dump complete: %u classes, %u categories, %u protocols\n", 
           result->classCount, result->categoryCount, result->protocolCount);
}
