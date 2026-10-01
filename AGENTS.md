# Project

Factorio MOD.

# Development

## Git workflow

The default branch is protected: direct pushes and force pushes are rejected, deletion is disallowed. Make changes on a branch and open a pull request; see CONTRIBUTING.md for PR conventions.

## Available tasks

Run `mise tasks ls -l` to list tasks defined in this project. The `-l` (`--local`) flag excludes tasks inherited from mise's global config, which are unrelated to this project.

## Build and Install

- `mise run install` - Install to local Factorio MOD directory. Uses `git archive` internally, so only committed files are included; commit changes before running.

## Temporary files

Use the `tmp/` directory for temporary files. Create it if it doesn't exist. It is gitignored.

## Lua source layout

Root-level Lua files are limited to the Factorio stage entry points (`settings.lua`, `data.lua`, `control.lua`, and their `-updates`/`-final-fixes` variants). Put additional Lua code in a subdirectory:

- `prototypes/` - declarative prototype definitions (`data:extend({...})`), used from both the settings stage (setting prototypes) and the data stage (item/recipe/entity/etc. prototypes)
- `lib/` - runtime code: control-stage logic and helpers shared across stages

## Comments

Public functions carry a `---` doc comment: a one-line summary, an optional
rationale paragraph (*why*, not *what*), `---@param` per declared parameter in
declaration order, and `---@return` per returned value. "Public" includes a
`local function` the module exports through its `return` or onto its module
table, documented at its definition. `mise run doc-check` enforces that shape. A
comment explaining a single line stays inside the body. The full convention is
CONTRIBUTING.md "Comment conventions".

## Tests

`spec/` holds busted unit tests; run them with `mise run test`.

Cover pure logic only: code that does not touch the Factorio runtime (`game`, `script`, `rendering`, `defines`, `data`, prototype globals). Keep such logic in `lib/` as functions over plain values so a spec can `require` it directly (e.g. `require("lib.foo")`). Runtime-integrated behavior is out of scope for these tests.

`spec/example_spec.lua`, if present, is a placeholder; replace it with real specs.

`spec/helper.lua` runs once before any spec loads. Put setup there that must precede the first `require` of the code under test (e.g. Factorio global stubs). Keep it idempotent.

## Release

Releases are handled by GitHub Actions workflows. Do not run `mise run release:*` tasks manually.

Changelog is managed by `factorix mod changelog` and follows Factorio's changelog.txt specification.

### What to write in changelog.txt

- Regular releases: limit entries to user-visible changes only.
- Initial release: write "Initial release" only, under the `Features` category.

### Updating the changelog during development

`Version: Unreleased` marks the not-yet-released section. The release workflow renames it to the released version and does not open a new one, so between releases `changelog.txt` starts with the last released version. Add a fresh `Unreleased` section at the top for the first user-visible change of a new cycle; put later entries in that same section.

Do not create a section for the next release version directly; version bumping is handled by the GitHub Actions release workflow.

# Document Map

- README.md: Project overview
- CONTRIBUTING.md: Development setup and pull request guidelines
- .scaffold-sync.json / .scaffold-sync.paths: scaffold-drift sync state and tracked-path list; do not delete (see CONTRIBUTING.md "Scaffold drift")

# External References

- [Factorio API](https://lua-api.factorio.com/latest/)
- [Factorio Wiki](https://wiki.factorio.com/)
- [factorio-data](https://github.com/wube/factorio-data): the base game's data definitions; clone locally if needed
- Game directories (mod dir, user dir, data dir, etc.): `factorix path --json | jq -r .<field>` (e.g. `.mod_dir`)
- Other MODs: to investigate a MOD's contents, download it with `factorix mod download <mod-name> -d tmp` rather than guessing; if its source is on GitHub or Codeberg, refer to that as well
- Game terminology: use the wording in the locale files under the data directory (`<data_dir>/<base|space-age|...>/locale/<lang>/*.cfg`) so that terms match the game
