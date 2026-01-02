#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator, Optional


@dataclass(frozen=True)
class SourceLoc:
    path: str
    line: int


def _is_ident_char(ch: str) -> bool:
    return ch.isalnum() or ch == "_"


def _parse_c_string_literal(token: str) -> str:
    token = token.strip()
    if not token.startswith('"'):
        raise ValueError(f"expected C string literal, got: {token!r}")

    out: list[str] = []
    i = 1
    while i < len(token):
        ch = token[i]
        if ch == '"':
            return "".join(out)
        if ch == "\\":
            i += 1
            if i >= len(token):
                raise ValueError(f"unterminated escape in: {token!r}")
            esc = token[i]
            mapping = {
                "n": "\n",
                "t": "\t",
                "r": "\r",
                "\\": "\\",
                '"': '"',
                "0": "\0",
            }
            out.append(mapping.get(esc, esc))
        else:
            out.append(ch)
        i += 1

    raise ValueError(f"unterminated string literal: {token!r}")


def _parse_int_like(token: str) -> Optional[int]:
    token = token.strip()
    if re.fullmatch(r"[0-9]+", token):
        return int(token, 10)
    return None


def _parse_c_int_literal(token: str) -> int:
    token = token.strip()
    if re.fullmatch(r"0[xX][0-9a-fA-F]+", token):
        return int(token, 16)
    if re.fullmatch(r"0[0-7]+", token):
        return int(token, 8)
    if re.fullmatch(r"[0-9]+", token):
        return int(token, 10)
    raise ValueError(f"unrecognized int literal: {token!r}")


class Scanner:
    def __init__(self, text: str) -> None:
        self.text = text
        self.i = 0
        self.line = 1
        self.state = "normal"  # normal|string|char|line_comment|block_comment

    def _peek(self, n: int = 0) -> str:
        j = self.i + n
        if j < 0 or j >= len(self.text):
            return ""
        return self.text[j]

    def _advance(self, n: int = 1) -> None:
        for _ in range(n):
            if self.i >= len(self.text):
                return
            if self.text[self.i] == "\n":
                self.line += 1
            self.i += 1

    def _skip_string(self, quote: str) -> None:
        self._advance()  # opening quote
        while self.i < len(self.text):
            ch = self._peek()
            if ch == "\\":
                self._advance(2)
                continue
            if ch == quote:
                self._advance()
                return
            self._advance()

    def _skip_line_comment(self) -> None:
        while self.i < len(self.text) and self._peek() != "\n":
            self._advance()
        self._advance()

    def _skip_block_comment(self) -> None:
        self._advance(2)  # /*
        while self.i < len(self.text):
            if self._peek() == "*" and self._peek(1) == "/":
                self._advance(2)
                return
            self._advance()

    def _parse_args(self, want_n: int) -> list[str]:
        # Expects current position at first char after '('.
        args: list[str] = []
        buf: list[str] = []
        depth = 0

        def flush() -> None:
            arg = "".join(buf).strip()
            args.append(arg)
            buf.clear()

        while self.i < len(self.text):
            ch = self._peek()

            if ch == '"' and self.state == "normal":
                start = self.i
                self._skip_string('"')
                buf.append(self.text[start : self.i])
                continue

            if ch == "'" and self.state == "normal":
                start = self.i
                self._skip_string("'")
                buf.append(self.text[start : self.i])
                continue

            if ch == "/" and self._peek(1) == "/" and self.state == "normal":
                self._skip_line_comment()
                continue

            if ch == "/" and self._peek(1) == "*" and self.state == "normal":
                self._skip_block_comment()
                continue

            if ch in "([{":
                depth += 1
                buf.append(ch)
                self._advance()
                continue

            if ch in ")]}":
                if ch == ")" and depth == 0:
                    flush()
                    self._advance()
                    return args[:want_n]
                depth = max(0, depth - 1)
                buf.append(ch)
                self._advance()
                continue

            if ch == "," and depth == 0:
                flush()
                self._advance()
                if len(args) >= want_n:
                    return args[:want_n]
                continue

            buf.append(ch)
            self._advance()

        raise ValueError("unterminated macro call while parsing args")

    def iter_macro_calls(
        self, macro: str, want_n: int
    ) -> Iterator[tuple[int, list[str]]]:
        text = self.text
        mlen = len(macro)

        while self.i < len(text):
            ch = self._peek()

            if self.state == "normal" and ch == "/" and self._peek(1) == "/":
                self.state = "line_comment"
                self._skip_line_comment()
                self.state = "normal"
                continue

            if self.state == "normal" and ch == "/" and self._peek(1) == "*":
                self.state = "block_comment"
                self._skip_block_comment()
                self.state = "normal"
                continue

            if self.state == "normal" and ch == '"':
                self.state = "string"
                self._skip_string('"')
                self.state = "normal"
                continue

            if self.state == "normal" and ch == "'":
                self.state = "char"
                self._skip_string("'")
                self.state = "normal"
                continue

            if self.state == "normal":
                if text.startswith(macro, self.i):
                    prev = self._peek(-1) if self.i > 0 else ""
                    nxt = self._peek(mlen)
                    if (prev and _is_ident_char(prev)) or (
                        nxt and _is_ident_char(nxt)
                    ):
                        self._advance()
                        continue

                    start_line = self.line
                    j = self.i + mlen
                    while j < len(text) and text[j].isspace():
                        j += 1
                    if j < len(text) and text[j] == "(":
                        self.i = j + 1
                        args = self._parse_args(want_n)
                        yield (start_line, args)
                        continue

            self._advance()


