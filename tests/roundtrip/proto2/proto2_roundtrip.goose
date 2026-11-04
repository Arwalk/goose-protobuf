// Round-trip test for tests/protos/proto2.proto (gpb-6xy.1).
// Run: scripts/roundtrip.sh proto2
import pb_wire;
import proto2;

var failures = 0;

fn fail_at(what: u8[:], detail: u8[:]) {
    failures += 1;
    print("FAIL ", what, ": ", detail);
}

// built encodes to want (protoc's bytes), and want decodes and re-encodes to
// itself, with what it set and nothing else, and leaves nothing unknown.
fn check_case(name: u8[:], want: const u8[:], built: p2::Pres&) {
    var out: u8[>..] = [];
    p2::Pres_encode(built, out);
    if out != want { fail_at(name, "encoding differs from protoc"); }
    if p2::Pres_size_of(built) != want.len { fail_at(name, "size_of"); }
    var back = p2::Pres { .. };
    if p2::Pres_decode(want, back) != PB_OK { fail_at(name, "decode"); }
    if back.pb_unknown.len != 0 { fail_at(name, "kept as unknown fields"); }
    if back.pb_has0 != built.pb_has0 { fail_at(name, "has-bits differ"); }
    var again: u8[>..] = [];
    p2::Pres_encode(back, again);
    if again != want { fail_at(name, "re-encoding differs"); }
    p2::Pres_clear(back);
    if back.pb_has0 != 0 || p2::Pres_size_of(back) != 0 { fail_at(name, "clear left fields set"); }
}

fn set_all(m: p2::Pres&, s: const u8[:], b: const u8[:]) {
    p2::Pres_set_o_string(m, s);
    p2::Pres_set_o_bytes(m, b);
}

fn main() {
    // Unset: nothing is encoded.
    var m = p2::Pres { .. };
    check_case("unset", embed_file("unset.bin"), m);

    // Set to the default: everything is encoded, and each has_ says so.
    p2::Pres_set_o_int32(m, 0);
    if !p2::Pres_has_o_int32(m) || p2::Pres_has_o_int64(m) { fail_at("defaults", "has_"); }
    p2::Pres_set_o_int64(m, 0);
    p2::Pres_set_o_uint32(m, 0);
    p2::Pres_set_o_uint64(m, 0);
    p2::Pres_set_o_sint32(m, 0);
    p2::Pres_set_o_sint64(m, 0);
    p2::Pres_set_o_fixed32(m, 0);
    p2::Pres_set_o_fixed64(m, 0);
    p2::Pres_set_o_sfixed32(m, 0);
    p2::Pres_set_o_sfixed64(m, 0);
    p2::Pres_set_o_float(m, 0.0);
    p2::Pres_set_o_double(m, 0.0);
    p2::Pres_set_o_bool(m, false);
    set_all(m, "", "");
    p2::Pres_mutable_o_sub(m);
    check_case("defaults", embed_file("defaults.bin"), m);

    // clear_ drops one field, value and has-bit.
    p2::Pres_clear_o_bytes(m);
    if p2::Pres_has_o_bytes(m) { fail_at("clear_", "has_"); }
    p2::Pres_clear(m);

    p2::Pres_set_o_int32(m, -1);
    p2::Pres_set_o_int64(m, -2);
    p2::Pres_set_o_uint32(m, 3);
    p2::Pres_set_o_uint64(m, 4);
    p2::Pres_set_o_sint32(m, -5);
    p2::Pres_set_o_sint64(m, -6);
    p2::Pres_set_o_fixed32(m, 7);
    p2::Pres_set_o_fixed64(m, 8);
    p2::Pres_set_o_sfixed32(m, -9);
    p2::Pres_set_o_sfixed64(m, -10);
    p2::Pres_set_o_float(m, 1.5);
    p2::Pres_set_o_double(m, 2.5);
    p2::Pres_set_o_bool(m, true);
    let ff: u8[1] = [0xff];
    set_all(m, "s", ff);
    let sub .= p2::Pres_mutable_o_sub(m);
    p2::Sub_set_a(sub, 1);
    p2::Sub_set_a(p2::Sub_mutable_next(sub), 0);
    check_case("values", embed_file("values.bin"), m);

    // A required field is stored like the others, and set to its default encodes.
    var q = p2::Req { .. };
    p2::Req_set_r_int32(q, 0);
    p2::Req_set_r_string(q, "");
    if !p2::Req_has_r_int32(q) { fail_at("req", "has_"); }
    var qo: u8[>..] = [];
    p2::Req_encode(q, qo);
    if qo != embed_file("req.bin") { fail_at("req", "encoding differs from protoc"); }
    p2::Req_clear(q);

    // A deep copy keeps presence.
    var c = p2::Pres { .. };
    p2::Pres_copy(c, m);
    p2::Pres_clear(m);
    var co: u8[>..] = [];
    p2::Pres_encode(c, co);
    if co != embed_file("values.bin") { fail_at("copy", "encoding differs"); }
    p2::Pres_clear(c);

    // A proto2 string is not validated (field 14, tag 0x72), unlike proto3's.
    let bad: u8[3] = [0x72, 1, 0xff];
    if p2::Pres_decode(bad, m) != PB_OK { fail_at("utf8", "rejected"); }
    if p2::Pres_o_string(m)[0] != 0xff { fail_at("utf8", "value"); }
    p2::Pres_clear(m);

    // A field with another wire type is unknown, and does not set has_.
    let wrong: u8[5] = [0x0d, 1, 2, 3, 4];
    if p2::Pres_decode(wrong, m) != PB_OK || p2::Pres_has_o_int32(m) || m.pb_unknown.len != 5 {
        fail_at("wire type", "not kept unknown");
    }
    p2::Pres_clear(m);

    // Later: all is stored but the extension, which stays on the wire.
    let later = embed_file("later.bin");
    var l = p2::Later { .. };
    if p2::Later_decode(later, l) != PB_OK { fail_at("later", "decode"); }
    if !p2::Later_has_stored(l) || l.stored != 1 { fail_at("later", "stored"); }
    if !p2::Later_has_mode(l) || l.mode != p2::Mode_MODE_B { fail_at("later", "mode"); }
    if p2::Later_list_at(l, 0) != 2 || !p2::Later_has_member(l) { fail_at("later", "list, member"); }
    let lc, lf = p2::Later_counts_get(l, "k");
    if !lf || lc != 4 { fail_at("later", "counts"); }
    if !p2::Later_has_grp(l) { fail_at("later", "group"); }
    // [p2.ext]: 6 is 3 bytes.
    if l.pb_unknown.len != 3 { fail_at("later", str("unknown bytes ", l.pb_unknown.len, " of ", later.len)); }
    var lo: u8[>..] = [];
    p2::Later_encode(l, lo);
    if lo != later { fail_at("later", "re-encoding differs"); }
    p2::Later_clear(l);

    if failures > 0 { abort(str(failures, " failures")); }
    print("ok");
}
