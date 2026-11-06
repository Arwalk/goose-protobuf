// generator-goose/features.goose: how features resolve. The defaults themselves are
// in feature_defaults_unit.goose. Run by scripts/selfhost_tests.sh.
import pb_wire;
import google.protobuf.descriptor;
import features;
import unit_support;

let EXPLICIT = google_protobuf::FeatureSet_FieldPresence_EXPLICIT;
let IMPLICIT = google_protobuf::FeatureSet_FieldPresence_IMPLICIT;
let LEGACY_REQUIRED = google_protobuf::FeatureSet_FieldPresence_LEGACY_REQUIRED;
let OPEN = google_protobuf::FeatureSet_EnumType_OPEN;
let CLOSED = google_protobuf::FeatureSet_EnumType_CLOSED;
let PACKED = google_protobuf::FeatureSet_RepeatedFieldEncoding_PACKED;
let EXPANDED = google_protobuf::FeatureSet_RepeatedFieldEncoding_EXPANDED;
let VERIFY = google_protobuf::FeatureSet_Utf8Validation_VERIFY;
let NO_VERIFY = google_protobuf::FeatureSet_Utf8Validation_NONE;
let LENGTH_PREFIXED = google_protobuf::FeatureSet_MessageEncoding_LENGTH_PREFIXED;
let DELIMITED = google_protobuf::FeatureSet_MessageEncoding_DELIMITED;

fn same(a: Features, b: Features) -> bool {
    return a.presence == b.presence && a.closed_enum == b.closed_enum && a.packed_repeated == b.packed_repeated
        && a.verify_utf8 == b.verify_utf8 && a.delimited == b.delimited;
}

fn with_presence(f: Features, v: i32) -> Features {
    var s = FeatureSet { .. };
    google_protobuf::FeatureSet_set_field_presence(s, v);
    return features_child(f, s);
}

fn with_enum_type(f: Features, v: i32) -> Features {
    var s = FeatureSet { .. };
    google_protobuf::FeatureSet_set_enum_type(s, v);
    return features_child(f, s);
}

fn with_encoding(f: Features, v: i32) -> Features {
    var s = FeatureSet { .. };
    google_protobuf::FeatureSet_set_repeated_field_encoding(s, v);
    return features_child(f, s);
}

fn with_utf8(f: Features, v: i32) -> Features {
    var s = FeatureSet { .. };
    google_protobuf::FeatureSet_set_utf8_validation(s, v);
    return features_child(f, s);
}

fn with_message_encoding(f: Features, v: i32) -> Features {
    var s = FeatureSet { .. };
    google_protobuf::FeatureSet_set_message_encoding(s, v);
    return features_child(f, s);
}

fn syntax_picks_the_defaults() {
    var none = FileDesc { .. };
    var p2 = FileDesc { .. };
    google_protobuf::FileDescriptorProto_set_syntax(p2, "proto2");
    var p3 = FileDesc { .. };
    google_protobuf::FileDescriptorProto_set_syntax(p3, "proto3");
    var ed = FileDesc { .. };
    google_protobuf::FileDescriptorProto_set_syntax(ed, "editions");
    google_protobuf::FileDescriptorProto_set_edition(ed, google_protobuf::Edition_EDITION_2023);
    expect(same(proto2_defaults, features_of_file(none)), "no syntax is proto2");
    expect(same(proto2_defaults, features_of_file(p2)), "proto2");
    expect(same(proto3_defaults, features_of_file(p3)), "proto3");
    expect(same(edition_2023_defaults, features_of_file(ed)), "edition 2023");
    expect(is_editions(ed), "editions is editions");
    expect(!is_editions(p3), "proto3 is not editions");
}

