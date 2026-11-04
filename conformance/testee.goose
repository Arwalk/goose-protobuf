// testee.goose: conformance testee for protoc-gen-goose.
//
// Protocol (conformance_test_runner from third_party/protobuf):
//   read  4-byte little-endian length + ConformanceRequest
//   write 4-byte little-endian length + ConformanceResponse, then flush
//   repeat until stdin reaches EOF.
//
// The first request has message_type == "conformance.FailureSet"; reply
// with an empty FailureSet in protobuf_payload. A binary request for
// TestAllTypesProto3 with binary output is decoded with the generated
// bindings and re-encoded into protobuf_payload; a decode error is a
// parse_error. Everything else (proto2, editions, JSON, text) gets
// `skipped`.
//
// ConformanceRequest and ConformanceResponse are hand-coded (only the
// fields needed here; any other field is skipped by wire type) until the
// generator supports strings and oneofs (Phase 3).
//
// os.read_stdin reads to EOF, so exact-length reads go through the C shim
// in io.c (linked by testee.build); see docs/decisions/0003-stdio.md.
// Only the reply may go to stdout: no print, no read_stdin, no read_line.
//
// Build: scripts/build_testee.sh   (generates test_messages_proto3.goose
//        next to this file and builds build/testee)
// Check: python3 conformance/check_testee.py build/testee

import os;
import pb_wire;
import google.protobuf.test_messages_proto3;

extern "pbio_read_exact" fn read_exact(out: u8[>..]&, n: i64) -> i32;

// conformance.proto WireFormat
let WIRE_PROTOBUF: u64 = 1;

// What the testee needs from a ConformanceRequest.
let PAYLOAD_NONE = 0;
let PAYLOAD_PROTOBUF = 1;   // protobuf_payload (1)
let PAYLOAD_OTHER = 2;      // json_payload (2), jspb_payload (7), text_payload (8)

fn fail(msg: u8[:]) {
    write_stderr("testee: ");
    write_stderr(msg);
    write_stderr("\n");
    exit(1);
}

// Protobuf varint at b[at..]: the value and the position after it, or
// position -1 if it is truncated or longer than 10 bytes.
fn read_varint(b: u8[:], at: i64) -> u64, i64 {
    var v: u64 = 0;
    var i = at;
    for k in 10 {
        if i >= b.len { return 0, -1; }
        let c = b[i];
        i++;
        v |= ((c & 0x7f) as u64) << (7 * k) as u64;
        if c < 0x80 { return v, i; }
    }
    return 0, -1;
}

fn append_varint(out: u8[>..]&, v: u64) {
    var x = v;
    while x >= 0x80 {
        out.push((x & 0x7f | 0x80) as! u8);
        x >>= 7;
    }
    out.push(x as! u8);
}

// Send one ConformanceResponse: prefix and payload in one write.
fn send(resp: u8[:]) {
    let n = resp.len as! u64;
    var out: u8[>..] = [];
    for i in 4 { out.push((n >> (8 * i) as u64) as! u8); }
    out.append(resp);
    write_stdout(out);
    flush_stdout();
}

// Send a response holding one length-delimited field.
fn send_field(tag: u8, data: u8[:]) {
    var resp: u8[>..] = [];
    resp.push(tag);
    append_varint(resp, data.len as! u64);
    resp.append(data);
    send(resp);
}

fn send_skipped(reason: u8[:]) { send_field(0x2a, reason); }   // skipped (5)

// TestAllTypesProto3: decode, re-encode. The message's pool storage is
// freed before the next request.
var t3 = protobuf_test_messages_proto3::TestAllTypesProto3 { .. };

fn roundtrip_proto3(payload: u8[:]) {
    let err = protobuf_test_messages_proto3::TestAllTypesProto3_decode(payload, t3);
    if err != PB_OK {
        protobuf_test_messages_proto3::TestAllTypesProto3_clear(t3);
        send_field(0x0a, str("decode error ", err));   // parse_error (1)
        return;
    }
    var out: u8[>..] = [];
    protobuf_test_messages_proto3::TestAllTypesProto3_encode(t3, out);
    protobuf_test_messages_proto3::TestAllTypesProto3_clear(t3);
    send_field(0x1a, out);   // protobuf_payload (3)
}

fn respond(req: u8[:]) {
    var message_type: u8[:] = req[..0];
    var payload = PAYLOAD_NONE;
    var protobuf_payload: u8[:] = req[..0];
    var output_format: u64 = 0;

    var at: i64 = 0;
    while at < req.len {
        let tag, p = read_varint(req, at);
        if p < 0 { fail("truncated tag"); }
        at = p;
        let field = tag >> 3;
        let wire = tag & 7;
        if wire == 0 {
            let v, q = read_varint(req, at);
            if q < 0 { fail("truncated varint"); }
            at = q;
            if field == 3 { output_format = v; }
        } else if wire == 1 {
            if req.len - at < 8 { fail("truncated fixed64"); }
            at += 8;
        } else if wire == 5 {
            if req.len - at < 4 { fail("truncated fixed32"); }
            at += 4;
        } else if wire == 2 {
            let n, q = read_varint(req, at);
            if q < 0 { fail("truncated length"); }
            if n > (req.len - q) as! u64 { fail("length past end of request"); }
            at = q + n as! i64;
            if field == 4 { message_type = req[q..at]; }
            else if field == 1 { payload = PAYLOAD_PROTOBUF; protobuf_payload = req[q..at]; }
            else if field == 2 || field == 7 || field == 8 { payload = PAYLOAD_OTHER; }
        } else {
            fail("unsupported wire type in request");
        }
    }

    if message_type == "conformance.FailureSet" {
        let empty_failure_set: u8[2] = [0x1a, 0x00];   // protobuf_payload (3), 0 bytes
        send(empty_failure_set);
    } else if payload == PAYLOAD_PROTOBUF && output_format == WIRE_PROTOBUF {
        if message_type == "protobuf_test_messages.proto3.TestAllTypesProto3" {
            roundtrip_proto3(protobuf_payload);
        } else {
            send_skipped("only TestAllTypesProto3 is generated yet");
        }
    } else {
        send_skipped("only the binary wire format is supported");
    }
}

fn main() {
    var head: u8[>..] = [];
    var req: u8[>..] = [];
    loop {
        head.clear();
        let h = read_exact(head, 4);
        if h == 1 { exit(0); }                    // clean EOF between requests
        if h != 0 { fail("short read in length"); }
        var len: u64 = 0;
        for i in 4 { len |= (head[i] as u64) << (8 * i) as u64; }

        req.clear();
        if read_exact(req, len as! i64) != 0 { fail("short read in request"); }
        respond(req);
    }
}
