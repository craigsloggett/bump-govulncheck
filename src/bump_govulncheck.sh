#!/bin/sh

set -euf

# Required user inputs.
: "${FILE:?FILE is required}"

# GitHub Actions runtime environment.
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is unset, most likely during testing}"

# Optional user inputs.
: "${YAML_PATH:=}"
: "${LINE_MATCH:=}"
: "${LINE_REPLACE:=}"

die() {
  printf '%s\n' "$1" >&2
  exit 1
}

validate_utilities() (
  for utility in "$@"; do
    command -v "${utility}" >/dev/null 2>&1 ||
      die "Required utility not installed: ${utility}"
  done
)

validate_inputs() (
  [ -f "${FILE}" ] || die "File not found: ${FILE}"

  if [ -n "${LINE_MATCH}" ] && [ -z "${LINE_REPLACE}" ]; then
    die "'match' was provided without 'replace'."
  fi

  if [ -z "${LINE_MATCH}" ] && [ -n "${LINE_REPLACE}" ]; then
    die "'replace' was provided without 'match'."
  fi

  if [ -n "${YAML_PATH}" ] && [ -n "${LINE_MATCH}" ]; then
    die "Provide either 'path' or 'match'+'replace', not both."
  fi

  if [ -z "${YAML_PATH}" ] && [ -z "${LINE_MATCH}" ]; then
    die "Provide either 'path' or 'match'+'replace'."
  fi

  if [ -n "${YAML_PATH}" ] && [ "${YAML_PATH#.}" = "${YAML_PATH}" ]; then
    die "Missing leading '.' in path: ${YAML_PATH}"
  fi
)

discover_latest_version() (
  latest_version=$(
    curl -sf https://proxy.golang.org/golang.org/x/vuln/@latest |
      jq -r '.Version // empty'
  )
  [ -n "${latest_version}" ] ||
    die 'Failed to determine the latest version.'

  printf '%s\n' "${latest_version}"
)

bump_yaml() {
  current_version=$(yq "${YAML_PATH}" "${FILE}") ||
    exit 1

  [ "${current_version}" != "null" ] ||
    die "Path ${YAML_PATH} not found in ${FILE}."

  [ "${current_version}" != "${LATEST_VERSION}" ] ||
    return 1 # No change, signal VERSION_CHANGED="false"

  # Strip an optional leading 'v' so the plain-version check accepts both
  # 'v1.2.3' (Go module style) and '1.2.3'.
  case "${current_version#v}" in
    *[!0-9.]*)
      die "Value at ${YAML_PATH} is '${current_version}'; this action only bumps plain v?MAJOR.MINOR.PATCH versions."
      ;;
  esac

  line_number=$(yq "${YAML_PATH} | line" "${FILE}") ||
    exit 1

  awk -v line="${line_number}" -v current_version="${current_version}" -v latest_version="${LATEST_VERSION}" '
    NR == line {                           # Only apply this script to the line number supplied by `yq`.
      sub(current_version, latest_version) # Substitute the value found at YAML_PATH with LATEST_VERSION.
    }
    { print }                              # Passthrough for non-matching lines.
  ' "${FILE}" >"${STAGING}" ||
    exit 1

  cmp -s "${FILE}" "${STAGING}" &&
    die "Value for ${YAML_PATH} not on its key's line in ${FILE}; block/folded scalars are not supported, use 'match'+'replace' instead."

  mv "${STAGING}" "${FILE}" ||
    exit 1
}

bump_line() {
  match_count=$(grep -cE "${LINE_MATCH}" "${FILE}") || true

  [ "${match_count}" -ge 1 ] ||
    die "No line in ${FILE} matched pattern: ${LINE_MATCH}"

  [ "${match_count}" -le 1 ] ||
    die "Pattern matched ${match_count} lines in ${FILE}; refine the pattern to match exactly one line."

  awk -v pattern="${LINE_MATCH}" -v replacement="${LINE_REPLACE}" -v version="${LATEST_VERSION}" '
    $0 ~ pattern {                         # Match on the current line using the regex supplied in `pattern`.
      output = replacement                 # Working copy of the replacement template.
      gsub(/\{version\}/, version, output) # Substitute {version} with the latest version.
      print output
      next                                 # Skip the passthrough block for this line.
    }
    { print }                              # Passthrough for non-matching lines.
  ' "${FILE}" >"${STAGING}" ||
    exit 1

  cmp -s "${FILE}" "${STAGING}" &&
    return 1 # No change, signal VERSION_CHANGED="false"

  mv "${STAGING}" "${FILE}" ||
    exit 1
}

emit_outputs() {
  {
    printf 'version=%s\n' "${LATEST_VERSION}"
    printf 'changed=%s\n' "${VERSION_CHANGED}"
  } >>"${GITHUB_OUTPUT}"
}

emit_state_log() (
  printf '::group::Status\n'
  printf 'version=%s\n' "${LATEST_VERSION}"
  printf 'changed=%s\n' "${VERSION_CHANGED}"
  printf 'file=%s\n' "${FILE}"
  printf '::endgroup::\n'
)

emit_diff_log() (
  [ "${VERSION_CHANGED}" = "true" ] || return 0

  printf '::group::Changes\n'
  git -c color.ui=always --no-pager diff -- "${FILE}" || true
  printf '\n::endgroup::\n'
)

main() {
  validate_utilities curl jq yq
  validate_inputs

  STAGING=$(mktemp "${FILE}.XXXXXX")
  readonly STAGING
  trap 'rm -f "${STAGING}"' EXIT INT TERM HUP

  LATEST_VERSION=$(discover_latest_version)
  readonly LATEST_VERSION

  VERSION_CHANGED="false"
  if [ -n "${YAML_PATH}" ]; then
    bump_yaml && VERSION_CHANGED="true"
  else
    bump_line && VERSION_CHANGED="true"
  fi
  readonly VERSION_CHANGED

  emit_outputs
  emit_state_log
  emit_diff_log
}

main "$@"