fn each_feature_resolves_through_each_value() {
    let base = edition_2023_defaults;
    expect(with_presence(base, IMPLICIT).presence == PRESENCE_IMPLICIT, "implicit");
    expect(with_presence(base, LEGACY_REQUIRED).presence == PRESENCE_REQUIRED, "required");
    expect(with_presence(proto3_defaults, EXPLICIT).presence == PRESENCE_EXPLICIT, "explicit");
    expect(with_enum_type(base, CLOSED).closed_enum, "closed");
    expect(!with_enum_type(proto2_defaults, OPEN).closed_enum, "open");
    expect(!with_encoding(base, EXPANDED).packed_repeated, "expanded");
    expect(with_encoding(proto2_defaults, PACKED).packed_repeated, "packed");
    expect(!with_utf8(base, NO_VERIFY).verify_utf8, "no verify");
    expect(with_utf8(proto2_defaults, VERIFY).verify_utf8, "verify");
    expect(with_message_encoding(base, DELIMITED).delimited, "delimited");
    expect(!with_message_encoding(with_message_encoding(base, DELIMITED), LENGTH_PREFIXED).delimited, "length prefixed");
    // An element with no overrides, or the unknown values, changes nothing.
    expect(same(base, features_child(base, null)), "no set");
    var empty = FeatureSet { .. };
    expect(same(base, features_child(base, empty)), "empty set");
    expect(same(base, with_presence(base, 0)), "unknown presence");
    expect(same(base, with_enum_type(base, 0)), "unknown enum type");
    expect(same(base, with_encoding(base, 0)), "unknown encoding");
    expect(same(base, with_utf8(base, 0)), "unknown utf8");
    expect(same(base, with_message_encoding(base, 0)), "unknown message encoding");
}

fn features_are_inherited_through_each_level() {
    var file = FileDesc { .. };
    google_protobuf::FileDescriptorProto_set_syntax(file, "editions");
    google_protobuf::FileDescriptorProto_set_edition(file, google_protobuf::Edition_EDITION_2023);
    let file_set .= google_protobuf::FileOptions_mutable_features(google_protobuf::FileDescriptorProto_mutable_options(file));
    google_protobuf::FeatureSet_set_field_presence(file_set, IMPLICIT);
    google_protobuf::FeatureSet_set_enum_type(file_set, CLOSED);
    google_protobuf::FeatureSet_set_utf8_validation(file_set, NO_VERIFY);
    let at_file = features_of_file(file);
    expect(at_file.presence == PRESENCE_IMPLICIT, "file presence");
    expect(at_file.closed_enum, "file enum type");

    // A message inherits the file, overriding one feature; a nested one both.
    var outer = MessageDesc { .. };
    google_protobuf::FeatureSet_set_field_presence(google_protobuf::MessageOptions_mutable_features(google_protobuf::DescriptorProto_mutable_options(outer)), EXPLICIT);
    let at_outer = features_of_message(at_file, outer);
    expect(at_outer.presence == PRESENCE_EXPLICIT, "message overrides");
    expect(!at_outer.verify_utf8, "message inherits");
    var nested = MessageDesc { .. };
    google_protobuf::FeatureSet_set_utf8_validation(google_protobuf::MessageOptions_mutable_features(google_protobuf::DescriptorProto_mutable_options(nested)), VERIFY);
    let at_nested = features_of_message(at_outer, nested);
    expect(at_nested.presence == PRESENCE_EXPLICIT, "nested inherits its message");
    expect(at_nested.verify_utf8, "nested overrides");
    expect(at_nested.closed_enum, "nested inherits the file");
    var plain = MessageDesc { .. };
    expect(same(at_outer, features_of_message(at_outer, plain)), "a plain message");

    // An enum inherits the file or a message, and overrides.
    var open_e = EnumDesc { .. };
    google_protobuf::FeatureSet_set_enum_type(google_protobuf::EnumOptions_mutable_features(google_protobuf::EnumDescriptorProto_mutable_options(open_e)), OPEN);
    var plain_e = EnumDesc { .. };
    expect(!features_of_enum(at_file, open_e).closed_enum, "enum overrides");
    expect(features_of_enum(at_nested, plain_e).closed_enum, "enum inherits");

    // A oneof inherits its message, and a field its oneof or message.
    var oneof = OneofDesc { .. };
    google_protobuf::FeatureSet_set_message_encoding(google_protobuf::OneofOptions_mutable_features(google_protobuf::OneofDescriptorProto_mutable_options(oneof)), DELIMITED);
    let at_oneof = features_of_oneof(at_outer, oneof);
    expect(at_oneof.delimited, "oneof overrides");
    var plain_f = FieldDesc { .. };
    google_protobuf::FieldDescriptorProto_set_name(plain_f, "a");
    google_protobuf::FieldDescriptorProto_set_type(plain_f, TYPE_MESSAGE);
    expect(features_of_field(file, at_oneof, plain_f).delimited, "field inherits its oneof");
    var own_f = FieldDesc { .. };
    google_protobuf::FieldDescriptorProto_set_name(own_f, "b");
    google_protobuf::FieldDescriptorProto_set_type(own_f, TYPE_MESSAGE);
    let own_set .= google_protobuf::FieldOptions_mutable_features(google_protobuf::FieldDescriptorProto_mutable_options(own_f));
    google_protobuf::FeatureSet_set_message_encoding(own_set, LENGTH_PREFIXED);
    google_protobuf::FeatureSet_set_field_presence(own_set, LEGACY_REQUIRED);
    google_protobuf::FeatureSet_set_repeated_field_encoding(own_set, EXPANDED);
    let at_own = features_of_field(file, at_oneof, own_f);
    expect(!at_own.delimited, "field overrides encoding");
    expect(at_own.presence == PRESENCE_REQUIRED, "field overrides presence");
    expect(!at_own.packed_repeated, "field overrides packing");
}

