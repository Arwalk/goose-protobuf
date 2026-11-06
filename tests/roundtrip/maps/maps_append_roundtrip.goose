// M_<f>_append adds entries with no key check, and M_fold_maps settles them as
// decoding does: the last value wins, in the place of the first occurrence.
import pb_wire;
import maps;

fn expect(cond: bool, what: const u8[:]) {
    if !cond { abort(str("expected: ", what)); }
}

// The bytes of `built`, against those of `put`, which _put made.
fn expect_same_bytes(what: const u8[:], built: maps::Maps&, put: maps::Maps&) {
    var a: u8[>..] = [];
    var b: u8[>..] = [];
    maps::Maps_encode(built, a);
    maps::Maps_encode(put, b);
    expect(a == b, what);
    expect(a.len == maps::Maps_size_of(built), "size_of agrees");
}

fn every_kind_of_value() {
    var m = maps::Maps { .. };
    var p = maps::Maps { .. };
    maps::Maps_ss_append(m, "a", "b");
    maps::Maps_ss_put(p, "a", "b");
    maps::Maps_is_append(m, -2, "x");
    maps::Maps_is_put(p, -2, "x");
    maps::Maps_si_append(m, "n", -1);
    maps::Maps_si_put(p, "n", -1);
    maps::Maps_ll_append(m, -3, -4);
    maps::Maps_ll_put(p, -3, -4);
    maps::Maps_bb_append(m, true, true);
    maps::Maps_bb_put(p, true, true);
    maps::Maps_sd_append(m, "d", -2.5);
    maps::Maps_sd_put(p, "d", -2.5);
    maps::Maps_se_append(m, "e", maps::Mode_MODE_ON);
    maps::Maps_se_put(p, "e", maps::Mode_MODE_ON);
    // A message value comes back to be filled, and starts empty.
    maps::Maps_sm_append(m, "m").a = 7;
    maps::Maps_sm_put(p, "m").a = 7;
    maps::Maps_sm_append(m, "empty");
    maps::Maps_sm_put(p, "empty");
    expect_same_bytes("every kind of value", m, p);
}

fn the_last_value_wins_in_the_first_place() {
    var m = maps::Maps { .. };
    maps::Maps_si_append(m, "a", 1);
    maps::Maps_si_append(m, "b", 2);
    maps::Maps_si_append(m, "a", 3);
    maps::Maps_si_append(m, "c", 4);
    maps::Maps_si_append(m, "b", 5);
    // Until it is folded, a repeated key is there twice.
    expect(maps::Maps_si(m).len == 5, "nothing folded yet");
    maps::Maps_fold_maps(m);
    expect(maps::Maps_si(m).len == 3, "folded to three");
    let va, fa = maps::Maps_si_get(m, "a");
    expect(fa && va == 3, "a has its last value");
    let vb, fb = maps::Maps_si_get(m, "b");
    expect(fb && vb == 5, "b has its last value");
    var p = maps::Maps { .. };
    maps::Maps_si_put(p, "a", 3);
    maps::Maps_si_put(p, "b", 5);
    maps::Maps_si_put(p, "c", 4);
    expect_same_bytes("in the place of the first occurrence", m, p);
}

fn a_repeated_message_value_frees_the_earlier_one() {
    var m = maps::Maps { .. };
    maps::Maps_sm_append(m, "k").a = 1;
    maps::Maps_sm_append(m, "k").a = 2;
    maps::Maps_fold_maps(m);
    let v = maps::Maps_sm_get(m, "k");
    assert(v);
    expect(v.a == 2, "the last message");
    expect(maps::Maps_sm(m).len == 1, "one entry");
    maps::Maps_clear(m);
    expect(maps::Maps_sm(m).len == 0, "cleared");
}

fn it_goes_on_after_a_put_and_a_decode() {
    var m = maps::Maps { .. };
    maps::Maps_si_put(m, "a", 1);
    maps::Maps_si_append(m, "b", 2);
    maps::Maps_si_append(m, "a", 3);
    var wire: u8[>..] = [];
    var other = maps::Maps { .. };
    maps::Maps_si_put(other, "c", 4);
    maps::Maps_encode(other, wire);
    // Decoding folds, so what was appended is settled with it.
    expect(maps::Maps_decode(wire, m) == PB_OK, "decodes");
    expect(maps::Maps_si(m).len == 3, "a, b and c");
    let va, fa = maps::Maps_si_get(m, "a");
    expect(fa && va == 3, "a");
}

fn many_entries_stay_quick() {
    // Past what a scan per key could do in the time a test has: 16 s for _put.
    var m = maps::Maps { .. };
    let n = 400000;
    for i in n { maps::Maps_ll_append(m, i, i * 2); }
    maps::Maps_ll_append(m, 5, -1);
    maps::Maps_fold_maps(m);
    expect(maps::Maps_ll(m).len == n, "all the keys, once");
    expect(maps::Maps_ll(m)[5].value == -1, "the last value, in its place");
    expect(maps::Maps_ll(m)[n - 1].key == n - 1, "the order they came in");
}

fn main() {
    every_kind_of_value();
    the_last_value_wins_in_the_first_place();
    a_repeated_message_value_frees_the_earlier_one();
    it_goes_on_after_a_put_and_a_decode();
    many_entries_stay_quick();
}
