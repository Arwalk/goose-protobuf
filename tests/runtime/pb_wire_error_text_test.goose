// pb_error_text gives each error code its own text, and is public (decision 0012).
// Run: scripts/goose_tests.sh tests/runtime
import pb_wire from "../../runtime";

fn expect(code: i32, want: const u8[:]) {
    if pb_error_text(code) != want { abort(str("code ", code, " reads '", pb_error_text(code), "'")); }
}

fn main() {
    expect(PB_OK, "no error");
    expect(PB_ERR_TRUNCATED, "truncated input");
    expect(PB_ERR_MALFORMED, "malformed input");
    expect(PB_ERR_DEPTH, "messages nested too deeply");
    expect(PB_ERR_UTF8, "a string that is not valid UTF-8");
    expect(PB_ERR_REQUIRED, "a required field is not set");
    expect(99, "unknown error");
    expect(-1, "unknown error");
}
