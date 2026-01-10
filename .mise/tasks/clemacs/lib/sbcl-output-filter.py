#!/usr/bin/env python3
import collections
import os
import re
import sys


def _open_log(path: str | None):
    if not path:
        return None
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return open(path, "w", encoding="utf-8", errors="replace")


def main() -> int:
    mode = (sys.argv[1] if len(sys.argv) > 1 else "summary").strip().lower()
    log_path = sys.argv[2] if len(sys.argv) > 2 else ""
    log_fp = _open_log(log_path)

    suppress_warning_blocks = os.getenv("CLEMACS_SUPPRESS_WARNING_BLOCKS", "0") not in (
        "",
        "0",
    )

    in_style_block = False
    in_warning_block = False
    style_blocks = 0
    warning_blocks = 0
    suppressed_lines = 0
    suppressed_warning_lines = 0
    undefined = collections.Counter()
    undefined_vars = collections.Counter()

    undef_re = re.compile(r"undefined function:\s+([^\s]+)", re.IGNORECASE)
    undef_var_re = re.compile(r"undefined variable:\s+([^\s]+)", re.IGNORECASE)

    try:
        for line in sys.stdin:
            if log_fp is not None:
                log_fp.write(line)

            if mode == "full":
                sys.stdout.write(line)
                continue

            # "muffle" means: don't add extra filtering beyond logging. The
            # caller is expected to have asked SBCL to muffle style-warnings.
            if mode == "muffle":
                sys.stdout.write(line)
                continue

            # summary mode
            if "caught STYLE-WARNING:" in line:
                style_blocks += 1
                in_style_block = True
                suppressed_lines += 1
                continue

            if in_style_block:
                m = undef_re.search(line)
                if m:
                    undefined[m.group(1)] += 1
                # Keep suppressing all compiler chatter until we see a normal
                # non-comment, non-empty line again.
                if line.strip() == "" or line.startswith(";"):
                    suppressed_lines += 1
                    continue
                in_style_block = False

            if suppress_warning_blocks and "caught WARNING:" in line:
                warning_blocks += 1
                in_warning_block = True
                suppressed_warning_lines += 1
                continue

            if in_warning_block:
                m = undef_var_re.search(line)
                if m:
                    undefined_vars[m.group(1)] += 1
                if line.strip() == "" or line.startswith(";"):
                    suppressed_warning_lines += 1
                    continue
                in_warning_block = False

            # Other style-warning lines outside the main "caught STYLE-WARNING"
            # block (e.g. summary/footer lines).
            if line.startswith(";") and "STYLE-WARNING" in line:
                suppressed_lines += 1
                continue

            sys.stdout.write(line)

    finally:
        if log_fp is not None:
            log_fp.flush()
            log_fp.close()

    if mode == "summary" and style_blocks:
        top = ", ".join([k for (k, _v) in undefined.most_common(8)])
        extra = ""
        if top:
            extra = f"; undefined functions (top): {top}"
        if suppress_warning_blocks and warning_blocks:
            top_vars = ", ".join([k for (k, _v) in undefined_vars.most_common(8)])
            extra_vars = ""
            if top_vars:
                extra_vars = f"; undefined variables (top): {top_vars}"
            extra += f"; warnings suppressed: blocks={warning_blocks} lines={suppressed_warning_lines}{extra_vars}"
        where = f" (full log: {log_path})" if log_path else ""
        sys.stderr.write(
            f"[clemacs] SBCL style-warnings suppressed: blocks={style_blocks} lines={suppressed_lines}{extra}{where}\n"
        )
        sys.stderr.flush()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
