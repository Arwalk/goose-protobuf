// Resolved protobuf features: what proto2, proto3 and editions all come down
// to, per element. protoc passes a file's features unresolved, as it wrote them,
// so the plugin resolves them as protobuf's descriptor.cc does: the defaults of
// the file's edition, overridden by the file, then each enclosing element.

import pb_wire;
import google.protobuf.descriptor;

type FeatureSet = google_protobuf::FeatureSet;
type FileDesc = google_protobuf::FileDescriptorProto;
type MessageDesc = google_protobuf::DescriptorProto;
type FieldDesc = google_protobuf::FieldDescriptorProto;
type EnumDesc = google_protobuf::EnumDescriptorProto;
type OneofDesc = google_protobuf::OneofDescriptorProto;

let TYPE_DOUBLE = 1;
let TYPE_FLOAT = 2;
let TYPE_INT64 = 3;
let TYPE_UINT64 = 4;
let TYPE_INT32 = 5;
let TYPE_FIXED64 = 6;
let TYPE_FIXED32 = 7;
let TYPE_BOOL = 8;
let TYPE_STRING = 9;
let TYPE_GROUP = 10;
let TYPE_MESSAGE = 11;
let TYPE_BYTES = 12;
let TYPE_UINT32 = 13;
let TYPE_ENUM = 14;
let TYPE_SFIXED32 = 15;
let TYPE_SFIXED64 = 16;
let TYPE_SINT32 = 17;
let TYPE_SINT64 = 18;
// fd.type when the field has none.
let TYPE_NONE = 0;

let LABEL_REQUIRED = 2;
let LABEL_REPEATED = 3;

let PRESENCE_EXPLICIT = 0;
let PRESENCE_IMPLICIT = 1;
let PRESENCE_REQUIRED = 2;

// The field accessors of the bindings, for what is not set: a field reads as "" or
// TYPE_NONE, not as its default.
fn field_name(fd: FieldDesc&) -> const u8[:] { return google_protobuf::FieldDescriptorProto_name(fd); }

fn field_type(fd: FieldDesc&) -> i32 {
    if !google_protobuf::FieldDescriptorProto_has_type(fd) { return TYPE_NONE; }
    return fd.type_;
}

fn field_is_repeated(fd: FieldDesc&) -> bool {
    return google_protobuf::FieldDescriptorProto_has_label(fd) && fd.label == LABEL_REPEATED;
}

fn field_is_required(fd: FieldDesc&) -> bool {
    return google_protobuf::FieldDescriptorProto_has_label(fd) && fd.label == LABEL_REQUIRED;
}

fn file_name(file: FileDesc&) -> const u8[:] { return google_protobuf::FileDescriptorProto_name(file); }
fn file_package(file: FileDesc&) -> const u8[:] { return google_protobuf::FileDescriptorProto_package(file); }
fn message_name(m: MessageDesc&) -> const u8[:] { return google_protobuf::DescriptorProto_name(m); }
fn enum_name(e: EnumDesc&) -> const u8[:] { return google_protobuf::EnumDescriptorProto_name(e); }

// The features this generator acts on. json_format and the naming and limit
// features say nothing about the binary wire format.
struct Features {
    presence: i32,
    closed_enum: bool,
    packed_repeated: bool,
    verify_utf8: bool,
    delimited: bool,
}

// What an element whose parent has these features has, with its own
// overrides from its options, if any.
fn features_child(parent: Features, set: FeatureSet?) -> Features {
    var f = parent;
    guard set else { return f; }
    if google_protobuf::FeatureSet_has_field_presence(set) {
        let v = set.field_presence;
        if v == google_protobuf::FeatureSet_FieldPresence_EXPLICIT { f.presence = PRESENCE_EXPLICIT; }
        if v == google_protobuf::FeatureSet_FieldPresence_IMPLICIT { f.presence = PRESENCE_IMPLICIT; }
        if v == google_protobuf::FeatureSet_FieldPresence_LEGACY_REQUIRED { f.presence = PRESENCE_REQUIRED; }
    }
    if google_protobuf::FeatureSet_has_enum_type(set) {
        let v = set.enum_type;
        if v == google_protobuf::FeatureSet_EnumType_OPEN { f.closed_enum = false; }
        if v == google_protobuf::FeatureSet_EnumType_CLOSED { f.closed_enum = true; }
    }
    if google_protobuf::FeatureSet_has_repeated_field_encoding(set) {
        let v = set.repeated_field_encoding;
        if v == google_protobuf::FeatureSet_RepeatedFieldEncoding_PACKED { f.packed_repeated = true; }
        if v == google_protobuf::FeatureSet_RepeatedFieldEncoding_EXPANDED { f.packed_repeated = false; }
    }
    if google_protobuf::FeatureSet_has_utf8_validation(set) {
        let v = set.utf8_validation;
        if v == google_protobuf::FeatureSet_Utf8Validation_VERIFY { f.verify_utf8 = true; }
        if v == google_protobuf::FeatureSet_Utf8Validation_NONE { f.verify_utf8 = false; }
    }
    if google_protobuf::FeatureSet_has_message_encoding(set) {
        let v = set.message_encoding;
        if v == google_protobuf::FeatureSet_MessageEncoding_LENGTH_PREFIXED { f.delimited = false; }
        if v == google_protobuf::FeatureSet_MessageEncoding_DELIMITED { f.delimited = true; }
    }
    return f;
}

