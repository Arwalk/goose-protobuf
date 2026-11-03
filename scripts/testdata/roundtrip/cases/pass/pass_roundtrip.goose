// Passes: five.bin decodes to a = 5.
import pb_wire;
import pass;

fn main() {
    var m = pass::M { .. };
    if pass::M_decode(embed_file("five.bin"), m) != PB_OK || m.a != 5 { abort("five.bin"); }
}
