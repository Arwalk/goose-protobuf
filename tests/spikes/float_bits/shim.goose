// Spike gpb-wof.2: the C shim alternative, same vectors as pure.goose.
// float_bits.c does the bit cast with memcpy; shim.build links it in.
// Run: goose tests/spikes/float_bits/shim.goose [--debug]

extern "pbw_f32_to_bits" fn f32_to_bits(x: f32) -> u32;
extern "pbw_f64_to_bits" fn f64_to_bits(x: f64) -> u64;
extern "pbw_f32_from_bits" fn f32_from_bits(v: u32) -> f32;
extern "pbw_f64_from_bits" fn f64_from_bits(v: u64) -> f64;

var failures = 0;

fn check32(name: u8[:], bits: u32, lit: f32) {
    let to = f32_to_bits(lit);
    let back = f32_to_bits(f32_from_bits(bits));
    let ok = to == bits && back == bits;
    if !ok { failures += 1; }
    print(if ok { "PASS" } else { "FAIL" }, " f32 ", name, " want ", bits,
          " to_bits ", to, " round_trip ", back);
}

fn check64(name: u8[:], bits: u64, lit: f64) {
    let to = f64_to_bits(lit);
    let back = f64_to_bits(f64_from_bits(bits));
    let ok = to == bits && back == bits;
    if !ok { failures += 1; }
    print(if ok { "PASS" } else { "FAIL" }, " f64 ", name, " want ", bits,
          " to_bits ", to, " round_trip ", back);
}

fn main() {
    let one: u32 = 1;
    let probe: u32[1] = [one];
    print("little-endian host: ", bytes_of(probe)[0] == 1);

    let zero32: f32 = 0.0;
    let zero64: f64 = 0.0;
    let inf32: f32 = 1.0 / zero32;
    let inf64: f64 = 1.0 / zero64;

    // For NaN vectors the "literal" side is the value decoded from bits,
    // since Goose has no NaN-payload literal: this checks that a payload
    // survives a pass through an f32/f64 local and parameter.
    check32("+0.0", 0x00000000, 0.0);
    check32("-0.0", 0x80000000, -zero32);
    check32("1.0", 0x3F800000, 1.0);
    check32("-2.5", 0xC0200000, -2.5);
    check32("+inf", 0x7F800000, inf32);
    check32("-inf", 0xFF800000, -inf32);
    check32("qNaN payload 1", 0x7FC00001, f32_from_bits(0x7FC00001));
    check32("-qNaN payload", 0xFFC0BEEF, f32_from_bits(0xFFC0BEEF));
    check32("sNaN payload 1", 0x7F800001, f32_from_bits(0x7F800001));
    check32("sNaN max payload", 0x7FBFFFFF, f32_from_bits(0x7FBFFFFF));
    check32("min subnormal", 0x00000001, 0x1p-149);
    check32("max subnormal", 0x007FFFFF, f32_from_bits(0x007FFFFF));
    check32("max finite", 0x7F7FFFFF, 0x1.fffffep127);

    check64("+0.0", 0x0000000000000000, 0.0);
    check64("-0.0", 0x8000000000000000, -zero64);
    check64("1.0", 0x3FF0000000000000, 1.0);
    check64("-2.5", 0xC004000000000000, -2.5);
    check64("+inf", 0x7FF0000000000000, inf64);
    check64("-inf", 0xFFF0000000000000, -inf64);
    check64("qNaN payload 1", 0x7FF8000000000001, f64_from_bits(0x7FF8000000000001));
    check64("-qNaN payload", 0xFFF800000000BEEF, f64_from_bits(0xFFF800000000BEEF));
    check64("sNaN payload 1", 0x7FF0000000000001, f64_from_bits(0x7FF0000000000001));
    check64("sNaN max payload", 0x7FF7FFFFFFFFFFFF, f64_from_bits(0x7FF7FFFFFFFFFFFF));
    check64("min subnormal", 0x0000000000000001, 0x1p-1074);
    check64("max subnormal", 0x000FFFFFFFFFFFFF, f64_from_bits(0x000FFFFFFFFFFFFF));
    check64("max finite", 0x7FEFFFFFFFFFFFFF, 0x1.fffffffffffffp1023);

    // Arithmetic must quiet an sNaN; the bit routes above must not.
    let s = f32_from_bits(0x7F800001);
    print("sNaN + 0 gives ", f32_to_bits(s + 0.0), " (quieted, expected)");

    print(failures, " failures");
    if failures != 0 { exit(1); }
}
