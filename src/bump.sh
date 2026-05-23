#!/bin/sh

set -euf

: "${YAML_PATH:=}"
: "${LINE_MATCH:=}"
: "${LINE_REPLACE:=}"

# -----------------------------------------------------------------------------
# Per-tool version discovery — the only per-tool variation across bump-* repos.
# -----------------------------------------------------------------------------

discover_version() {
  curl -sf https://proxy.golang.org/golang.org/x/vuln/@latest | jq -r '.Version'
}

# -----------------------------------------------------------------------------
# Shared helpers.
# -----------------------------------------------------------------------------

die() {
  printf '%s\n' "$1" >&2
  exit 1
}

validate_inputs() {
  [ -f "${FILE}" ] || die "File not found: ${FILE}"

  if [ -n "${LINE_MATCH}" ] && [ -z "${LINE_REPLACE}" ]; then
    die '"match" was provided without "replace".'
  fi
  if [ -z "${LINE_MATCH}" ] && [ -n "${LINE_REPLACE}" ]; then
    die '"replace" was provided without "match".'
  fi
  if [ -n "${YAML_PATH}" ] && [ -n "${LINE_MATCH}" ]; then
    die 'Provide either "path" or "match"+"replace", not both.'
  fi
  if [ -z "${YAML_PATH}" ] && [ -z "${LINE_MATCH}" ]; then
    die 'Provide either "path" (for YAML) or "match"+"replace" (for line-based files).'
  fi
}

bump_yaml() {
  _current=$(yq "${YAML_PATH}" "${FILE}")
  if [ "${_current}" = "null" ]; then
    die "Path ${YAML_PATH} not found in ${FILE}."
  fi
  if [ "${_current}" = "${VERSION}" ]; then
    CHANGED=false
    return
  fi
  yq "${YAML_PATH} = \"${VERSION}\"" -i "${FILE}"
  CHANGED=true
}

bump_line() {
  _matches=$(awk -v pattern="${LINE_MATCH}" '$0 ~ pattern { c++ } END { print c+0 }' "${FILE}")
  if [ "${_matches}" -eq 0 ]; then
    die "No line in ${FILE} matched pattern: ${LINE_MATCH}"
  fi
  if [ "${_matches}" -gt 1 ]; then
    die "Pattern matched ${_matches} lines in ${FILE}; refine the pattern to match exactly one line."
  fi
  _replacement=$(printf '%s' "${LINE_REPLACE}" | sed "s|{version}|${VERSION}|g")
  _current=$(awk -v pattern="${LINE_MATCH}" '$0 ~ pattern { print; exit }' "${FILE}")
  if [ "${_current}" = "${_replacement}" ]; then
    CHANGED=false
    return
  fi
  awk -v pattern="${LINE_MATCH}" -v replacement="${_replacement}" '
    $0 ~ pattern { print replacement; next }
    { print }
  ' "${FILE}" >"${FILE}.new"
  mv "${FILE}.new" "${FILE}"
  CHANGED=true
}

emit_outputs() {
  printf 'version=%s\n' "${VERSION}" >>"${GITHUB_OUTPUT}"
  printf 'changed=%s\n' "${CHANGED}" >>"${GITHUB_OUTPUT}"
}

main() {
  VERSION=$(discover_version)
  if [ -z "${VERSION}" ] || [ "${VERSION}" = "null" ]; then
    die 'Failed to determine the latest version.'
  fi
  validate_inputs
  if [ -n "${YAML_PATH}" ]; then
    bump_yaml
  else
    bump_line
  fi
  emit_outputs
}

main "$@"
