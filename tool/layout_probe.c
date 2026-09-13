// Emits the real offsets and sizes of the platform's filesystem-statistics
// struct as JSON, so tool/check_layout.dart can verify lib/src/platform_layout.dart
// against the actual system headers.
//
// Darwin deliberately probes `struct statfs`, not `struct statvfs`: Darwin's
// fsblkcnt_t is a 32-bit unsigned int (counts wrap above 16 TiB) and its
// statvfs f_bsize is a 1 MiB I/O hint rather than a block size.
#include <stdio.h>
#include <stddef.h>

#if defined(__APPLE__)
#include <sys/mount.h>
#define STRUCT_NAME "statfs"
typedef struct statfs fs_struct_t;
#define UNIT_FIELD f_bsize
#else
#include <sys/statvfs.h>
#define STRUCT_NAME "statvfs"
typedef struct statvfs fs_struct_t;
#define UNIT_FIELD f_frsize
#endif

int main(void) {
    printf("{\n");
    printf("  \"struct\": \"%s\",\n", STRUCT_NAME);
    printf("  \"pointerSize\": %zu,\n", sizeof(void *));
    printf("  \"structSize\": %zu,\n", sizeof(fs_struct_t));
    printf("  \"unitOffset\": %zu,\n", offsetof(fs_struct_t, UNIT_FIELD));
    printf("  \"unitSize\": %zu,\n", sizeof(((fs_struct_t *)0)->UNIT_FIELD));
    printf("  \"blocksOffset\": %zu,\n", offsetof(fs_struct_t, f_blocks));
    printf("  \"freeOffset\": %zu,\n", offsetof(fs_struct_t, f_bfree));
    printf("  \"availOffset\": %zu,\n", offsetof(fs_struct_t, f_bavail));
    printf("  \"countSize\": %zu\n", sizeof(((fs_struct_t *)0)->f_blocks));
    printf("}\n");
    return 0;
}
