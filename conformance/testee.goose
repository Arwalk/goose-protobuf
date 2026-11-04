// testee.goose: conformance testee for protoc-gen-goose.
//
// Protocol (conformance_test_runner from third_party/protobuf):
//   read  4-byte little-endian length + ConformanceRequest
//   write 4-byte little-endian length + ConformanceResponse, then flush
//   repeat until stdin reaches EOF.
//
// The first request has message_type == "conformance.FailureSet"; reply
// with an empty FailureSet in protobuf_payload. A binary request with binary
// output, for TestAllTypesProto3, TestAllTypesProto2, their editions variants or
// TestAllTypesEdition2023, is decoded with the generated bindings and re-encoded
// into protobuf_payload; a decode error is a parse_error. Everything else (JSON,
// text, later editions) gets `skipped`.
//
// The envelope, ConformanceRequest and ConformanceResponse, is generated from
// conformance/conformance.proto too. The 4-byte length around it is framing, not
// protobuf, and uses the runtime's fixed32 helpers.
//
// os.read_stdin reads to EOF, so exact-length reads go through the C shim
// in io.c (linked by testee.build); see docs/decisions/0003-stdio.md.
// Only the reply may go to stdout: no print, no read_stdin, no read_line.
//
// Build: scripts/build_testee.sh   (generates the bindings next to this
//        file and builds build/testee)
// Check: python3 conformance/check_testee.py build/testee

import os;
import pb_wire;
import conformance.conformance;
import google.protobuf.test_messages_proto3;
import google.protobuf.test_messages_proto2;
import editions.golden.test_messages_proto3_editions;
import editions.golden.test_messages_proto2_editions;
import conformance.test_protos.test_messages_edition2023;

extern "pbio_read_exact" fn read_exact(out: u8[>..]&, n: i64) -> i32;

fn fail(msg: u8[:]) {
    write_stderr("testee: ");
    write_stderr(msg);
    write_stderr("\n");
    exit(1);
}

// Sends resp, and frees what it holds. Prefix and payload go in one write.
fn send(resp: conformance::ConformanceResponse&) {
    var out: u8[>..] = [];
    pb_write_fixed32(out, conformance::ConformanceResponse_size_of(resp) as! u32);
    conformance::ConformanceResponse_encode(resp, out);
    conformance::ConformanceResponse_clear(resp);
    write_stdout(out);
    flush_stdout();
}

// TestAllTypesProto3: decode, re-encode. The message's pool storage is
// freed before the next request.
var t3 = protobuf_test_messages_proto3::TestAllTypesProto3 { .. };

fn roundtrip_proto3(payload: const u8[:], resp: conformance::ConformanceResponse&) {
    let err = protobuf_test_messages_proto3::TestAllTypesProto3_decode(payload, t3);
    if err != PB_OK {
        protobuf_test_messages_proto3::TestAllTypesProto3_clear(t3);
        conformance::ConformanceResponse_set_parse_error(resp, str("decode error ", err));
        return;
    }
    var out: u8[>..] = [];
    protobuf_test_messages_proto3::TestAllTypesProto3_encode(t3, out);
    protobuf_test_messages_proto3::TestAllTypesProto3_clear(t3);
    conformance::ConformanceResponse_set_protobuf_payload(resp, out);
}

// TestAllTypesProto2, likewise.
var t2 = protobuf_test_messages_proto2::TestAllTypesProto2 { .. };

fn roundtrip_proto2(payload: const u8[:], resp: conformance::ConformanceResponse&) {
    let err = protobuf_test_messages_proto2::TestAllTypesProto2_decode(payload, t2);
    if err != PB_OK {
        protobuf_test_messages_proto2::TestAllTypesProto2_clear(t2);
        conformance::ConformanceResponse_set_parse_error(resp, str("decode error ", err));
        return;
    }
    var out: u8[>..] = [];
    protobuf_test_messages_proto2::TestAllTypesProto2_encode(t2, out);
    protobuf_test_messages_proto2::TestAllTypesProto2_clear(t2);
    conformance::ConformanceResponse_set_protobuf_payload(resp, out);
}

// The editions variants, likewise.
var e3 = protobuf_test_messages_editions_proto3::TestAllTypesProto3 { .. };

fn roundtrip_proto3_editions(payload: const u8[:], resp: conformance::ConformanceResponse&) {
    let err = protobuf_test_messages_editions_proto3::TestAllTypesProto3_decode(payload, e3);
    if err != PB_OK {
        protobuf_test_messages_editions_proto3::TestAllTypesProto3_clear(e3);
        conformance::ConformanceResponse_set_parse_error(resp, str("decode error ", err));
        return;
    }
    var out: u8[>..] = [];
    protobuf_test_messages_editions_proto3::TestAllTypesProto3_encode(e3, out);
    protobuf_test_messages_editions_proto3::TestAllTypesProto3_clear(e3);
    conformance::ConformanceResponse_set_protobuf_payload(resp, out);
}

