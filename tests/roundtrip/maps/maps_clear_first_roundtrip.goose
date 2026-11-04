// clear_ of a map field compiles as the first call into the clear cycle of a
// recursive message, with M_clear called nowhere.
import pb_wire;
import maps;

fn main() {
    var m = maps::Maps { .. };
    maps::Maps_clear_self(m);
    print("ok");
}
