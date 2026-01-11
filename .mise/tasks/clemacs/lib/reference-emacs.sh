#!/usr/bin/env bash
set -euo pipefail

clemacs_resolve_reference_emacs() {
  if [[ -n "${CLEMACS_REFERENCE_EMACS:-}" ]]; then
    printf '%s' "${CLEMACS_REFERENCE_EMACS}"
    return 0
  fi

  if [[ -x "/opt/homebrew/bin/emacs" ]]; then
    printf '%s' "/opt/homebrew/bin/emacs"
    return 0
  fi

  if [[ -x "/usr/local/bin/emacs" ]]; then
    printf '%s' "/usr/local/bin/emacs"
    return 0
  fi

  if command -v emacs >/dev/null 2>&1; then
    command -v emacs
    return 0
  fi

  return 1
}

clemacs_export_reference_emacs_if_unset() {
  if [[ -n "${CLEMACS_REFERENCE_EMACS:-}" ]]; then
    return 0
  fi

  local resolved
  resolved="$(clemacs_resolve_reference_emacs 2>/dev/null || true)"
  if [[ -n "${resolved}" ]]; then
    export CLEMACS_REFERENCE_EMACS="${resolved}"
  fi
}
