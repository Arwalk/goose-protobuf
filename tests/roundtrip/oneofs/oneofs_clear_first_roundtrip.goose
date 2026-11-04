// clear_<oneof> compiles as the first call into the clear cycle of a
// recursive message, with M_clear called nowhere (gpb-gp4.3).
import pb_wire;
import oneofs;

fn main() {
    var m = oneofs::Choice { .. };
    oneofs::Choice_clear_pick(m);
    print("ok");
}
