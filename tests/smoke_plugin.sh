#!/usr/bin/env bash
# Smoke test for protoc-gen-goose:
# - protoc runs the plugin on tests/protos/smoke.proto, exits 0, and writes
#   exactly smoke.goose (its content is checked by scripts/golden.sh);
# - a malformed CodeGeneratorRequest makes the plugin exit nonzero with a
#   message on stderr;
# - --version and --help answer without reading stdin, an unknown argument is
#   refused, and a run on a terminal prints usage instead of waiting for a request.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -d "$root/.tools/bin" ]]; then
  export PATH="$root/.tools/bin:$PATH"
fi

"$root/scripts/build_plugin.sh"
plugin="$root/build/protoc-gen-goose"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/out"

protoc --plugin=protoc-gen-goose="$plugin" --goose_out="$tmp/out" \
  -I "$root/tests/protos" "$root/tests/protos/smoke.proto"

if [[ "$(ls -A "$tmp/out")" != "smoke.goose" ]]; then
  echo "FAIL: plugin wrote, instead of smoke.goose:" >&2
  ls -A "$tmp/out" >&2
  exit 1
fi
echo "PASS: protoc exits 0 and writes smoke.goose"

status=0
printf '\x0a\x05a' | "$plugin" >"$tmp/stdout" 2>"$tmp/stderr" || status=$?
if [[ $status -eq 0 ]]; then
  echo "FAIL: malformed request exited 0" >&2
  exit 1
fi
if [[ ! -s "$tmp/stderr" ]]; then
  echo "FAIL: malformed request printed nothing on stderr" >&2
  exit 1
fi
echo "PASS: malformed request exits $status: $(cat "$tmp/stderr")"

python3 - "$plugin" <<'PY'
import os, pty, re, select, subprocess, sys, time

plugin = sys.argv[1]


def check_option(what, want_status, want_out, want_err, *args):
    """Runs the plugin with a stdin that stays open, so that reading it would hang."""
    p = subprocess.Popen([plugin, *args], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, text=True)
    try:
        # Not communicate(), which would close stdin.
        deadline = time.time() + 10
        while p.poll() is None and time.time() < deadline:
            time.sleep(0.01)
        if p.poll() is None:
            p.kill()
            sys.exit(f"FAIL: {what}: still waiting for input")
        out, err = p.stdout.read(), p.stderr.read()
    finally:
        p.stdin.close()
    if p.returncode != want_status or not re.search(want_out, out, re.M) or not re.search(want_err, err, re.M):
        sys.exit(f"FAIL: {what}: exit {p.returncode}, stdout: {out!r}, stderr: {err!r}")
    print(f"PASS: {what}")


check_option("--version prints the version", 0, r"^protoc-gen-goose \d[\d.]*\S* \(runtime abi \d+\)$", "", "--version")
check_option("--help prints usage", 0, "^Usage:", "", "--help")
check_option("-h prints usage", 0, "^Usage:", "", "-h")
check_option("an unknown argument is refused", 2, "", "unknown argument: --nope", "--nope")

# On a terminal, usage on stderr, and it does not wait for a request.
pid, fd = pty.fork()
if pid == 0:
    os.execv(plugin, [plugin])
out, deadline, status = b"", time.time() + 10, None
while time.time() < deadline:
    if select.select([fd], [], [], 0.1)[0]:
        try:
            out += os.read(fd, 4096)
        except OSError:
            pass
    done, st = os.waitpid(pid, os.WNOHANG)
    if done:
        status = os.waitstatus_to_exitcode(st)
        break
if status is None:
    os.kill(pid, 9)
    sys.exit(f"FAIL: a terminal run still waits for input: {out!r}")
if status != 2 or b"Usage:" not in out:
    sys.exit(f"FAIL: a terminal run: exit {status}, printed {out!r}")
print("PASS: a terminal run prints usage")
PY
