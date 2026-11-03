// Only aborts under --debug, which the runner always uses.
fn main() {
  let big: i32 = 2147483647;
  let one: i32 = 1;
  let x = big + one;
  if x == 0 { exit(0); }
}
