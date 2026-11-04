// Round-trip test for tests/protos/required.proto (gpb-6xy.4).
// Run: scripts/roundtrip.sh required
import pb_wire;
import required;
import required_p2;

var failures = 0;

fn fail_at(what: u8[:], detail: u8[:]) {
    failures += 1;
    print("FAIL ", what, ": ", detail);
}

// Wire bytes of Inner fields.
let X1: u8[2] = [0x08, 1];                       // x: 1
let NEXT_NO_X: u8[4] = [0x08, 1, 0x12, 0];       // x: 1, next { }
let NEXT_X: u8[6] = [0x08, 1, 0x12, 2, 0x08, 2]; // x: 1, next { x: 2 }
let EMPTY_NEXT: u8[2] = [0x12, 0];               // next { }

fn inner_err(b: const u8[:]) -> i32 {
    var m = req::Inner { .. };
    let e = req::Inner_decode(b, m);
    req::Inner_clear(m);
    return e;
}

fn check_inner() {
    if inner_err(X1) != PB_OK { fail_at("inner", "all present"); }
    if inner_err(EMPTY_NEXT) != PB_ERR_REQUIRED { fail_at("inner", "own field missing"); }
    let none: u8[0] = [];
    if inner_err(none) != PB_ERR_REQUIRED { fail_at("inner", "empty input"); }
    if inner_err(NEXT_NO_X) != PB_ERR_REQUIRED { fail_at("inner", "missing in a nested message"); }
    if inner_err(NEXT_X) != PB_OK { fail_at("inner", "nested present"); }
    // Set to its default, it is present.
    let zero: u8[2] = [0x08, 0];
    if inner_err(zero) != PB_OK { fail_at("inner", "set to the default"); }
    // A malformed input reports that, not the missing field.
    let bad: u8[1] = [0x08];
    if inner_err(bad) != PB_ERR_TRUNCATED { fail_at("inner", "truncated"); }
}

// Each of a, s and inner is required, whichever is missing.
fn check_req() {
    let all: u8[9] = [0x08, 1, 0x12, 1, 0x73, 0x1a, 2, 0x08, 1];
    let no_a: u8[7] = [0x12, 1, 0x73, 0x1a, 2, 0x08, 1];
    let no_s: u8[6] = [0x08, 1, 0x1a, 2, 0x08, 1];
    let no_inner: u8[5] = [0x08, 1, 0x12, 1, 0x73];
    let bad_inner: u8[7] = [0x08, 1, 0x12, 1, 0x73, 0x1a, 0];
    var m = req::Req { .. };
    if req::Req_decode(all, m) != PB_OK { fail_at("req", "all"); }
    if !req::Req_is_initialized(m) { fail_at("req", "is_initialized"); }
    var out: u8[>..] = [];
    req::Req_encode(m, out);
    if out != all { fail_at("req", "re-encoding differs"); }
    req::Req_clear(m);
    if req::Req_is_initialized(m) { fail_at("req", "is_initialized after clear"); }
    if req::Req_decode(no_a, m) != PB_ERR_REQUIRED { fail_at("req", "no a"); }
    req::Req_clear(m);
    if req::Req_decode(no_s, m) != PB_ERR_REQUIRED { fail_at("req", "no s"); }
    req::Req_clear(m);
    if req::Req_decode(no_inner, m) != PB_ERR_REQUIRED { fail_at("req", "no inner"); }
    req::Req_clear(m);
    if req::Req_decode(bad_inner, m) != PB_ERR_REQUIRED { fail_at("req", "inner lacks x"); }
    req::Req_clear(m);

    // On a message built through the API.
    req::Req_set_a(m, 0);
    req::Req_set_s(m, "");
    if req::Req_is_initialized(m) { fail_at("req", "built, without inner"); }
    let i .= req::Req_mutable_inner(m);
    if req::Req_is_initialized(m) { fail_at("req", "built, inner lacks x"); }
    req::Inner_set_x(i, 1);
    if !req::Req_is_initialized(m) { fail_at("req", "built, complete"); }
    req::Req_clear(m);
}

