// Round-trip test for tests/protos/strings.proto (gpb-8qn.4).
// Run: scripts/roundtrip.sh strings
import pb_wire;
import strings;

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

fn hex(b: const u8[:]) -> u8[>..] {
    let digits = "0123456789abcdef";
    var s: u8[>..] = [];
    for i in b.len {
        if i > 0 { s.push(32); }
        s.push(digits[(b[i] >> 4) as i64]);
        s.push(digits[(b[i] & 15) as i64]);
    }
    return s;
}

fn same(a: strings::Text&, b: strings::Text&) -> bool {
    return bytes_eq(strings::Text_s(a), strings::Text_s(b))
        && bytes_eq(strings::Text_b(a), strings::Text_b(b))
        && bytes_eq(strings::Text_os(a), strings::Text_os(b))
        && bytes_eq(strings::Text_ob(a), strings::Text_ob(b))
        && strings::Text_has_os(a) == strings::Text_has_os(b)
        && strings::Text_has_ob(a) == strings::Text_has_ob(b)
        && a.n == b.n;
}

// built encodes to want (protoc's bytes); want decodes to built and
// re-encodes to want.
fn check_case(name: u8[:], want: const u8[:], built: strings::Text&) {
    var out: u8[>..] = [];
    strings::Text_encode(built, out);
    if !bytes_eq(out, want) { fail_at(name, str("encode [", hex(out), "] want [", hex(want), "]")); }
    if strings::Text_size_of(built) != want.len { fail_at(name, str("size_of ", strings::Text_size_of(built))); }
    var back = strings::Text { .. };
    let err = strings::Text_decode(want, back);
    if err != PB_OK { fail_at(name, str("decode error ", err)); return; }
    if !same(back, built) { fail_at(name, "decoded message differs from the built one"); }
    var again: u8[>..] = [];
    strings::Text_encode(back, again);
    if !bytes_eq(again, want) { fail_at(name, str("re-encode [", hex(again), "]")); }
    // Decoding again replaces each string: the last value wins.
    strings::Text_decode(want, back);
    if !same(back, built) { fail_at(name, "decoding twice changed the message"); }
    strings::Text_clear(back);
    if strings::Text_size_of(back) != 0 || back.s.len != 0 || back.pb_has0 != 0 {
        fail_at(name, "clear left fields set");
    }
}

fn main() {
    var ascii = strings::Text { .. };
    strings::Text_set_s(ascii, "hello");
    let bin: u8[9] = [0x00, 0xff, 0x80, 0x62, 0x69, 0x6e, 0x61, 0x72, 0x79];
    strings::Text_set_b(ascii, bin);
    ascii.n = 3;
    check_case("ascii", embed_file("ascii.bin"), ascii);

    var multi = strings::Text { .. };
    strings::Text_set_s(multi, "héllo € 😀");
    strings::Text_set_os(multi, "中");
    check_case("multibyte", embed_file("multibyte.bin"), multi);

    var empty = strings::Text { .. };
    strings::Text_set_s(empty, "");
    strings::Text_set_b(empty, "");
    strings::Text_set_os(empty, "");
    strings::Text_set_ob(empty, "");
    check_case("empty", embed_file("empty.bin"), empty);
    let empty_bin = embed_file("empty.bin");
    let want_empty: u8[4] = [0x1a, 0x00, 0x22, 0x00];   // only os and ob
    if !bytes_eq(empty_bin, want_empty) { fail_at("empty", str("protoc [", hex(empty_bin), "]")); }

    // Invalid UTF-8 in a string is a decode error; in bytes it is data.
    var bad = strings::Text { .. };
    let bad_s: u8[4] = [0x0a, 0x02, 0xc0, 0x80];
    if strings::Text_decode(bad_s, bad) != PB_ERR_UTF8 { fail_at("invalid string", "decoded"); }
    let bad_os: u8[5] = [0x1a, 0x03, 0xed, 0xa0, 0x80];   // a surrogate
    if strings::Text_decode(bad_os, bad) != PB_ERR_UTF8 { fail_at("invalid optional string", "decoded"); }
    strings::Text_clear(bad);
    let bad_b: u8[4] = [0x12, 0x02, 0xc0, 0x80];
    if strings::Text_decode(bad_b, bad) != PB_OK || strings::Text_b(bad).len != 2 {
        fail_at("bytes", "invalid UTF-8 in bytes was rejected");
    }
    strings::Text_clear(bad);

    // Setting a field from its own contents.
    var self_set = strings::Text { .. };
    strings::Text_set_s(self_set, "abcdef");
    strings::Text_set_s(self_set, strings::Text_s(self_set)[2..4]);
    if !bytes_eq(strings::Text_s(self_set), "cd") { fail_at("self set", strings::Text_s(self_set)); }
    strings::Text_clear(self_set);

    strings::Text_clear(ascii);
    strings::Text_clear(multi);
    strings::Text_clear(empty);
    if failures != 0 { abort(str(failures, " failures")); }
    print("strings round-trip: all passed");
}
