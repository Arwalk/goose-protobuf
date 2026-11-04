#!/usr/bin/env python3
"""A conformance testee that records inputs: scripts/fuzz_seeds.sh runs it.

It sits between conformance_test_runner and the real testee (argv[1]) and writes
each binary request's payload to $FUZZ_RECORD_DIR, as fuzz_target.goose reads it:
one byte choosing the message, then the payload. The name is its sha1.
"""
import hashlib
import os
import struct
import subprocess
import sys

from google.protobuf import descriptor_pb2, descriptor_pool, message_factory

CHOICE = {
    "protobuf_test_messages.proto3.TestAllTypesProto3": 0,
    "protobuf_test_messages.proto2.TestAllTypesProto2": 1,
    "protobuf_test_messages.editions.proto3.TestAllTypesProto3": 2,
    "protobuf_test_messages.editions.proto2.TestAllTypesProto2": 3,
    "protobuf_test_messages.editions.TestAllTypesEdition2023": 4,
}


def read_frame(stream):
    head = stream.read(4)
    if len(head) < 4:
        return None
    return head + stream.read(struct.unpack("<I", head)[0])


def main():
    pool = descriptor_pool.DescriptorPool()
    with open(os.environ["FUZZ_RECORD_DESC"], "rb") as f:
        for file in descriptor_pb2.FileDescriptorSet.FromString(f.read()).file:
            pool.Add(file)
    request_type = message_factory.GetMessageClass(
        pool.FindMessageTypeByName("conformance.ConformanceRequest"))
    out = os.environ["FUZZ_RECORD_DIR"]
    testee = subprocess.Popen(sys.argv[1:], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    while True:
        frame = read_frame(sys.stdin.buffer)
        if frame is None:
            break
        request = request_type.FromString(frame[4:])
        if request.WhichOneof("payload") == "protobuf_payload" and request.message_type in CHOICE:
            data = bytes([CHOICE[request.message_type]]) + request.protobuf_payload
            with open(os.path.join(out, hashlib.sha1(data).hexdigest()), "wb") as f:
                f.write(data)
        testee.stdin.write(frame)
        testee.stdin.flush()
        reply = read_frame(testee.stdout)
        sys.stdout.buffer.write(reply)
        sys.stdout.buffer.flush()
    testee.stdin.close()
    testee.wait()


if __name__ == "__main__":
    main()