def _walk_src(root: Path) -> Iterable[Path]:
    src = root / "src"
    for path in sorted(src.rglob("*")):
        if path.suffix in (".c", ".h"):
            yield path


def _record(
    *,
    kind: str,
    lisp_name: str,
    c_name: str,
    loc: SourceLoc,
    arity_raw_min: Optional[str] = None,
    arity_raw_max: Optional[str] = None,
    arity_min: Optional[int] = None,
    arity_max: Optional[int] = None,
    opcode: Optional[int] = None,
) -> dict:
    rec: dict = {
        "kind": kind,
        "lisp_name": lisp_name,
        "c_name": c_name,
        "source": {"path": loc.path, "line": loc.line},
    }
    if arity_raw_min is not None or arity_raw_max is not None:
        rec["arity"] = {
            "raw_min": arity_raw_min,
            "raw_max": arity_raw_max,
            "min": arity_min,
            "max": arity_max,
        }
    if opcode is not None:
        rec["opcode"] = opcode
    return rec


def extract_static_inventory(root: Path) -> list[dict]:
    records: list[dict] = []

    for path in _walk_src(root):
        rel = os.path.relpath(path, root).replace(os.sep, "/")
        text = path.read_text(encoding="utf-8", errors="replace")

        sc = Scanner(text)
        for line, args in sc.iter_macro_calls("DEFUN", want_n=5):
            if len(args) < 5:
                continue
            try:
                lisp_name = _parse_c_string_literal(args[0])
            except ValueError:
                continue
            c_name = args[1].strip()
            raw_min = args[3].strip()
            raw_max = args[4].strip()
            kind = "special_form" if raw_max == "UNEVALLED" else "subr"
            records.append(
                _record(
                    kind=kind,
                    lisp_name=lisp_name,
                    c_name=c_name,
                    loc=SourceLoc(rel, line),
                    arity_raw_min=raw_min,
                    arity_raw_max=raw_max,
                    arity_min=_parse_int_like(raw_min),
                    arity_max=_parse_int_like(raw_max),
                )
            )

        sc = Scanner(text)
        for line, args in sc.iter_macro_calls("DEFSYM", want_n=2):
            if len(args) < 2:
                continue
            c_name = args[0].strip()
            try:
                lisp_name = _parse_c_string_literal(args[1])
            except ValueError:
                continue
            records.append(
                _record(
                    kind="symbol",
                    lisp_name=lisp_name,
                    c_name=c_name,
                    loc=SourceLoc(rel, line),
                )
            )

        # DEFVAR_* family: DEFVAR_LISP, DEFVAR_BOOL, DEFVAR_INT, ...
        # We scan for the prefix and then parse arguments.
        # NOTE: we intentionally limit ourselves to src/ (not lib-src/).
        for m in re.finditer(r"\bDEFVAR_[A-Z0-9_]+\b", text):
            macro = m.group(0)
            sc = Scanner(text)
            sc.i = m.start()
            sc.line = text.count("\n", 0, m.start()) + 1
            for line, args in sc.iter_macro_calls(macro, want_n=2):
                if len(args) < 2:
                    continue
                try:
                    lisp_name = _parse_c_string_literal(args[0])
                except ValueError:
                    continue
                c_name = args[1].strip()
                records.append(
                    _record(
                        kind="variable",
                        lisp_name=lisp_name,
                        c_name=c_name,
                        loc=SourceLoc(rel, line),
                    )
                )
                break

    # Bytecode opcodes are defined via BYTE_CODES in src/bytecode.c.
    bytecode_path = root / "src" / "bytecode.c"
    if bytecode_path.exists():
        rel = os.path.relpath(bytecode_path, root).replace(os.sep, "/")
        lines = bytecode_path.read_text(encoding="utf-8", errors="replace").splitlines()
        for idx, line in enumerate(lines, start=1):
            m = re.search(r"\bDEFINE\s*\(\s*([A-Za-z0-9_]+)\s*,\s*([0-9A-Fa-fxX]+)\s*\)", line)
            if not m:
                continue
            opname = m.group(1)
            opval = _parse_c_int_literal(m.group(2))
            records.append(
                _record(
                    kind="bytecode_op",
                    lisp_name=opname,
                    c_name=opname,
                    loc=SourceLoc(rel, idx),
                    opcode=opval,
                )
            )

    # Deduplicate (comment matches can occasionally cause duplicates).
    uniq: dict[tuple, dict] = {}
    for rec in records:
        src = rec["source"]
        key = (
            rec["kind"],
            rec["lisp_name"],
            rec["c_name"],
            src["path"],
            int(src["line"]),
        )
        uniq[key] = rec

    return list(uniq.values())