// Merging counts: what one occurrence lacks, a later one may set, so the check
// is on the whole message, once.
fn check_merge() {
    // Holder { i { } i { x: 1 } }: fine, the two merge.
    let merged: u8[6] = [0x0a, 0, 0x0a, 2, 0x08, 1];
    var m = req::Holder { .. };
    if req::Holder_decode(merged, m) != PB_OK { fail_at("merge", "second occurrence sets it"); }
    req::Holder_clear(m);
    let lacking: u8[2] = [0x0a, 0];
    if req::Holder_decode(lacking, m) != PB_ERR_REQUIRED { fail_at("merge", "never set"); }
    req::Holder_clear(m);
    // Across two decodes: the first fails, and the second completes it.
    if req::Holder_decode(lacking, m) != PB_ERR_REQUIRED { fail_at("merge", "first decode"); }
    let rest: u8[4] = [0x0a, 2, 0x08, 1];
    if req::Holder_decode(rest, m) != PB_OK { fail_at("merge", "second decode"); }
    req::Holder_clear(m);
    // An unset field holding a required one is no failure.
    let none: u8[0] = [];
    if req::Holder_decode(none, m) != PB_OK { fail_at("merge", "unset holder field"); }
}

// Through each kind of field, from proto3.
fn check_kinds() {
    var m = holder::Uses { .. };
    let one_ok: u8[4] = [0x0a, 2, 0x08, 1];
    let one_bad: u8[2] = [0x0a, 0];
    let many_bad: u8[6] = [0x12, 2, 0x08, 1, 0x12, 0];
    let map_ok: u8[6] = [0x1a, 4, 0x12, 2, 0x08, 1];
    let map_bad: u8[4] = [0x1a, 2, 0x12, 0];
    let map_absent: u8[2] = [0x1a, 0];
    let member_ok: u8[4] = [0x22, 2, 0x08, 1];
    let member_bad: u8[2] = [0x22, 0];
    let other: u8[2] = [0x28, 1];
    if holder::Uses_decode(one_ok, m) != PB_OK { fail_at("kinds", "singular ok"); }
    holder::Uses_clear(m);
    if holder::Uses_decode(one_bad, m) != PB_ERR_REQUIRED { fail_at("kinds", "singular"); }
    holder::Uses_clear(m);
    if holder::Uses_decode(many_bad, m) != PB_ERR_REQUIRED { fail_at("kinds", "repeated, the second"); }
    holder::Uses_clear(m);
    if holder::Uses_decode(map_ok, m) != PB_OK { fail_at("kinds", "map ok"); }
    holder::Uses_clear(m);
    if holder::Uses_decode(map_bad, m) != PB_ERR_REQUIRED { fail_at("kinds", "map value"); }
    holder::Uses_clear(m);
    // A value that is absent is an empty message, which lacks x.
    if holder::Uses_decode(map_absent, m) != PB_ERR_REQUIRED { fail_at("kinds", "map value absent"); }
    holder::Uses_clear(m);
    // A value that lacks x, replaced by a later entry with its key, does not count.
    var replaced: u8[>..] = [];
    replaced.append(map_bad);
    replaced.append(map_ok);
    if holder::Uses_decode(replaced, m) != PB_OK { fail_at("kinds", "replaced map value"); }
    holder::Uses_clear(m);
    if holder::Uses_decode(member_ok, m) != PB_OK { fail_at("kinds", "member ok"); }
    holder::Uses_clear(m);
    if holder::Uses_decode(member_bad, m) != PB_ERR_REQUIRED { fail_at("kinds", "oneof member"); }
    holder::Uses_clear(m);
    if holder::Uses_decode(other, m) != PB_OK { fail_at("kinds", "another member"); }
    holder::Uses_clear(m);
    // A repeated run with no bad element.
    var two = holder::Uses { .. };
    let i0 .= holder::Uses_add_many(two);
    req::Inner_set_x(i0, 1);
    req::Inner_set_x(holder::Uses_add_many(two), 2);
    if !holder::Uses_is_initialized(two) { fail_at("kinds", "repeated ok"); }
    holder::Uses_add_many(two);
    if holder::Uses_is_initialized(two) { fail_at("kinds", "repeated, a bad one added"); }
    holder::Uses_clear(two);
}

// A required group is stored later: decoding does not fail on what it cannot see.
fn check_not_stored() {
    var m = req::NotStored { .. };
    let none: u8[0] = [];
    if req::NotStored_decode(none, m) != PB_OK { fail_at("not stored", "false failure"); }
    req::NotStored_clear(m);
}

fn main() {
    check_inner();
    check_req();
    check_merge();
    check_kinds();
    check_not_stored();
    if failures > 0 { abort(str(failures, " failures")); }
    print("ok");
}
