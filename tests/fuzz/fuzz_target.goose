// fuzz_target.goose: the fuzz target for scripts/fuzz.sh, built as C with
// --debug, so that a failed check in generated code is a crash too.
//
// fuzz_one(input) reads input[0] as a choice of message and the rest as its
// bytes, the conformance suite's five test messages. Bytes that do not decode
// are fine. Those that do must encode to size_of bytes, and those bytes must
// decode again and encode to the same bytes. Anything else aborts.
// fuzz_entry.c is the libFuzzer entry point.
import pb_wire;
import google.protobuf.test_messages_proto3;
import google.protobuf.test_messages_proto2;
import editions.golden.test_messages_proto3_editions;
import editions.golden.test_messages_proto2_editions;
import conformance.test_protos.test_messages_edition2023;

var t3 = protobuf_test_messages_proto3::TestAllTypesProto3 { .. };

fn check_t3(input: const u8[:]) {
    if protobuf_test_messages_proto3::TestAllTypesProto3_decode(input, t3) != PB_OK {
        protobuf_test_messages_proto3::TestAllTypesProto3_clear(t3);
        return;
    }
    var first: u8[>..] = [];
    protobuf_test_messages_proto3::TestAllTypesProto3_encode(t3, first);
    if protobuf_test_messages_proto3::TestAllTypesProto3_size_of(t3) != first.len { abort("size_of differs from encode"); }
    protobuf_test_messages_proto3::TestAllTypesProto3_clear(t3);
    if protobuf_test_messages_proto3::TestAllTypesProto3_decode(first, t3) != PB_OK { abort("own encoding does not decode"); }
    var second: u8[>..] = [];
    protobuf_test_messages_proto3::TestAllTypesProto3_encode(t3, second);
    protobuf_test_messages_proto3::TestAllTypesProto3_clear(t3);
    if first != second { abort("second encoding differs"); }
}

var t2 = protobuf_test_messages_proto2::TestAllTypesProto2 { .. };

fn check_t2(input: const u8[:]) {
    if protobuf_test_messages_proto2::TestAllTypesProto2_decode(input, t2) != PB_OK {
        protobuf_test_messages_proto2::TestAllTypesProto2_clear(t2);
        return;
    }
    var first: u8[>..] = [];
    protobuf_test_messages_proto2::TestAllTypesProto2_encode(t2, first);
    if protobuf_test_messages_proto2::TestAllTypesProto2_size_of(t2) != first.len { abort("size_of differs from encode"); }
    protobuf_test_messages_proto2::TestAllTypesProto2_clear(t2);
    if protobuf_test_messages_proto2::TestAllTypesProto2_decode(first, t2) != PB_OK { abort("own encoding does not decode"); }
    var second: u8[>..] = [];
    protobuf_test_messages_proto2::TestAllTypesProto2_encode(t2, second);
    protobuf_test_messages_proto2::TestAllTypesProto2_clear(t2);
    if first != second { abort("second encoding differs"); }
}

var e3 = protobuf_test_messages_editions_proto3::TestAllTypesProto3 { .. };

fn check_e3(input: const u8[:]) {
    if protobuf_test_messages_editions_proto3::TestAllTypesProto3_decode(input, e3) != PB_OK {
        protobuf_test_messages_editions_proto3::TestAllTypesProto3_clear(e3);
        return;
    }
    var first: u8[>..] = [];
    protobuf_test_messages_editions_proto3::TestAllTypesProto3_encode(e3, first);
    if protobuf_test_messages_editions_proto3::TestAllTypesProto3_size_of(e3) != first.len { abort("size_of differs from encode"); }
    protobuf_test_messages_editions_proto3::TestAllTypesProto3_clear(e3);
    if protobuf_test_messages_editions_proto3::TestAllTypesProto3_decode(first, e3) != PB_OK { abort("own encoding does not decode"); }
    var second: u8[>..] = [];
    protobuf_test_messages_editions_proto3::TestAllTypesProto3_encode(e3, second);
    protobuf_test_messages_editions_proto3::TestAllTypesProto3_clear(e3);
    if first != second { abort("second encoding differs"); }
}

var e2 = protobuf_test_messages_editions_proto2::TestAllTypesProto2 { .. };

fn check_e2(input: const u8[:]) {
    if protobuf_test_messages_editions_proto2::TestAllTypesProto2_decode(input, e2) != PB_OK {
        protobuf_test_messages_editions_proto2::TestAllTypesProto2_clear(e2);
        return;
    }
    var first: u8[>..] = [];
    protobuf_test_messages_editions_proto2::TestAllTypesProto2_encode(e2, first);
    if protobuf_test_messages_editions_proto2::TestAllTypesProto2_size_of(e2) != first.len { abort("size_of differs from encode"); }
    protobuf_test_messages_editions_proto2::TestAllTypesProto2_clear(e2);
    if protobuf_test_messages_editions_proto2::TestAllTypesProto2_decode(first, e2) != PB_OK { abort("own encoding does not decode"); }
    var second: u8[>..] = [];
    protobuf_test_messages_editions_proto2::TestAllTypesProto2_encode(e2, second);
    protobuf_test_messages_editions_proto2::TestAllTypesProto2_clear(e2);
    if first != second { abort("second encoding differs"); }
}

var e23 = protobuf_test_messages_editions::TestAllTypesEdition2023 { .. };

fn check_e23(input: const u8[:]) {
    if protobuf_test_messages_editions::TestAllTypesEdition2023_decode(input, e23) != PB_OK {
        protobuf_test_messages_editions::TestAllTypesEdition2023_clear(e23);
        return;
    }
    var first: u8[>..] = [];
    protobuf_test_messages_editions::TestAllTypesEdition2023_encode(e23, first);
    if protobuf_test_messages_editions::TestAllTypesEdition2023_size_of(e23) != first.len { abort("size_of differs from encode"); }
    protobuf_test_messages_editions::TestAllTypesEdition2023_clear(e23);
    if protobuf_test_messages_editions::TestAllTypesEdition2023_decode(first, e23) != PB_OK { abort("own encoding does not decode"); }
    var second: u8[>..] = [];
    protobuf_test_messages_editions::TestAllTypesEdition2023_encode(e23, second);
    protobuf_test_messages_editions::TestAllTypesEdition2023_clear(e23);
    if first != second { abort("second encoding differs"); }
}

export "fuzz_one" fn fuzz_one(input: const u8[:]) {
    if input.len == 0 { return; }
    let rest = input[1..input.len];
    let which = input[0] % 5;
    if which == 0 {
        check_t3(rest);
    } else if which == 1 {
        check_t2(rest);
    } else if which == 2 {
        check_e3(rest);
    } else if which == 3 {
        check_e2(rest);
    } else if which == 4 {
        check_e23(rest);
    }
}