fn legacy_syntax_infers_features() {
    var p2 = FileDesc { .. };
    google_protobuf::FileDescriptorProto_set_syntax(p2, "proto2");
    var p3 = FileDesc { .. };
    google_protobuf::FileDescriptorProto_set_syntax(p3, "proto3");
    var ed = FileDesc { .. };
    google_protobuf::FileDescriptorProto_set_syntax(ed, "editions");
    google_protobuf::FileDescriptorProto_set_edition(ed, google_protobuf::Edition_EDITION_2023);
    var req = FieldDesc { .. };
    set_field(req, "r", 1, LABEL_REQUIRED, TYPE_INT32);
    var grp = FieldDesc { .. };
    set_field(grp, "g", 2, LABEL_OPTIONAL, TYPE_GROUP);
    var pk = FieldDesc { .. };
    set_field(pk, "p", 3, LABEL_REPEATED, TYPE_INT32);
    google_protobuf::FieldOptions_set_packed(google_protobuf::FieldDescriptorProto_mutable_options(pk), true);
    var unpk = FieldDesc { .. };
    set_field(unpk, "u", 4, LABEL_REPEATED, TYPE_INT32);
    google_protobuf::FieldOptions_set_packed(google_protobuf::FieldDescriptorProto_mutable_options(unpk), false);
    var plain = FieldDesc { .. };
    set_field(plain, "x", 5, LABEL_REPEATED, TYPE_INT32);
    let f2 = features_of_file(p2);
    let f3 = features_of_file(p3);
    expect(features_of_field(p2, f2, req).presence == PRESENCE_REQUIRED, "a required label");
    expect(features_of_field(p2, f2, grp).delimited, "a group");
    expect(features_of_field(p2, f2, pk).packed_repeated, "packed in proto2");
    expect(!features_of_field(p2, f2, plain).packed_repeated, "proto2 does not pack");
    expect(features_of_field(p3, f3, plain).packed_repeated, "proto3 packs");
    expect(!features_of_field(p3, f3, unpk).packed_repeated, "unpacked in proto3");
    expect(features_of_field(p3, f3, plain).presence == PRESENCE_IMPLICIT, "proto3 presence");
    // Editions say it with features only.
    expect(features_of_field(ed, features_of_file(ed), req).presence == PRESENCE_EXPLICIT, "editions ignore the label");
    expect(!features_of_field(ed, features_of_file(ed), grp).delimited, "editions ignore the type");
}

fn main() {
    syntax_picks_the_defaults();
    each_feature_resolves_through_each_value();
    features_are_inherited_through_each_level();
    legacy_syntax_infers_features();
}
