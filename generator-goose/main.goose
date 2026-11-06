// protoc-gen-goose: protoc plugin that emits Goose code for the protobuf
// binary wire format. scripts/build_plugin.sh builds it.

import os;
import pb_wire;
import support;
import generate;

// The version of this plugin, its runtime and the well-known types (decision 0012).
// RELEASING.md says when it changes.
const plugin_version = "0.1.0-dev";

const usage = """
    Usage: protoc --goose_out=DIR file.proto

    protoc-gen-goose is a protoc plugin, which protoc runs with a request on stdin.
    It generates Goose code for the protobuf binary wire format. protoc finds it on
    your PATH, or with --plugin=protoc-gen-goose=PATH. It takes no parameter.

    Options:
      -h, --help   print this and exit
      --version    print the version and exit

    """;

// In plugin_stdio.c, as Goose's os module has neither.
extern fn plugin_stdio_binary();
extern fn plugin_stdin_is_terminal() -> i32;

fn print_version() {
    write_stdout(str("protoc-gen-goose ", plugin_version, " (runtime abi ", runtime_abi, ")\n"));
}

// Answers what a person typed, and exits. protoc passes no argument, so it never
// gets here unless its stdin is a terminal, where reading would wait for ever.
fn handle_command_line() {
    let argv = args();
    if argv.len > 2 {
        write_stderr(str("protoc-gen-goose: unknown argument: ", argv[2], "\n", usage));
        exit(2);
    }
    if argv.len == 2 {
        let a = argv[1];
        if a == "--version" {
            print_version();
        } else if a == "--help" || a == "-h" {
            write_stdout(usage);
        } else {
            write_stderr(str("protoc-gen-goose: unknown argument: ", a, "\n", usage));
            exit(2);
        }
        flush_stdout();
        exit(0);
    }
    if plugin_stdin_is_terminal() != 0 {
        write_stderr(usage);
        exit(2);
    }
}

fn main() {
    handle_command_line();
    plugin_stdio_binary();
    var input: u8[>..] = [];
    read_stdin(input);
    var out: u8[>..] = [];
    let err = run_plugin(input, out);
    if err != PB_OK {
        write_stderr(str("protoc-gen-goose: failed to decode CodeGeneratorRequest: ", pb_error_text(err), "\n"));
        exit(1);
    }
    write_stdout(out);
    flush_stdout();
}
