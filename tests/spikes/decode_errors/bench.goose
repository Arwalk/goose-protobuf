// Shared benchmark for the variants: `<variant> bench` decodes a root Node
// with 200000 children (id varints and a name) 20 times. Each variant
// defines decode(buf, pool) -> i32.
import os;

fn bench_input(out: u8[>..]&) {
    out.resize(0);
    for i in 200000 {
        // child: id = 150 (twice; last one wins), name = "abc"
        let child: u8[11] = [0x08, 0x96, 0x01, 0x08, 0x96, 0x01, 0x1a, 0x03, 0x61, 0x62, 0x63];
        out.push(0x12);
        out.push(11);
        out.append(child);
    }
}

fn bench(name: u8[:]) {
    var buf: u8[>..] = [];
    bench_input(buf);
    var pool: Node[>..] = [];
    let t0 = clock();
    var total: i64 = 0;
    for rep in 20 {
        pool.resize(0);
        let err = decode(buf, pool);
        if err != 0 { abort("bench decode failed"); }
        total += pool.len;
    }
    let dt = clock() - t0;
    print(name, ": ", total, " nodes, ", buf.len * 20 / 1000000, " MB in ", dt, " s");
}

fn bench_requested() -> bool {
    return args().len > 1;
}
