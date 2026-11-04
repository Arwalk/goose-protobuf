/* libFuzzer entry point for fuzz_target.goose; see scripts/fuzz.sh. */
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include "fuzz.h"

/* The Goose runtime ends a failed check or abort() with _Exit, which libFuzzer
   does not see: it would save no input. scripts/fuzz.sh builds with
   -D_Exit=fuzz_exit, so that it comes here and is a crash. */
void fuzz_exit(int code) {
    (void)code;
    abort();
}

int LLVMFuzzerInitialize(int *argc, char ***argv) {
    goose_init(*argc, *argv);
    return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    sl_u8 input = { (uint8_t *)data, (int64_t)size };
    fuzz_one(input);
    return 0;
}
