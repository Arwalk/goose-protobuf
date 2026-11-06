// generator-goose/float_text.goose: the Goose expression of a float default.
// Run by scripts/selfhost_tests.sh.
import pb_wire;
import float_text;

fn check_literal(is32: bool, text: const u8[:], want: const u8[:]) {
    let got = floatLiteral(is32, text);
    if got != want { abort(str("floatLiteral(", is32, ", \"", text, "\") is \"", got, "\", not \"", want, "\"")); }
}

fn main() {
    // Leading zeros say nothing of the magnitude, nor does an exponent on zero.
    var zeros: u8[>..] = [];
    for i in 500 { zeros.push('0'); }
    check_literal(false, str(zeros, "1"), "1e0");
    check_literal(true, str(zeros, ".5"), "5e-1");
    check_literal(false, "0e999", "");
    check_literal(true, "0e999", "");
    check_literal(false, "-0e999", "-0.0");
    check_literal(false, str(zeros, "1e-500"), "");
}
