// clear_ of a message field compiles as the first call into the clear cycle
// of a recursive message, with M_clear called nowhere (gpb-gp4.10).
import pb_wire;
import cycles;

fn main() {
    var n = cycles::Node { .. };
    cycles::Node_mutable_child(n).v = 1;
    cycles::Node_clear_child(n);
    if cycles::Node_has_child(n) { abort("clear_child"); }
    print("ok");
}