def write_jsonl(records: Iterable[dict], out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as f:
        for rec in records:
            f.write(json.dumps(rec, sort_keys=True, separators=(",", ":")))
            f.write("\n")


def write_tsv(records: Iterable[dict], out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    header = [
        "kind",
        "lisp_name",
        "c_name",
        "source.path",
        "source.line",
        "arity.min",
        "arity.max",
        "arity.raw_min",
        "arity.raw_max",
        "opcode",
    ]
    with out_path.open("w", encoding="utf-8") as f:
        f.write("\t".join(header))
        f.write("\n")
        for rec in records:
            ar = rec.get("arity") or {}
            src = rec["source"]
            row = [
                rec["kind"],
                rec["lisp_name"],
                rec["c_name"],
                src["path"],
                str(src["line"]),
                "" if ar.get("min") is None else str(ar.get("min")),
                "" if ar.get("max") is None else str(ar.get("max")),
                "" if ar.get("raw_min") is None else str(ar.get("raw_min")),
                "" if ar.get("raw_max") is None else str(ar.get("raw_max")),
                "-" if rec.get("opcode") is None else str(rec.get("opcode")),
            ]
            f.write("\t".join(row))
            f.write("\n")


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument(
        "--runtime-subrs",
        help="Optional JSON file from scripts/inventory/runtime-subrs.el; filters DEFUNs to the TTY runtime surface",
        default=None,
    )
    ap.add_argument("--out-jsonl", required=True)
    ap.add_argument("--out-tsv", required=True)
    args = ap.parse_args(argv)

    root = Path(args.root).resolve()
    records = extract_static_inventory(root)

    if args.runtime_subrs:
        runtime = json.loads(Path(args.runtime_subrs).read_text(encoding="utf-8"))
        runtime_kind: dict[str, str] = {}
        for it in runtime:
            name = it.get("lisp_name")
            kind = it.get("kind")
            if isinstance(name, str) and isinstance(kind, str):
                runtime_kind[name] = kind

        runtime_names = set(runtime_kind.keys())
        filtered: list[dict] = []
        static_defun_names: set[str] = set()
        for rec in records:
            if rec["kind"] in ("subr", "special_form"):
                static_defun_names.add(rec["lisp_name"])
                if rec["lisp_name"] in runtime_names:
                    rec = dict(rec)
                    rec["kind"] = runtime_kind[rec["lisp_name"]]
                    filtered.append(rec)
            else:
                filtered.append(rec)

        missing_defun = sorted(runtime_names - static_defun_names)
        if missing_defun:
            sys.stderr.write("[c-elisp] runtime subrs missing DEFUN sources:\n")
            for name in missing_defun[:25]:
                sys.stderr.write(f"- {name}\n")
            if len(missing_defun) > 25:
                sys.stderr.write(f"... ({len(missing_defun)} total)\n")
            return 2

        records = filtered

    def sort_key(rec: dict) -> tuple:
        src = rec["source"]
        return (
            rec["kind"],
            rec["lisp_name"],
            rec["c_name"],
            src["path"],
            int(src["line"]),
        )

    records_sorted = sorted(records, key=sort_key)
    write_jsonl(records_sorted, Path(args.out_jsonl))
    write_tsv(records_sorted, Path(args.out_tsv))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
