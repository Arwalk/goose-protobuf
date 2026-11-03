// Unit tests for pb_skip_field and pb_append_unknown (gpb-41j.2).
// Run: scripts/goose_tests.sh tests/runtime
import pb_wire from "../../runtime";

var failures = 0;

fn fail_at(what: u8[:], detail: u8[:]) {
    failures += 1;
    print("FAIL ", what, ": ", detail);
}

fn bytes_eq(a: const u8[:], b: const u8[:]) -> bool {
    if a.len != b.len { return false; }
    for i in a.len { if a[i] != b[i] { return false; } }
    return true;
}

// input = one field, then a varint field 15 = 1 as a sentinel. The field
// must be skipped exactly: the sentinel reads back afterwards.
fn check_skip(what: u8[:], field: const u8[:]) {
    var input: u8[>..] = [];
    input.append(field);
    input.push(0x78); input.push(0x01);       // field 15, varint 1
    var r = pb_reader(input);
    let tag = pb_read_tag(r);
    var copied: u8[>..] = [];
    pb_append_unknown(r, 0, tag, copied);
    if r.err != PB_OK { fail_at(what, str("err ", r.err)); return; }
    if r.pos != field.len { fail_at(what, str("stopped at ", r.pos, " want ", field.len)); }
    if !bytes_eq(copied, field) { fail_at(what, str("copied ", copied)); }
    if pb_read_tag(r) != 0x78 || pb_read_varint(r) != 1 { fail_at(what, "sentinel"); }
}

fn check_reject(what: u8[:], input: const u8[:], want_err: i32) {
    var r = pb_reader(input);
    let tag = pb_read_varint(r) as! u32;     // raw: wire types 6/7 must reach skip
    var copied: u8[>..] = [];
    pb_append_unknown(r, 0, tag, copied);
    if r.err != want_err { fail_at(what, str("err ", r.err, " want ", want_err)); }
    if copied.len != 0 { fail_at(what, "copied bytes after an error"); }
}

fn main() {
    // Each wire type.
    let vint: u8[3] = [0x08, 0x96, 0x01];                         // 1: varint 150
    check_skip("varint", vint);
    let i64v: u8[9] = [0x11, 1, 2, 3, 4, 5, 6, 7, 8];               // 2: fixed64
    check_skip("i64", i64v);
    let len: u8[5] = [0x1a, 0x03, 0x61, 0x62, 0x63];                // 3: "abc"
    check_skip("len", len);
    let empty_len: u8[2] = [0x1a, 0x00];
    check_skip("empty len", empty_len);
    let i32v: u8[5] = [0x25, 1, 2, 3, 4];                           // 4: fixed32
    check_skip("i32", i32v);
    // 5: group { 1: varint 1, 6: group { 2: "x" }, 3: fixed32 }
    let group: u8[16] = [0x2b, 0x08, 0x01, 0x33, 0x12, 0x01, 0x78, 0x34,
                         0x1d, 1, 2, 3, 4, 0x2c, 0, 0];
    check_skip("nested group", group[..14]);
    let empty_group: u8[2] = [0x2b, 0x2c];
    check_skip("empty group", empty_group);

    // Rejections.
    let mismatched: u8[2] = [0x2b, 0x34];                           // start 5, end 6
    check_reject("mismatched end group", mismatched, PB_ERR_MALFORMED);
    let lone_end: u8[1] = [0x2c];
    check_reject("end group without start", lone_end, PB_ERR_MALFORMED);
    let wt6: u8[2] = [0x0e, 0x00];
    check_reject("wire type 6", wt6, PB_ERR_MALFORMED);
    let wt7: u8[2] = [0x0f, 0x00];
    check_reject("wire type 7", wt7, PB_ERR_MALFORMED);
    let open_group: u8[3] = [0x2b, 0x08, 0x01];
    check_reject("unterminated group", open_group, PB_ERR_TRUNCATED);
    let overflow: u8[4] = [0x1a, 0x05, 0x61, 0x62];
    check_reject("length past the buffer", overflow, PB_ERR_TRUNCATED);
    let short64: u8[5] = [0x11, 1, 2, 3, 4];
    check_reject("truncated i64", short64, PB_ERR_TRUNCATED);
    let short32: u8[3] = [0x25, 1, 2];
    check_reject("truncated i32", short32, PB_ERR_TRUNCATED);

    // A length past the window is rejected even when the buffer has more.
    let windowed: u8[6] = [0x1a, 0x03, 0x61, 0x62, 0x63, 0x64];
    var rw = pb_reader(windowed);
    rw.end = 4;
    pb_skip_field(rw, pb_read_tag(rw));
    if rw.err != PB_ERR_TRUNCATED { fail_at("length past the window", str(rw.err)); }

    // Nesting: PB_MAX_DEPTH groups are fine, one more is rejected.
    for extra in 2 {
        let depth = PB_MAX_DEPTH + extra;
        var deep: u8[>..] = [];
        for i in depth { deep.push(0x0b); }               // field 1, start group
        for i in depth { deep.push(0x0c); }               // field 1, end group
        var rd = pb_reader(deep);
        pb_skip_field(rd, pb_read_tag(rd));
        let want = if extra == 0 { PB_OK } else { PB_ERR_DEPTH };
        if rd.err != want { fail_at("group depth", str(depth, " groups: err ", rd.err)); }
    }

    // The group limit counts message nesting already in the reader.
    var nested: u8[>..] = [0x0b, 0x0c];
    var rn = pb_reader(nested);
    rn.depth = PB_MAX_DEPTH;
    pb_skip_field(rn, pb_read_tag(rn));
    if rn.err != PB_ERR_DEPTH { fail_at("group inside deep message", str(rn.err)); }

    if failures != 0 { abort(str(failures, " failures")); }
    print("pb_wire skip tests: all passed");
}
