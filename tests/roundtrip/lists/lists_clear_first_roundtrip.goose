// clear_ of a repeated message field compiles as the first call into the
// clear cycle of a recursive message, with M_clear called nowhere (gpb-gp4.10).
import pb_wire;
import lists;

fn main() {
    var t = lists::Tree { .. };
    lists::Tree_add_children(t);
    lists::Tree_clear_children(t);
    if lists::Tree_children(t).len != 0 { abort("clear_children"); }
    print("ok");
}
