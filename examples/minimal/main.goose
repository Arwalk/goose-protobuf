import pb_wire from "../..";
import greeting;

fn main() {
    var hello = greeting::Greeting { .. };
    greeting::Greeting_set_text(hello, "hi");
    hello.count = 3;

    var bytes: u8[>..] = [];
    greeting::Greeting_encode(hello, bytes);
    greeting::Greeting_clear(hello);

    var back = greeting::Greeting { .. };
    let err = greeting::Greeting_decode(bytes, back);
    if err != PB_OK { abort(str("decode failed: ", pb_error_text(err))); }
    print(greeting::Greeting_text(back), " x ", back.count, " in ", bytes.len, " bytes");
    greeting::Greeting_clear(back);
}
