#!/usr/bin/env python3
"""Checks docs/generated-code.md against tests/golden/.

A comment `<!-- golden: <dir> <message> [field] -->` before a table says which
generated code the table describes. In it, M is the message and f or o the field.

- Each row's function must be in tests/golden/<dir>/, with those parameter names and
  that return type. In a return type, S, T, K and V stand for any type.
- With a field, each function generated for that field must have a row.
- Every other M_ name on the page must be one a table lists.
- Every pb_ or PB_ name on the page must be public (decision 0012).

Usage: scripts/check_reference.py [file]
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBLIC = re.compile(r"^(PB_OK|PB_ERR_\*|PB_ERR_[A-Z0-9_]+|PB_MAX_DEPTH|pb_error_text|pb_none|pb_wire)$")
MARK = re.compile(r"^<!-- golden: (\S+) (\S+)(?: (\S+))? -->$")
ROW = re.compile(r"^\| `(M_\w+)\(([^)]*)\)(?: -> ([^`]+))?` \|")
PREFIXES = ("set_", "has_", "clear_", "mutable_", "add_")


def functions(golden_dir):
    """Maps the name of each function in a golden directory to (params, return type)."""
    found = {}
    for path in sorted((ROOT / "tests/golden" / golden_dir).rglob("*.goose")):
        for m in re.finditer(r"^(?:recursive )?fn (\w+)\(([^)]*)\)(?: -> ([^{]*?))? \{", path.read_text(), re.M):
            params = [p.split(":")[0].strip() for p in m.group(2).split(", ") if p]
            found[m.group(1)] = (params, m.group(3) or "")
    return found


def concrete(template, message, field):
    """M_set_f with message Maps and field si is Maps_set_si."""
    parts = template.split("_")
    parts[0] = message
    return "_".join(field if p in ("f", "o") and field else p for p in parts)


def type_matches(doc, got):
    pattern = re.escape(doc)
    for placeholder in "STKV":
        pattern = re.sub(rf"\b{placeholder}\b", r"[\\w:\\[\\]]+", pattern)
    return re.fullmatch(pattern, got) is not None


def field_functions(funcs, message, field):
    """The functions of a field: Maps_si_at, Maps_clear_si, and so on."""
    prefixes = "|".join(PREFIXES)
    name = re.compile(rf"^{re.escape(message)}_(?:{prefixes})?{re.escape(field)}(?:_\w+)?$")
    return {n for n, (params, _) in funcs.items() if name.match(n) and params[:1] == ["m"]}


def check(text):
    problems = []
    listed = set()
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        mark = MARK.match(lines[i])
        i += 1
        if not mark:
            continue
        golden_dir, message, field = mark.groups()
        funcs = functions(golden_dir)
        if not funcs:
            problems.append(f"line {i}: no golden code in tests/golden/{golden_dir}")
        seen = set()
        while i < len(lines) and lines[i].startswith("|"):
            row = ROW.match(lines[i])
            where = f"line {i + 1}"
            i += 1
            if not row:
                continue
            template, params, result = row.groups()
            listed.add(template)
            name = concrete(template, message, field)
            seen.add(name)
            if name not in funcs:
                problems.append(f"{where}: {template} is {name}, which tests/golden/{golden_dir} does not have")
                continue
            got_params, got_result = funcs[name]
            want_params = [p.strip() for p in params.split(",") if p.strip()]
            if want_params != got_params:
                problems.append(f"{where}: {template} takes ({', '.join(got_params)})")
            if not type_matches(result or "", got_result):
                problems.append(f"{where}: {template} returns '{got_result}'")
        if field:
            for name in sorted(field_functions(funcs, message, field) - seen):
                problems.append(f"table before line {i + 1}: no row for {name}")
    for token in sorted(set(re.findall(r"\bM_\w+", text))):
        if token not in listed:
            problems.append(f"{token} is on the page, but in no table")
    for token in sorted(set(re.findall(r"\b(?:pb|PB)_\w*\*?", text))):
        if token not in ("pb_", "PB_") and not PUBLIC.match(token):
            problems.append(f"{token} is not public")
    return problems


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs/generated-code.md"
    problems = check(path.read_text())
    for p in problems:
        print(f"FAIL {path.name}: {p}")
    if problems:
        return 1
    print(f"ok   {path.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
