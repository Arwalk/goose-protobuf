// The runtime's public names and their values (decision 0012). A failure here is
// a breaking change: it needs a version bump and a changelog entry, not a new value
// in this test.
// Run: scripts/goose_tests.sh tests/runtime
import pb_wire from "../../runtime";

fn expect(what: const u8[:], got: i64, want: i64) {
    if got != want { abort(str(what, " is ", got, ", and is public as ", want)); }
}

fn main() {
    expect("PB_OK", PB_OK, 0);
    expect("PB_ERR_TRUNCATED", PB_ERR_TRUNCATED, 1);
    expect("PB_ERR_MALFORMED", PB_ERR_MALFORMED, 2);
    expect("PB_ERR_DEPTH", PB_ERR_DEPTH, 3);
    expect("PB_ERR_UTF8", PB_ERR_UTF8, 4);
    expect("PB_ERR_REQUIRED", PB_ERR_REQUIRED, 5);
    expect("PB_MAX_DEPTH", PB_MAX_DEPTH, 100);
}
