/* Spike gpb-wof.3: exact-length stdin reads for the conformance protocol.
   os.read_stdin reads to EOF and os.read_line stops at '\n', so neither
   can read one length-prefixed frame and return. This reads exactly n
   bytes from fd 0 with read(2), appending them to a Goose builder. */
#include "goose.h"
#include <errno.h>
#include <stdint.h>
#include <unistd.h>

/* extern "pbio_read_exact" fn read_exact(out: u8[>..]&, n: i64) -> i32;
   0: all n bytes appended. 1: clean EOF before the first byte.
   -1: EOF partway through (short read), a read error, or n < 0. */
int32_t pbio_read_exact(gs_rref out, int64_t n) {
    uint8_t buf[65536];
    int64_t got = 0;
    if (n < 0) return -1;
    while (got < n) {
        int64_t want = n - got;
        if (want > (int64_t)sizeof buf) want = (int64_t)sizeof buf;
        ssize_t r = read(0, buf, (size_t)want);
        if (r < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (r == 0) return got == 0 ? 1 : -1;
        gs_bld_append(out, buf, (int64_t)r);
        got += r;
    }
    return 0;
}
