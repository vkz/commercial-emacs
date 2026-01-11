#!/usr/bin/env bash
set -euo pipefail

clemacs_setup_xdg_and_home() {
  local project_root="$1"
  local build_dir="$2"

  export XDG_CACHE_HOME="${project_root}/${build_dir}/xdg-cache"
  export XDG_CONFIG_HOME="${project_root}/${build_dir}/xdg-config"
  export XDG_DATA_HOME="${project_root}/${build_dir}/xdg-data"

  local home_dir="${project_root}/${build_dir}/home"
  mkdir -p "${home_dir}"
  export HOME="${home_dir}"
}
clemacs_core_is_stale() {
  local project_root="$1"
  local core_path="$2"

  if [[ ! -f "${core_path}" ]]; then
    return 0
  fi

  if find "${project_root}/clemacs" \
      -type f \
      \( -name '*.lisp' -o -name '*.asd' -o -name 'qlfile' -o -name 'qlfile.lock' \) \
      -newer "${core_path}" \
      -print -quit | rg -q .; then
    return 0
  fi

  return 1
}

clemacs_ensure_core() {
  local project_root="$1"
  local build_dir="$2"
  local core_path="$3"

  local use_core="${CLEMACS_USE_CORE:-1}"
  if [[ "${use_core}" == "0" ]]; then
    return 0
  fi

  if clemacs_core_is_stale "${project_root}" "${core_path}"; then
    usage_build_dir="${build_dir}" bash "${project_root}/.mise/tasks/clemacs/core/build"
  fi
}

clemacs_sbcl_eval() {
  local project_root="$1"
  local build_dir="$2"
  local deps_dir="$3"
  local qlot_bin="$4"
  local sbcl_dynamic_space="$5"
  shift 5

  local core_path="${project_root}/${build_dir}/clemacs.core"
  local use_core="${CLEMACS_USE_CORE:-1}"

  local style_mode="${CLEMACS_STYLE_WARNING_MODE:-summary}"
  if [[ "${CLEMACS_MUFFLE_STYLE_WARNINGS:-0}" != "0" ]]; then
    style_mode="muffle"
  fi

  local tmp_dir="${project_root}/${build_dir}/tmp"
  mkdir -p "${tmp_dir}"
  local log_path="${tmp_dir}/sbcl.$(date -u +%Y%m%dT%H%M%SZ).$$.log"
  ln -sf "${log_path}" "${tmp_dir}/sbcl.latest.log" 2>/dev/null || true
  echo "[clemacs] sbcl log: ${log_path}" >&2
  local filter_py="${project_root}/.mise/tasks/clemacs/lib/sbcl-output-filter.py"

  local common_args=(
    --dynamic-space-size "${sbcl_dynamic_space}"
    --noinform
    --no-sysinit
    --no-userinit
    --non-interactive
    --disable-debugger
  )

  if [[ "${style_mode}" == "muffle" ]]; then
    common_args+=(--eval '(declaim (sb-ext:muffle-conditions style-warning sb-ext:compiler-note))')
  fi

  if [[ "${use_core}" != "0" ]]; then
    clemacs_ensure_core "${project_root}" "${build_dir}" "${core_path}"
  fi

  set +e
  if [[ "${use_core}" != "0" && -f "${core_path}" ]]; then
    sbcl --core "${core_path}" "${common_args[@]}" "$@" 2>&1 \
      | python3 "${filter_py}" "${style_mode}" "${log_path}"
  else
    (
      cd "${deps_dir}"
      "${qlot_bin}" exec sbcl \
        "${common_args[@]}" \
        --eval '(require :asdf)' \
        --eval "(asdf:load-asd #p\"${project_root}/clemacs/clemacs.asd\")" \
        --eval '(asdf:load-system :clemacs)' \
        "$@"
    ) 2>&1 | python3 "${filter_py}" "${style_mode}" "${log_path}"
  fi

  local status=$?
  set -e
  if [[ "${status}" != "0" ]]; then
    echo "[clemacs] sbcl failed; full log: ${log_path}" >&2
    if [[ "${style_mode}" == "full" || "${CLEMACS_SBCL_SHOW_FULL_LOG_ON_FAIL:-0}" != "0" ]]; then
      cat "${log_path}" >&2
    else
      echo "[clemacs] (showing last 200 log lines; set CLEMACS_SBCL_SHOW_FULL_LOG_ON_FAIL=1 for full log)" >&2
      tail -n 200 "${log_path}" >&2 || true
    fi
    return "${status}"
  fi
}
