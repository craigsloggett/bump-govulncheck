# bump-govulncheck

A composite action that fetches the latest `govulncheck` release and updates a target file with the new version.

## Usage

Update a YAML value located by path:

```yaml
- uses: craigsloggett/bump-govulncheck@v1
  with:
    file: action.yml
    path: .inputs.govulncheck-version.default
```

Update a line by regex:

```yaml
- uses: craigsloggett/bump-govulncheck@v1
  with:
    file: Makefile
    match: '^GOVULNCHECK_VERSION'
    replace: 'GOVULNCHECK_VERSION := {version}'
```

Open a pull request only when the file actually changed:

```yaml
- id: bump-govulncheck
  uses: craigsloggett/bump-govulncheck@v1
  with:
    file: Makefile
    match: '^GOVULNCHECK_VERSION'
    replace: 'GOVULNCHECK_VERSION := {version}'

- if: steps.bump-govulncheck.outputs.changed == 'true'
  uses: craigsloggett/create-github-pull-request@v1
  with:
    commit-message: 'chore(build): Bump govulncheck to ${{ steps.bump-govulncheck.outputs.version }}'
    pull-request-head-branch: bump-govulncheck-${{ steps.bump-govulncheck.outputs.version }}
```

## Inputs

| Input     | Required | Default | Description                                                                                  |
| --------- | -------- | ------- | -------------------------------------------------------------------------------------------- |
| `file`    | Yes      |         | Path to the file to update.                                                                  |
| `path`    | No       |         | yq expression locating the line to update (e.g. `.inputs.govulncheck-version.default`).      |
| `match`   | No       |         | Regex matching the line to rewrite. Pair with `replace`.                                     |
| `replace` | No       |         | Replacement line. Use `{version}` as the placeholder for the new version. Pair with `match`. |

Provide either `path` (YAML mode) or `match`+`replace` (line mode), not both.

For YAML replacements:

- The path must begin with `.` and resolve to an existing line.
- The first `vX.Y.Z` substring on the resolved line is rewritten; the rest of the line is preserved.

For line-based replacements:

- The match pattern must match exactly one line in the file.
- The action errors out if zero or more than one lines match.
- `{version}` is the only placeholder recognized in `replace`.

## Outputs

| Output    | Description                                                                                   |
| --------- | --------------------------------------------------------------------------------------------- |
| `version` | The latest `govulncheck` version, as reported by the Go module proxy.                         |
| `changed` | `true` if the file was modified by this run, `false` if it was already at the latest version. |