// proto2: FeatureSetDefaults' EDITION_LEGACY. scripts/edition_defaults.sh checks
// edition_defaults.binpb against protoc, and
// tests/selfhost/feature_defaults_unit.goose these values against that file.
let proto2_defaults = Features { presence: PRESENCE_EXPLICIT, closed_enum: true, packed_repeated: false, verify_utf8: false, delimited: false };
let proto3_defaults = Features { presence: PRESENCE_IMPLICIT, closed_enum: false, packed_repeated: true, verify_utf8: true, delimited: false };
// Edition 2024 adds defaults only for what protoc enforces itself (enforce_naming_style,
// default_symbol_visibility), so it resolves to these too.
let edition_2023_defaults = Features { presence: PRESENCE_EXPLICIT, closed_enum: false, packed_repeated: true, verify_utf8: true, delimited: false };

// True for a file of syntax "editions", whose features are its own.
fn is_editions(file: FileDesc&) -> bool {
    return google_protobuf::FileDescriptorProto_syntax(file) == "editions";
}

fn defaults_of(file: FileDesc&) -> Features {
    if is_editions(file) { return edition_2023_defaults; }
    if google_protobuf::FileDescriptorProto_has_syntax(file) && google_protobuf::FileDescriptorProto_syntax(file) == "proto3" { return proto3_defaults; }
    return proto2_defaults;
}

// The features of `file`, which its top-level elements inherit.
fn features_of_file(file: FileDesc&) -> Features {
    let opts = google_protobuf::FileDescriptorProto_options(file);
    guard opts else { return defaults_of(file); }
    return features_child(defaults_of(file), google_protobuf::FileOptions_features(opts));
}

// The features of a message whose parent, a file or a message, has `parent`.
fn features_of_message(parent: Features, m: MessageDesc&) -> Features {
    let opts = google_protobuf::DescriptorProto_options(m);
    guard opts else { return parent; }
    return features_child(parent, google_protobuf::MessageOptions_features(opts));
}

// The features of an enum whose parent, a file or a message, has `parent`.
fn features_of_enum(parent: Features, e: EnumDesc&) -> Features {
    let opts = google_protobuf::EnumDescriptorProto_options(e);
    guard opts else { return parent; }
    return features_child(parent, google_protobuf::EnumOptions_features(opts));
}

// The features of a oneof of a message that has `parent`.
fn features_of_oneof(parent: Features, o: OneofDesc&) -> Features {
    let opts = google_protobuf::OneofDescriptorProto_options(o);
    guard opts else { return parent; }
    return features_child(parent, google_protobuf::OneofOptions_features(opts));
}

// The features of field `fd` of `file`, whose parent, its message or its oneof,
// has `parent`. In proto2 and proto3, the label, the type and `packed` say what
// features say elsewhere: descriptor.cc's InferLegacyProtoFeatures.
fn features_of_field(file: FileDesc&, parent: Features, fd: FieldDesc&) -> Features {
    var f = parent;
    let opts = google_protobuf::FieldDescriptorProto_options(fd);
    if opts { f = features_child(f, google_protobuf::FieldOptions_features(opts)); }
    if is_editions(file) { return f; }
    if field_is_required(fd) { f.presence = PRESENCE_REQUIRED; }
    if field_type(fd) == TYPE_GROUP { f.delimited = true; }
    if opts {
        if google_protobuf::FieldOptions_has_packed(opts) { f.packed_repeated = opts.packed; }
    }
    return f;
}
