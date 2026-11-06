// A proto float default as Goose source: the text protoc wrote, read exactly as
// Zig's parseFloat does, and written as its {e} does. std's parse_flt is not
// correctly rounded, so this reads the digits through exact big-number division.

import std;
import pb_wire;
import support;

// Big natural numbers, little-endian u32 limbs, with no zero limb on top.
fn big_trim(a: u32[>..<]&) {
    while a.len > 0 && a[a.len - 1] == 0 { a.pop(); }
}

fn big_mul_add(a: u32[>..<]&, m: u32, add: u32) {
    var carry: u64 = add;
    for i in a.len {
        let v: u64 = (a[i] as u64) * m + carry;
        a[i] = v as! u32;
        carry = v >> 32;
    }
    if carry != 0 { a.push(carry as! u32); }
}

fn big_bits(a: u32[>..<]&) -> i64 {
    if a.len == 0 { return 0; }
    var n = (a.len - 1) * 32;
    var top = a[a.len - 1];
    while top != 0 { n += 1; top >>= 1; }
    return n;
}

fn big_shl(a: u32[>..<]&, n: i64) {
    if a.len == 0 { return; }
    let limbs = n / 32;
    let bits = n % 32;
    for i in limbs { a.push(0); }
    var i = a.len - 1;
    while i >= limbs {
        a[i] = a[i - limbs];
        i -= 1;
    }
    for j in limbs { a[j] = 0; }
    if bits != 0 {
        var carry: u32 = 0;
        for j in a.len {
            let v = a[j];
            a[j] = (v << bits) | carry;
            carry = v >> (32 - bits);
        }
        if carry != 0 { a.push(carry); }
    }
}

fn big_cmp(a: u32[>..<]&, b: u32[>..<]&) -> i64 {
    if a.len != b.len { return if a.len < b.len { -1 } else { 1 }; }
    var i = a.len - 1;
    while i >= 0 {
        if a[i] != b[i] { return if a[i] < b[i] { -1 } else { 1 }; }
        i -= 1;
    }
    return 0;
}

// a -= b, where a >= b.
fn big_sub(a: u32[>..<]&, b: u32[>..<]&) {
    var borrow: u64 = 0;
    for i in a.len {
        let s: u64 = (if i < b.len { b[i] as u64 } else { 0 }) + borrow;
        let v: u64 = a[i];
        if v >= s {
            a[i] = (v - s) as! u32;
            borrow = 0;
        } else {
            a[i] = (v + 0x100000000 - s) as! u32;
            borrow = 1;
        }
    }
    big_trim(a);
}

// The bits of the float nearest to digits * 10^exp10, ties to even, with
// `mant` mantissa bits and exponent bias `bias`. digits holds ASCII digits.
fn nearest_bits(digits: const u8[:], exp10: i64, mant: i64, bias: i64) -> u64 {
    var inf_bits: u64 = (bias * 2 + 1) as! u64;
    inf_bits = inf_bits << mant;
    var n: u32[>..<] = [];
    var d: u32[>..<] = [];
    d.push(1);
    for c in digits { big_mul_add(n, 10, c - '0'); }
    big_trim(n);
    if n.len == 0 { return 0; }
    if exp10 > 0 { for i in exp10 { big_mul_add(n, 10, 0); } }
    if exp10 < 0 { for i in -exp10 { big_mul_add(d, 10, 0); } }

    // Scale so that 1 <= n / d < 2: the value is that times 2^k.
    var k = big_bits(n) - big_bits(d);
    if k > 0 { big_shl(d, k); }
    if k < 0 { big_shl(n, -k); }
    if big_cmp(n, d) < 0 {
        big_shl(n, 1);
        k -= 1;
    }
    let emin = 1 - bias;
    if k > bias { return inf_bits; }
    // Below emin, fewer bits fit.
    let p = if k >= emin { mant + 1 } else { mant + 1 - (emin - k) };
    if p < 0 { return 0; }
    var q: u64 = 0;
    for i in p {
        q = q << 1;
        if big_cmp(n, d) >= 0 {
            big_sub(n, d);
            q |= 1;
        }
        big_shl(n, 1);
    }
    let c = big_cmp(n, d);
    if c > 0 || (c == 0 && (q & 1) != 0) { q += 1; }
    if k < emin { return q; }
    let biased: u64 = (k + bias) as! u64;
    let bits = (biased << mant) + (q - ((1 as! u64) << mant));
    if bits >= inf_bits { return inf_bits; }
    return bits;
}

