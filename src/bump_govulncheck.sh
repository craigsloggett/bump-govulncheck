#!/bin/sh

set -euf

# Required user inputs.
: "${FILE:?FILE is required}"

# GitHub Actions runtime environment.
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is unset, most likely during testing}"

# Optional user inputs.
: "${YAML_PATH:=}"
: "${MATCH:=}"
: "${REPLACE:=}"

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

  if [ -n "${YAML_PATH}" ] && [ -n "${REPLACE}" ]; then
    die "'path' and 'replace' are mutually exclusive; use 'path'+'match' for YAML or 'match'+'replace' for line-based files."
  fi

  if [ -n "${YAML_PATH}" ] && [ -z "${MATCH}" ]; then
    die "'path' requires 'match'."
  fi

  if [ -n "${REPLACE}" ] && [ -z "${MATCH}" ]; then
    die "'replace' requires 'match'."
  fi

  if [ -z "${YAML_PATH}" ] && [ -z "${REPLACE}" ]; then
    die "Provide either 'path'+'match' (YAML mode) or 'match'+'replace' (line mode)."
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
  line_number=$(yq "${YAML_PATH} | line" "${FILE}") ||
    exit 1

  [ "${line_number}" != "0" ] ||
    die "Path ${YAML_PATH} not found in ${FILE}."

  # `set -e` would terminate on awk's non-zero exit before the case statement
  # can dispatch on the specific code, so capture status explicitly here.
  status=0
  awk -v line="${line_number}" -v pattern="${MATCH}" -v version="${LATEST_VERSION}" '
    NR == line {                  # Only operate on the line yq located.
      if (match($0, pattern)) {   # Find the version substring on that line.
        matched = 1
        sub(pattern, version)
      }
    }
    { print }                     # Passthrough for non-matching lines.
    END {
      if (!matched) exit 2        # Distinguish "regex did not match" from awk errors.
    }
  ' "${FILE}" >"${STAGING}" || status=$?

  case "${status}" in
    0) ;;
    2) die "Pattern '${MATCH}' did not match on line ${line_number} of ${FILE}." ;;
    *) exit 1 ;;
  esac

  cmp -s "${FILE}" "${STAGING}" &&
    return 1 # No change, signal VERSION_CHANGED="false"

  mv "${STAGING}" "${FILE}" ||
    exit 1
}

bump_line() {
  match_count=$(grep -cE "${MATCH}" "${FILE}") || true

  [ "${match_count}" -ge 1 ] ||
    die "No line in ${FILE} matched pattern: ${MATCH}"

  [ "${match_count}" -le 1 ] ||
    die "Pattern matched ${match_count} lines in ${FILE}; refine the pattern to match exactly one line."

  awk -v pattern="${MATCH}" -v replacement="${REPLACE}" -v version="${LATEST_VERSION}" '
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
