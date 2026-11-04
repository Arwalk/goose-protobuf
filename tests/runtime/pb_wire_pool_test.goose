// Unit tests for the pb_bytes pool and pb_Span runs (gpb-41j.6).
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

fn main() {
    // A copy shares nothing with its source, and survives the pool moving.
    var src = pb_bytes_append(pb_Span { at: 0, len: 0 }, "copy me");
    let empty_copy = pb_bytes_copy(pb_Span { at: 0, len: 0 });
    if empty_copy.len != 0 { fail_at("copy empty", "allocated"); }
    var cp = pb_bytes_copy(src);
    if !bytes_eq(pb_run(pb_bytes, cp), "copy me") { fail_at("copy", pb_run(pb_bytes, cp)); }
    if cp.at == src.at { fail_at("copy", "shares the run"); }
    src = pb_bytes_free(src);
    if !bytes_eq(pb_run(pb_bytes, cp), "copy me") { fail_at("copy", "freeing the source changed it"); }
    // Copying when the pool must grow: fill it, then copy a large run.
    var large: u8[>..] = [];
    for i in 100000 { large.push(i as! u8); }
    var big = pb_bytes_append(pb_Span { at: 0, len: 0 }, large);
    let big2 = pb_bytes_copy(big);
    if !bytes_eq(pb_run(pb_bytes, big2), large) { fail_at("copy large", "contents differ"); }
    big = pb_bytes_free(big);
    pb_bytes_free(big2);
    cp = pb_bytes_free(cp);

    var a = pb_Span { at: 0, len: 0 };
    var b = pb_Span { at: 0, len: 0 };
    if pb_run(pb_bytes, a).len != 0 { fail_at("empty", "an empty span has elements"); }
    if pb_bytes_append(a, "").len != 0 { fail_at("append empty", "appending nothing allocated"); }

    // Interleaved growth: each append may move a run past the other.
    a = pb_bytes_append(a, "ab");
    b = pb_bytes_append(b, "xyz");
    a = pb_bytes_append(a, "cde");
    b = pb_bytes_append(b, "w");
    for i in 50 { a = pb_bytes_append(a, "."); }
    if !bytes_eq(pb_run(pb_bytes, b), "xyzw") { fail_at("b", pb_run(pb_bytes, b)); }
    let ra = pb_run(pb_bytes, a);
    if ra.len != 55 || !bytes_eq(ra[0..5], "abcde") || ra[54] != 46 {
        fail_at("a", str("len ", ra.len));
    }

    a = pb_bytes_free(a);
    if a.len != 0 || a.at != 0 { fail_at("free", "the freed span is not empty"); }
    if !bytes_eq(pb_run(pb_bytes, b), "xyzw") { fail_at("b after free", pb_run(pb_bytes, b)); }

    // A shrinking resize keeps the prefix.
    b = pb_resize(pb_bytes, b, 2);
    if !bytes_eq(pb_run(pb_bytes, b), "xy") { fail_at("shrink", pb_run(pb_bytes, b)); }
    b = pb_bytes_free(b);

    // Unknown fields: three fields copied raw, then the slack trimmed.
    // field 1 varint 150; field 2 len "hi"; field 3 group holding field 4
    // varint 1; then field 5 fixed32.
    let wire: u8[17] = [0x08, 0x96, 0x01, 0x12, 0x02, 0x68, 0x69,
                        0x1b, 0x20, 0x01, 0x1c, 0x2d, 1, 2, 3, 4, 0x00];
    var r = pb_reader(wire[0..16]);
    var u = pb_Span { at: 0, len: 0 };
    var used: i64 = 0;
    while r.pos < r.end {
        let start = r.pos;
        let tag = pb_read_tag(r);
        if r.err != PB_OK { break; }
        pb_unknown_append(r, start, tag, u, used);
    }
    if r.err != PB_OK { fail_at("unknown", str("err ", r.err)); }
    u = pb_bytes_trim(u, used);
    if !bytes_eq(pb_run(pb_bytes, u), wire[0..16]) { fail_at("unknown", str("len ", u.len)); }

    // A truncated field appends nothing.
    var t = pb_reader(wire[0..4]);   // field 1, then field 2's tag only
    var tu = pb_Span { at: 0, len: 0 };
    var tused: i64 = 0;
    while t.pos < t.end {
        let start = t.pos;
        let tag = pb_read_tag(t);
        if t.err != PB_OK { break; }
        pb_unknown_append(t, start, tag, tu, tused);
    }
    tu = pb_bytes_trim(tu, tused);
    if t.err != PB_ERR_TRUNCATED || !bytes_eq(pb_run(pb_bytes, tu), wire[0..3]) {
        fail_at("unknown truncated", str("err ", t.err, " len ", tu.len));
    }
    u = pb_bytes_free(u);
    tu = pb_bytes_free(tu);

    // Typed run pools: a run of f64 and a run of spans, grown and freed.
    var fs = pb_resize(pb_f64s, pb_Span { at: 0, len: 0 }, 2);
    pb_run(pb_f64s, fs)[0] = 1.5;
    pb_run(pb_f64s, fs)[1] = -2.0;
    fs = pb_resize(pb_f64s, fs, 3);
    let fr = pb_run(pb_f64s, fs);
    if fr.len != 3 || fr[0] != 1.5 || fr[1] != -2.0 { fail_at("f64s", str(fr.len)); }
    fs = pb_resize(pb_f64s, fs, 0);
    var ss = pb_resize(pb_spans, pb_Span { at: 0, len: 0 }, 1);
    pb_run(pb_spans, ss)[0] = pb_bytes_append(pb_Span { at: 0, len: 0 }, "s");
    if !bytes_eq(pb_run(pb_bytes, pb_run(pb_spans, ss)[0]), "s") { fail_at("spans", ""); }
    pb_bytes_free(pb_run(pb_spans, ss)[0]);
    ss = pb_resize(pb_spans, ss, 0);

    if failures != 0 { abort(str(failures, " failures")); }
    print("pb_wire pool tests: all passed");
}
