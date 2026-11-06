// generator-goose/float_text.goose: the Goose expression of a float default.
// Run by scripts/selfhost_tests.sh.
import pb_wire;
import float_text;

fn check_literal(is32: bool, text: const u8[:], want: const u8[:]) {
    let got = floatLiteral(is32, text);
    if got != want { abort(str("floatLiteral(", is32, ", \"", text, "\") is \"", got, "\", not \"", want, "\"")); }
}

fn main() {
    check_literal(true, "1.5", "1.5e0");
    check_literal(false, "1e+10", "1e10");
    check_literal(false, "-0", "-0.0");
    check_literal(false, "0", "");
    check_literal(true, "nan", "pb_f32_from_bits(0x7fc00000)");
    check_literal(false, "nan", "pb_f64_from_bits(0x7ff8000000000000)");
    check_literal(true, "inf", "pb_f32_from_bits(0x7f800000)");
    check_literal(false, "-inf", "pb_f64_from_bits(0xfff0000000000000)");
    // What protoc does not write stays as it is.
    check_literal(false, "abc", "abc");
    // Exact where std's parse_flt is not: the nearest float, ties to even.
    check_literal(false, "9007199254740993", "9.007199254740992e15");
    check_literal(false, "9007199254740995", "9.007199254740996e15");
    check_literal(true, "16777217", "1.6777216e7");
    check_literal(true, "16777219", "1.677722e7");
    // The ends of the range, and past them.
    check_literal(false, "5e-324", "5e-324");
    check_literal(false, "2e-324", "");
    check_literal(false, "3e-324", "5e-324");
    check_literal(false, "1.7976931348623157e308", "1.7976931348623157e308");
    check_literal(true, "1e-45", "1e-45");
    // Text past the largest float is an infinity, which has no literal. protoc
    // writes "inf" for it, but a plugin reads what it is given.
    check_literal(false, "1e309", "pb_f64_from_bits(0x7ff0000000000000)");
    check_literal(false, "-1e309", "pb_f64_from_bits(0xfff0000000000000)");
    check_literal(true, "1e39", "pb_f32_from_bits(0x7f800000)");
    check_literal(true, "-1e39", "pb_f32_from_bits(0xff800000)");
    check_literal(false, "1e99999999999", "pb_f64_from_bits(0x7ff0000000000000)");

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
