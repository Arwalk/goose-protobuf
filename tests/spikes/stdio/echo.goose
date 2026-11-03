// Spike gpb-wof.3: echo length-prefixed frames, the conformance framing.
// Each frame is a 4-byte little-endian length and then that many bytes;
// the echo writes the same frame back and flushes before reading the next.
// stdio.c (linked by echo.build) does the exact-length reads.
// See docs/decisions/0003-stdio.md.
// Run: goose tests/spikes/stdio/echo.goose [--debug]
//      python3 tests/spikes/stdio/driver.py goose tests/spikes/stdio/echo.goose

import os;

extern "pbio_read_exact" fn read_exact(out: u8[>..]&, n: i64) -> i32;

fn main() {
    var head: u8[>..] = [];
    var frame: u8[>..] = [];
    loop {
        head.clear();
        let h = read_exact(head, 4);
        if h == 1 { exit(0); }                    // clean EOF between frames
        if h != 0 { write_stderr("echo: short read in length\n"); exit(1); }
        var len: u64 = 0;
        for i in 4 { len |= (head[i] as u64) << (8 * i) as u64; }

        // One buffer, one write: the prefix, then the payload after it.
        frame.clear();
        frame.append(head);
        let p = read_exact(frame, len as! i64);
        if p != 0 { write_stderr("echo: short read in payload\n"); exit(1); }
        write_stdout(frame);
        flush_stdout();
    }
}
