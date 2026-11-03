// Unit tests for pb_utf8_valid and the string/bytes helpers (gpb-8qn.4).
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

fn want_valid(name: u8[:], b: const u8[:], want: bool) {
    if pb_utf8_valid(b) != want { fail_at(name, str("want ", want)); }
}

fn test_utf8() {
    want_valid("empty", "", true);
    want_valid("ASCII", "hello", true);
    let two: u8[2] = [0xc3, 0xa9];               // U+00E9
    let three: u8[3] = [0xe2, 0x82, 0xac];       // U+20AC
    let four: u8[4] = [0xf0, 0x9f, 0x98, 0x80];  // U+1F600
    let max: u8[4] = [0xf4, 0x8f, 0xbf, 0xbf];   // U+10FFFF
    let edges: u8[6] = [0xed, 0x9f, 0xbf, 0xee, 0x80, 0x80];   // U+D7FF, U+E000
    want_valid("2-byte", two, true);
    want_valid("3-byte", three, true);
    want_valid("4-byte", four, true);
    want_valid("U+10FFFF", max, true);
    want_valid("around the surrogates", edges, true);

    let over2: u8[2] = [0xc0, 0x80];             // overlong U+0000
    let over2b: u8[2] = [0xc1, 0xbf];
    let over3: u8[3] = [0xe0, 0x80, 0x80];
    let over3b: u8[3] = [0xe0, 0x9f, 0xbf];      // overlong U+07FF
    let over4: u8[4] = [0xf0, 0x8f, 0xbf, 0xbf]; // overlong U+FFFF
    want_valid("overlong 2-byte", over2, false);
    want_valid("overlong 2-byte C1", over2b, false);
    want_valid("overlong 3-byte", over3, false);
    want_valid("overlong 3-byte U+07FF", over3b, false);
    want_valid("overlong 4-byte", over4, false);

    let sur_lo: u8[3] = [0xed, 0xa0, 0x80];      // U+D800
    let sur_hi: u8[3] = [0xed, 0xbf, 0xbf];      // U+DFFF
    want_valid("surrogate D800", sur_lo, false);
    want_valid("surrogate DFFF", sur_hi, false);

    let big: u8[4] = [0xf4, 0x90, 0x80, 0x80];   // U+110000
    let f5: u8[4] = [0xf5, 0x80, 0x80, 0x80];
    let ff: u8[1] = [0xff];
    want_valid("above U+10FFFF", big, false);
    want_valid("F5 lead", f5, false);
    want_valid("FF", ff, false);

    let cut2: u8[1] = [0xc3];
    let cut3: u8[3] = [0x61, 0xe2, 0x82];
    let cut4: u8[3] = [0xf0, 0x9f, 0x98];
    let lone: u8[2] = [0x61, 0x80];
    let badcont: u8[3] = [0xe2, 0x28, 0xa1];
    want_valid("truncated 2-byte", cut2, false);
    want_valid("truncated 3-byte", cut3, false);
    want_valid("truncated 4-byte", cut4, false);
    want_valid("lone continuation", lone, false);
    want_valid("bad continuation", badcont, false);
}

fn test_bytes() {
    // pb_read_bytes / pb_read_string: the last value wins, failures keep
    // the old value, invalid UTF-8 is PB_ERR_UTF8 for strings only.
    let wire: u8[8] = [0x03, 0x61, 0x62, 0x63, 0x02, 0xc0, 0x80, 0x05];
    var r = pb_reader(wire);
    var s = pb_read_bytes(r, pb_Span { at: 0, len: 0 });
    if !bytes_eq(pb_run(pb_bytes, s), "abc") { fail_at("read bytes", pb_run(pb_bytes, s)); }
    let at_overlong = r.pos;
    s = pb_read_bytes(r, s);
    if s.len != 2 || r.err != PB_OK { fail_at("bytes are not validated", str(r.err)); }
    var rs = pb_reader(wire);
    var t = pb_read_string(rs, pb_Span { at: 0, len: 0 });
    t = pb_read_string(rs, t);
    if rs.err != PB_ERR_UTF8 || !bytes_eq(pb_run(pb_bytes, t), "abc") {
        fail_at("invalid string", str(rs.err, " pos ", at_overlong));
    }
    var rt = pb_reader(wire[7..8]);   // length 5, nothing follows
    let u = pb_read_bytes(rt, s);
    if rt.err != PB_ERR_TRUNCATED || u.at != s.at || u.len != s.len { fail_at("truncated bytes", str(rt.err)); }

    // Encoding and sizes.
    var out: u8[>..] = [];
    pb_write_bytes(out, t);
    let want: u8[4] = [0x03, 0x61, 0x62, 0x63];
    if !bytes_eq(out, want) || pb_bytes_size(t) != 4 { fail_at("write bytes", ""); }

    // pb_bytes_set may copy from pb_bytes, even from the run it replaces.
    t = pb_bytes_set(t, pb_run(pb_bytes, t)[1..3]);
    if !bytes_eq(pb_run(pb_bytes, t), "bc") { fail_at("set from itself", pb_run(pb_bytes, t)); }
    t = pb_bytes_set(t, pb_run(pb_bytes, s));
    if !bytes_eq(pb_run(pb_bytes, t), pb_run(pb_bytes, s)) { fail_at("set from another run", ""); }
    t = pb_bytes_set(t, "");
    if t.len != 0 { fail_at("set empty", str(t.len)); }
    s = pb_bytes_free(s);
}

fn main() {
    test_utf8();
    test_bytes();
    if failures != 0 { abort(str(failures, " failures")); }
    print("pb_wire utf8 tests: all passed");
}
