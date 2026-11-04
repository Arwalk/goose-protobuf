// For scripts/test_fuzz.sh: a target that fails on an input starting with 0x7f.
export "fuzz_one" fn fuzz_one(input: const u8[:]) {
    if input.len > 0 && input[0] == 0x7f { abort("found it"); }
}
