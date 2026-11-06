// generator-goose/features.goose holds the edition feature defaults as constants.
// edition_defaults.binpb is what protoc computes, which scripts/edition_defaults.sh
// checks: this decodes it with the bindings and compares every edition's defaults
// with the constants. Run by scripts/selfhost_tests.sh.
import pb_wire;
import google.protobuf.descriptor;
import features;

let EDITION_LEGACY = google_protobuf::Edition_EDITION_LEGACY;
let EDITION_PROTO2 = google_protobuf::Edition_EDITION_PROTO2;
let EDITION_PROTO3 = google_protobuf::Edition_EDITION_PROTO3;
let EDITION_2023 = google_protobuf::Edition_EDITION_2023;
let EDITION_2024 = google_protobuf::Edition_EDITION_2024;

// Each feature is set in exactly one of overridable_features and fixed_features.
// Starting from what cannot match makes a feature protoc leaves out fail too.
fn opposite_of(want: Features) -> Features {
    var presence: i32 = PRESENCE_IMPLICIT;
    if want.presence == PRESENCE_IMPLICIT { presence = PRESENCE_EXPLICIT; }
    return Features {
        presence: presence,
        closed_enum: !want.closed_enum,
        packed_repeated: !want.packed_repeated,
        verify_utf8: !want.verify_utf8,
        delimited: !want.delimited,
    };
}

fn check_feature(edition: i32, name: const u8[:], matches: bool) {
    if !matches { abort(str("edition ", edition, ": ", name, " differs from protoc's")); }
}

fn check_edition(d: google_protobuf::FeatureSetDefaults_FeatureSetEditionDefault&, want: Features) {
    let overridable = google_protobuf::FeatureSetDefaults_FeatureSetEditionDefault_overridable_features(d);
    let fixed = google_protobuf::FeatureSetDefaults_FeatureSetEditionDefault_fixed_features(d);
    let got = features_child(features_child(opposite_of(want), overridable), fixed);
    check_feature(d.edition, "field_presence", got.presence == want.presence);
    check_feature(d.edition, "enum_type", got.closed_enum == want.closed_enum);
    check_feature(d.edition, "repeated_field_encoding", got.packed_repeated == want.packed_repeated);
    check_feature(d.edition, "utf8_validation", got.verify_utf8 == want.verify_utf8);
    check_feature(d.edition, "message_encoding", got.delimited == want.delimited);
}

var defaults = google_protobuf::FeatureSetDefaults { .. };

fn main() {
    let err = google_protobuf::FeatureSetDefaults_decode(embed_file("edition_defaults.binpb"), defaults);
    if err != PB_OK { abort(str("decode error ", err)); }
    if defaults.minimum_edition != EDITION_PROTO2 { abort(str("minimum edition ", defaults.minimum_edition)); }
    if defaults.maximum_edition != EDITION_2024 { abort(str("maximum edition ", defaults.maximum_edition)); }
    let count = google_protobuf::FeatureSetDefaults_defaults_len(defaults);
    if count != 4 { abort(str(count, " editions, not 4")); }
    var seen_legacy = false;
    var seen_proto3 = false;
    var seen_2023 = false;
    var seen_2024 = false;
    for i in count {
        let d .= google_protobuf::FeatureSetDefaults_defaults_at(defaults, i);
        if d.edition == EDITION_LEGACY {
            check_edition(d, proto2_defaults);
            seen_legacy = true;
        } else if d.edition == EDITION_PROTO3 {
            check_edition(d, proto3_defaults);
            seen_proto3 = true;
        } else if d.edition == EDITION_2023 {
            check_edition(d, edition_2023_defaults);
            seen_2023 = true;
        } else if d.edition == EDITION_2024 {
            check_edition(d, edition_2023_defaults);
            seen_2024 = true;
        } else {
            abort(str("unexpected edition ", d.edition));
        }
    }
    if !(seen_legacy && seen_proto3 && seen_2023 && seen_2024) { abort("an edition is missing"); }
}