var e2 = protobuf_test_messages_editions_proto2::TestAllTypesProto2 { .. };

fn roundtrip_proto2_editions(payload: const u8[:], resp: conformance::ConformanceResponse&) {
    let err = protobuf_test_messages_editions_proto2::TestAllTypesProto2_decode(payload, e2);
    if err != PB_OK {
        protobuf_test_messages_editions_proto2::TestAllTypesProto2_clear(e2);
        conformance::ConformanceResponse_set_parse_error(resp, str("decode error ", err));
        return;
    }
    var out: u8[>..] = [];
    protobuf_test_messages_editions_proto2::TestAllTypesProto2_encode(e2, out);
    protobuf_test_messages_editions_proto2::TestAllTypesProto2_clear(e2);
    conformance::ConformanceResponse_set_protobuf_payload(resp, out);
}

var e23 = protobuf_test_messages_editions::TestAllTypesEdition2023 { .. };

fn roundtrip_edition2023(payload: const u8[:], resp: conformance::ConformanceResponse&) {
    let err = protobuf_test_messages_editions::TestAllTypesEdition2023_decode(payload, e23);
    if err != PB_OK {
        protobuf_test_messages_editions::TestAllTypesEdition2023_clear(e23);
        conformance::ConformanceResponse_set_parse_error(resp, str("decode error ", err));
        return;
    }
    var out: u8[>..] = [];
    protobuf_test_messages_editions::TestAllTypesEdition2023_encode(e23, out);
    protobuf_test_messages_editions::TestAllTypesEdition2023_clear(e23);
    conformance::ConformanceResponse_set_protobuf_payload(resp, out);
}

var request = conformance::ConformanceRequest { .. };
var response = conformance::ConformanceResponse { .. };

fn respond(buf: const u8[:]) {
    if conformance::ConformanceRequest_decode(buf, request) != PB_OK { fail("bad request"); }
    let binary = conformance::ConformanceRequest_has_protobuf_payload(request)
        && request.requested_output_format == conformance::WireFormat_PROTOBUF;
    if conformance::ConformanceRequest_message_type(request) == "conformance.FailureSet" {
        // An empty FailureSet, which encodes to no bytes, and is present.
        conformance::ConformanceResponse_set_protobuf_payload(response, "");
    } else if !binary {
        conformance::ConformanceResponse_set_skipped(response, "only the binary wire format is supported");
    } else if conformance::ConformanceRequest_message_type(request) == "protobuf_test_messages.proto3.TestAllTypesProto3" {
        // Its own copy: decoding allocates in pb_bytes, where the request is.
        var payload: u8[>..] = [];
        payload.append(conformance::ConformanceRequest_protobuf_payload(request));
        roundtrip_proto3(payload, response);
    } else if conformance::ConformanceRequest_message_type(request) == "protobuf_test_messages.proto2.TestAllTypesProto2" {
        var payload: u8[>..] = [];
        payload.append(conformance::ConformanceRequest_protobuf_payload(request));
        roundtrip_proto2(payload, response);
    } else if conformance::ConformanceRequest_message_type(request) == "protobuf_test_messages.editions.proto3.TestAllTypesProto3" {
        var payload: u8[>..] = [];
        payload.append(conformance::ConformanceRequest_protobuf_payload(request));
        roundtrip_proto3_editions(payload, response);
    } else if conformance::ConformanceRequest_message_type(request) == "protobuf_test_messages.editions.proto2.TestAllTypesProto2" {
        var payload: u8[>..] = [];
        payload.append(conformance::ConformanceRequest_protobuf_payload(request));
        roundtrip_proto2_editions(payload, response);
    } else if conformance::ConformanceRequest_message_type(request) == "protobuf_test_messages.editions.TestAllTypesEdition2023" {
        var payload: u8[>..] = [];
        payload.append(conformance::ConformanceRequest_protobuf_payload(request));
        roundtrip_edition2023(payload, response);
    } else {
        conformance::ConformanceResponse_set_skipped(response, "this message is not generated");
    }
    conformance::ConformanceRequest_clear(request);
    send(response);
}

fn main() {
    var head: u8[>..] = [];
    var req: u8[>..] = [];
    loop {
        head.clear();
        let h = read_exact(head, 4);
        if h == 1 { exit(0); }                    // clean EOF between requests
        if h != 0 { fail("short read in length"); }
        var r = pb_reader(head);
        let len: i64 = pb_read_fixed32(r);

        req.clear();
        if read_exact(req, len) != 0 { fail("short read in request"); }
        respond(req);
    }
}
