// Round-trip test for tests/protos/editions_2026.proto: what edition 2026 adds does
// not change the wire format, and each edition 2023 feature still applies.
// Run: scripts/roundtrip.sh editions_2026
import pb_wire;
import editions_2026;

var failures = 0;

fn fail_at(what: u8[:]) {
    failures += 1;
    print("FAIL ", what);
}

fn check_all() {
    let data = embed_file("all.bin");
    var m = ed26::Book { .. };
    if ed26::Book_decode(data, m) != PB_OK { fail_at("decode"); return; }
    if ed26::Book_title(m) != "Emma" { fail_at("title"); }
    if !ed26::Book_has_explicit_field(m) { fail_at("explicit presence is kept at 0"); }
    if m.implicit_field != 3 { fail_at("implicit field"); }
    if m.color != ed26::Color_COLOR_RED { fail_at("open enum"); }
    if m.closed != ed26::Closed_CLOSED_ONE { fail_at("closed enum"); }
    if ed26::Book_packed_values(m).len != 2 { fail_at("packed"); }
    if ed26::Book_expanded_values(m)[1] != 4 { fail_at("expanded"); }
    let v, found = ed26::Book_counts_get(m, "a");
    if !found || v != 5 { fail_at("map"); }
    if ed26::Book_word(m) != "w" { fail_at("oneof"); }
    var out: u8[>..] = [];
    ed26::Book_encode(m, out);
    if out != data { fail_at("encoding is not what protoc wrote"); }
    ed26::Book_clear(m);
}

fn check_delimited_is_a_group() {
    // Field 12, delimited: start group, field 1 = 2, end group.
    let want: u8[4] = [0x63, 0x08, 2, 0x64];
    var m = ed26::Book { .. };
    ed26::Book_Inner_set_i(ed26::Book_mutable_delimited_inner(m), 2);
    var out: u8[>..] = [];
    ed26::Book_encode(m, out);
    if out != want { fail_at("delimited encoding"); }
    ed26::Book_clear(m);
}

fn check_implicit_zero_is_not_written() {
    var m = ed26::Book { .. };
    m.implicit_field = 0;
    if ed26::Book_size_of(m) != 0 { fail_at("implicit zero"); }
    ed26::Book_clear(m);
}

fn main() {
    check_all();
    check_delimited_is_a_group();
    check_implicit_zero_is_not_written();
    if failures > 0 { abort("editions_2026 failed"); }
}
