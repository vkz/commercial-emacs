#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def read_jsonl(path: Path) -> list[dict]:
    items: list[dict] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        items.append(json.loads(line))
    return items


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--static-jsonl", required=True)
    ap.add_argument("--runtime-subrs", required=True)
    ap.add_argument("--runtime-check", required=True)
    ap.add_argument("--exceptions", required=True)
    args = ap.parse_args(argv)

    static_items = read_jsonl(Path(args.static_jsonl))
    runtime_subrs = json.loads(Path(args.runtime_subrs).read_text(encoding="utf-8"))
    runtime_check = json.loads(Path(args.runtime_check).read_text(encoding="utf-8"))
    exc = json.loads(Path(args.exceptions).read_text(encoding="utf-8"))

    static_subrs = {it["lisp_name"] for it in static_items if it["kind"] in ("subr", "special_form")}
    static_special = {it["lisp_name"] for it in static_items if it["kind"] == "special_form"}

    runtime_subr_names = {it["lisp_name"] for it in runtime_subrs if it["kind"] in ("subr", "special_form")}
    runtime_special = {it["lisp_name"] for it in runtime_subrs if it["kind"] == "special_form"}

    def apply_exceptions(s: set[str], key: str) -> set[str]:
        for name in exc.get(key, []):
            s.discard(name)
        return s

    missing_subrs = sorted(apply_exceptions(static_subrs - runtime_subr_names, "runtime_subrs_missing"))
    extra_subrs = sorted(apply_exceptions(runtime_subr_names - static_subrs, "runtime_subrs_extra"))

    missing_special = sorted(apply_exceptions(static_special - runtime_special, "runtime_special_forms_missing"))
    extra_special = sorted(apply_exceptions(runtime_special - static_special, "runtime_special_forms_extra"))

    unbound_vars = sorted(
        set(runtime_check.get("unbound_variables", [])) - set(exc.get("unbound_variables", []))
    )
    missing_syms = sorted(
        set(runtime_check.get("missing_symbols", [])) - set(exc.get("missing_symbols", []))
    )

    problems: list[str] = []
    if missing_subrs:
        problems.append(f"missing runtime subrs: {len(missing_subrs)}")
    if extra_subrs:
        problems.append(f"extra runtime subrs: {len(extra_subrs)}")
    if missing_special:
        problems.append(f"missing runtime special forms: {len(missing_special)}")
    if extra_special:
        problems.append(f"extra runtime special forms: {len(extra_special)}")
    if unbound_vars:
        problems.append(f"unbound variables: {len(unbound_vars)}")
    if missing_syms:
        problems.append(f"missing symbols: {len(missing_syms)}")

    if problems:
        sys.stderr.write("[inventory:check] FAILED\n")
        for p in problems:
            sys.stderr.write(f"- {p}\n")
        if missing_subrs:
            sys.stderr.write(f"  example missing subr: {missing_subrs[0]}\n")
        if extra_subrs:
            sys.stderr.write(f"  example extra subr: {extra_subrs[0]}\n")
        if unbound_vars:
            sys.stderr.write(f"  example unbound var: {unbound_vars[0]}\n")
        if missing_syms:
            sys.stderr.write(f"  example missing sym: {missing_syms[0]}\n")
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
