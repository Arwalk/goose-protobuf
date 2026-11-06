// What the *_unit.goose programs share: expectations, and building descriptors.

import pb_wire;
import google.protobuf.compiler.plugin;
import google.protobuf.descriptor;
import support;
import features;
import emit;

let LABEL_OPTIONAL = 1;

fn expect(cond: bool, what: const u8[:]) {
    if !cond { abort(str("expected: ", what)); }
}

fn expect_str(got: const u8[:], want: const u8[:]) {
    if got != want { abort(str("got \"", got, "\", want \"", want, "\"")); }
}

fn text_has(text: const u8[:], part: const u8[:]) -> bool {
    var i = 0;
    while i + part.len <= text.len {
        if text[i..i + part.len] == part { return true; }
        i += 1;
    }
    return false;
}

fn expect_has(text: const u8[:], part: const u8[:]) {
    if !text_has(text, part) { abort(str("no \"", part, "\" in:\n", text)); }
}

fn expect_lacks(text: const u8[:], part: const u8[:]) {
    if text_has(text, part) { abort(str("\"", part, "\" in:\n", text)); }
}

fn set_field(fd: FieldDesc&, name: const u8[:], number: i32, label: i32, type_: i32) {
    google_protobuf::FieldDescriptorProto_set_name(fd, name);
    google_protobuf::FieldDescriptorProto_set_number(fd, number);
    google_protobuf::FieldDescriptorProto_set_label(fd, label);
    google_protobuf::FieldDescriptorProto_set_type(fd, type_);
}

fn add_field(m: MessageDesc&, name: const u8[:], number: i32, label: i32, type_: i32) -> FieldDesc& {
    let fd .= google_protobuf::DescriptorProto_add_field(m);
    set_field(fd, name, number, label, type_);
    return fd;
}

fn add_message_field(m: MessageDesc&, name: const u8[:], number: i32, label: i32, type_name: const u8[:]) -> FieldDesc& {
    let fd .= add_field(m, name, number, label, TYPE_MESSAGE);
    google_protobuf::FieldDescriptorProto_set_type_name(fd, type_name);
    return fd;
}

fn add_message(file: FileDesc&, name: const u8[:]) -> MessageDesc& {
    let m .= google_protobuf::FileDescriptorProto_add_message_type(file);
    google_protobuf::DescriptorProto_set_name(m, name);
    return m;
}

fn add_nested(parent: MessageDesc&, name: const u8[:]) -> MessageDesc& {
    let m .= google_protobuf::DescriptorProto_add_nested_type(parent);
    google_protobuf::DescriptorProto_set_name(m, name);
    return m;
}

fn add_map_entry(parent: MessageDesc&, name: const u8[:]) -> MessageDesc& {
    let m .= add_nested(parent, name);
    google_protobuf::MessageOptions_set_map_entry(google_protobuf::DescriptorProto_mutable_options(m), true);
    return m;
}

fn add_oneof(m: MessageDesc&, name: const u8[:]) -> OneofDesc& {
    let o .= google_protobuf::DescriptorProto_add_oneof_decl(m);
    google_protobuf::OneofDescriptorProto_set_name(o, name);
    return o;
}

fn add_enum_value(e: EnumDesc&, name: const u8[:], number: i32) {
    let v .= google_protobuf::EnumDescriptorProto_add_value(e);
    google_protobuf::EnumValueDescriptorProto_set_name(v, name);
    google_protobuf::EnumValueDescriptorProto_set_number(v, number);
}

// Starts a request over, as a new run of the plugin would have it.
fn reset_generator() {
    google_protobuf_compiler::CodeGeneratorRequest_clear(request);
    forget_request();
    diag = "";
}

// A file of the request, which generate_file can see, as protoc would send it.
fn add_file(name: const u8[:], package: const u8[:], syntax: const u8[:]) -> FileDesc& {
    let file .= google_protobuf_compiler::CodeGeneratorRequest_add_proto_file(request);
    google_protobuf::FileDescriptorProto_set_name(file, name);
    if package.len > 0 { google_protobuf::FileDescriptorProto_set_package(file, package); }
    if syntax.len > 0 { google_protobuf::FileDescriptorProto_set_syntax(file, syntax); }
    return file;
}

// What generate_file writes for `file`, which must not collide.
fn generated_text(file: FileDesc&) -> const u8[:] {
    let at = w.len;
    if !generate_file(file) { abort(str("unexpected collision: ", diag)); }
    return w[at..];
}

// The message of the collision that `file` must have.
fn collision_of(file: FileDesc&) -> const u8[:] {
    if generate_file(file) { abort("expected a collision"); }
    return diag;
}
