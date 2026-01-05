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

  local common_args=(
    --noinform
    --no-sysinit
    --no-userinit
    --non-interactive
    --disable-debugger
  )

  if [[ "${CLEMACS_MUFFLE_STYLE_WARNINGS:-0}" != "0" ]]; then
    common_args+=(--eval '(declaim (sb-ext:muffle-conditions style-warning sb-ext:compiler-note))')
  fi

  if [[ "${use_core}" != "0" ]]; then
    clemacs_ensure_core "${project_root}" "${build_dir}" "${core_path}"
  fi

  if [[ "${use_core}" != "0" && -f "${core_path}" ]]; then
    sbcl \
      --core "${core_path}" \
      "${common_args[@]}" \
      "$@"
  else
    (
      cd "${deps_dir}"
      "${qlot_bin}" exec sbcl \
        --dynamic-space-size "${sbcl_dynamic_space}" \
        "${common_args[@]}" \
        --eval '(require :asdf)' \
        --eval "(asdf:load-asd #p\"${project_root}/clemacs/clemacs.asd\")" \
        --eval '(asdf:load-system :clemacs)' \
        "$@"
    )
  fi
}
