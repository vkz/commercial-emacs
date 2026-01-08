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

    in_style_block = False
    style_blocks = 0
    suppressed_lines = 0
    undefined = collections.Counter()

    undef_re = re.compile(r"undefined function:\s+([^\s]+)", re.IGNORECASE)

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
        where = f" (full log: {log_path})" if log_path else ""
        sys.stderr.write(
            f"[clemacs] SBCL style-warnings suppressed: blocks={style_blocks} lines={suppressed_lines}{extra}{where}\n"
        )
        sys.stderr.flush()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