// Reads [+-]digits[.digits][e[+-]digits]. The digits go to `digits`, without the
// point, and exp10 is what scales them. False for any other text.
fn scan_decimal(text: const u8[:], digits: u8[>..]&) -> bool, bool, i64 {
    var i = 0;
    var neg = false;
    if i < text.len && (text[i] == '-' || text[i] == '+') {
        neg = text[i] == '-';
        i += 1;
    }
    var exp10 = 0;
    var seen = false;
    while i < text.len && text[i] >= '0' && text[i] <= '9' {
        digits.push(text[i]);
        seen = true;
        i += 1;
    }
    if i < text.len && text[i] == '.' {
        i += 1;
        while i < text.len && text[i] >= '0' && text[i] <= '9' {
            digits.push(text[i]);
            exp10 -= 1;
            seen = true;
            i += 1;
        }
    }
    if !seen { return false, neg, 0; }
    if i < text.len && (text[i] == 'e' || text[i] == 'E') {
        i += 1;
        var eneg = false;
        if i < text.len && (text[i] == '-' || text[i] == '+') {
            eneg = text[i] == '-';
            i += 1;
        }
        var e = 0;
        var eseen = false;
        while i < text.len && text[i] >= '0' && text[i] <= '9' {
            if e < 100000 { e = e * 10 + (text[i] - '0'); }
            eseen = true;
            i += 1;
        }
        if !eseen { return false, neg, 0; }
        exp10 += if eneg { -e } else { e };
    }
    if i != text.len { return false, neg, 0; }
    return true, neg, exp10;
}

// The shortest text of a float, as print writes it, as Zig's {e} writes it:
// `1.5e0`, `-2.5e300`, `1e10`.
fn scientific(t: const u8[:]) -> const u8[:] {
    if t == "inf" || t == "-inf" { return keep(t); }
    var out: u8[>..] = [];
    var i = 0;
    if t[0] == '-' {
        out.push('-');
        i = 1;
    }
    var digits: u8[>..] = [];
    var point = 0;
    var seen_point = false;
    while i < t.len && t[i] != 'e' {
        if t[i] == '.' {
            seen_point = true;
        } else {
            digits.push(t[i]);
            if !seen_point { point += 1; }
        }
        i += 1;
    }
    var e = 0;
    if i < t.len {
        i += 1;
        var eneg = false;
        if t[i] == '-' || t[i] == '+' {
            eneg = t[i] == '-';
            i += 1;
        }
        while i < t.len {
            e = e * 10 + (t[i] - '0');
            i += 1;
        }
        if eneg { e = -e; }
    }
    var first = 0;
    while first + 1 < digits.len && digits[first] == '0' { first += 1; }
    var last = digits.len;
    while last > first + 1 && digits[last - 1] == '0' { last -= 1; }
    out.push(digits[first]);
    if last > first + 1 {
        out.push('.');
        out.append(digits[first + 1..last]);
    }
    format(out, "e", e + point - first - 1);
    return keep(out);
}

fn infinity_literal(is32: bool, neg: bool) -> const u8[:] {
    if is32 { return if neg { "pb_f32_from_bits(0xff800000)" } else { "pb_f32_from_bits(0x7f800000)" }; }
    return if neg { "pb_f64_from_bits(0xfff0000000000000)" } else { "pb_f64_from_bits(0x7ff0000000000000)" };
}

// The Goose expression of float default `text`, as protoc writes it, or "" if it
// is +0. Infinities and nan have no literal, so they go through the bits. Only
// decimal text is read, which is all protoc writes; other text stays as it is.
fn float_literal(is32: bool, text: const u8[:]) -> const u8[:] {
    if text == "inf" { return infinity_literal(is32, false); }
    if text == "-inf" { return infinity_literal(is32, true); }
    if text == "nan" { return if is32 { "pb_f32_from_bits(0x7fc00000)" } else { "pb_f64_from_bits(0x7ff8000000000000)" }; }
    var scanned: u8[>..] = [];
    let ok, neg, exp10 = scan_decimal(text, scanned);
    if !ok { return text; }
    var first = 0;
    while first < scanned.len && scanned[first] == '0' { first += 1; }
    let digits = scanned[first..];
    // The value is below 10^magnitude and, with no leading zeros, at least a tenth
    // of it. Past these, every float is 0 or inf, and the division need not be done.
    let magnitude = digits.len + exp10;
    var bits: u64 = 0;
    if digits.len == 0 {
        bits = 0;
    } else if is32 {
        bits = if magnitude > 60 { 0x7f800000 } else if magnitude < -80 { 0 } else { nearest_bits(digits, exp10, 23, 127) };
    } else {
        bits = if magnitude > 400 { 0x7ff0000000000000 } else if magnitude < -400 { 0 } else { nearest_bits(digits, exp10, 52, 1023) };
    }
    if bits == 0 { return if neg { "-0.0" } else { "" }; }
    if bits == (if is32 { 0x7f800000 } else { 0x7ff0000000000000 }) { return infinity_literal(is32, neg); }
    if is32 {
        let v = pb_f32_from_bits(bits as! u32);
        return scientific(str(if neg { -v } else { v }));
    }
    let v = pb_f64_from_bits(bits);
    return scientific(str(if neg { -v } else { v }));
}
