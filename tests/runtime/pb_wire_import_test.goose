// Tests import the runtime as a directory package: Goose resolves a plain
// `import` only below the root file's directory.
import pb_wire from "../../runtime";

fn main() {
  // Placeholder until the pb_wire primitives land (gpb-41j.1): proves the
  // runtime typechecks and links from a test.
  if 1 + 1 != 2 { abort("unreachable"); }
}
