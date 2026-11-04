// Round-trip test for files with mangled names (gpb-8qn.8): that this
// builds shows foo.v1.proto, my-api.proto and recursive.proto are importable.
// Run: scripts/roundtrip.sh mangled
import pb_wire;
import foo_v1;
import my_api;
import recursive_;

fn main() {
    var d = foo_v1::Dotted { .. };
    if foo_v1::Dotted_decode(embed_file("dotted.bin"), d) != PB_OK || d.n != 7 { abort("dotted"); }
    var h = my_api::Hyphenated { .. };
    if my_api::Hyphenated_decode(embed_file("hyphenated.bin"), h) != PB_OK { abort("hyphenated"); }
    if my_api::Hyphenated_s(h).len != 1 { abort("hyphenated s"); }
    my_api::Hyphenated_clear(h);
    var k = kw::Keyword { .. };
    if kw::Keyword_decode(embed_file("keyword.bin"), k) != PB_OK || !k.b { abort("keyword"); }
    print("mangled round-trip: all passed");
}
