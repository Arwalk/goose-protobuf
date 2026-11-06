// A run must not start past 2^32 in its pool, where its position would wrap and it
// would overwrite another run. scripts/test_pool_limit.sh expects this to abort, and
// builds it with a larger data stack, as the default ends the program long before.
import pb_wire;

fn main() {
    let first = pb_resize(pb_bytes, pb_Span { at: 0, len: 0 }, (1 << 32) - 1);
    pb_run(pb_bytes, first)[0] = 65;
    let second = pb_resize(pb_bytes, pb_Span { at: 0, len: 0 }, 16);
    let third = pb_resize(pb_bytes, pb_Span { at: 0, len: 0 }, 16);
    pb_run(pb_bytes, third)[0] = 66;
    print("first starts with ", pb_run(pb_bytes, first)[0], ", second at ", second.at, ", third at ", third.at);
}
