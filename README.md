# bump-govulncheck

A composite action that fetches the latest `govulncheck` release and updates a target file with the new version.

## Usage

Update a YAML value by path:

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
    replace: 'GOVULNCHECK_VERSION   := {version}'
```

Pair with [`craigsloggett/create-github-pull-request`](https://github.com/craigsloggett/create-github-pull-request) to open a pull request for the resulting working tree changes.

### Inputs

| Input     | Required? | Default | Description                                                                                                  |
| --------- | --------- | ------- | ------------------------------------------------------------------------------------------------------------ |
| `file`    | `true`    |         | Path to the file to update.                                                                                  |
| `path`    | `false`   |         | yq expression targeting the value to update in the file (e.g. `.inputs.govulncheck-version.default`).        |
| `match`   | `false`   |         | Regex pattern matching the line to update in the file. Use with `replace`.                                   |
| `replace` | `false`   |         | Replacement line. Use `{version}` as the placeholder for the new version.                                    |

Provide either `path` (for YAML) or `match` and `replace` (for line-based files), not both.

### Outputs

| Output    | Description                       |
| --------- | --------------------------------- |
| `version` | The latest `govulncheck` version. |
