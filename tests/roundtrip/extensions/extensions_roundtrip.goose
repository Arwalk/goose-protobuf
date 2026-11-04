// Round-trip test for tests/protos/extensions.proto (gpb-6xy.6).
// Run: scripts/roundtrip.sh extensions
import pb_wire;
import extensions;

var failures = 0;

fn fail_at(what: u8[:], detail: u8[:]) {
    failures += 1;
    print("FAIL ", what, ": ", detail);
}

fn encoded(m: ext::Target&) -> u8[>..] {
    var out: u8[>..] = [];
    ext::Target_encode(m, out);
    if ext::Target_size_of(m) != out.len { fail_at("encoded", "size_of"); }
    return out;
}

fn main() {
    // protoc writes `stored` first, then the extensions in field order.
    let all = embed_file("all.bin");
    var m = ext::Target { .. };
    if ext::Target_decode(all, m) != PB_OK { fail_at("all", "decode"); }
    if !ext::Target_has_stored(m) || m.stored != 1 { fail_at("all", "stored"); }
    if m.pb_unknown.len != all.len - 2 { fail_at("all", "unknown"); }
    if encoded(m) != all { fail_at("all", "re-encoding differs"); }

    // A deep copy, and through a message that holds one.
    var c = ext::Target { .. };
    ext::Target_copy(c, m);
    ext::Target_clear(m);
    if encoded(c) != all { fail_at("all", "copy differs"); }
    ext::Target_clear(c);
    if ext::Target_size_of(c) != 0 { fail_at("all", "clear"); }

    var wrapped: u8[>..] = [];
    wrapped.push(0x0a);
    pb_write_varint(wrapped, all.len as! u64);
    wrapped.append(all);
    var h = ext::Holder { .. };
    if ext::Holder_decode(wrapped, h) != PB_OK { fail_at("holder", "decode"); }
    var ho: u8[>..] = [];
    ext::Holder_encode(h, ho);
    if ho != wrapped { fail_at("holder", "re-encoding differs"); }
    ext::Holder_clear(h);

    // Closed enums are not checked on an extension: a value stays as it is, in
    // the extension's bytes. Field 106, tag 0xd0 0x06.
    let bad_enum: u8[3] = [0xd0, 0x06, 9];
    if ext::Target_decode(bad_enum, m) != PB_OK || m.pb_unknown.len != 3 { fail_at("enum", "not kept"); }
    if encoded(m) != bad_enum { fail_at("enum", "re-encoding"); }
    ext::Target_clear(m);

    // A message set item is an unknown group.
    var s = ext::Set { .. };
    let item: u8[8] = [0x0b, 0x10, 4, 0x1a, 1, 0x7f, 0x0c, 0x10];
    if ext::Set_decode(item[0..7], s) != PB_OK || s.pb_unknown.len != 7 { fail_at("set", "not kept"); }
    var so: u8[>..] = [];
    ext::Set_encode(s, so);
    if so != item[0..7] { fail_at("set", "re-encoding"); }
    ext::Set_clear(s);

    if failures > 0 { abort(str(failures, " failures")); }
    print("ok");
}
