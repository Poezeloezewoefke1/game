# Repository setup

Settings that cannot be configured from inside the repository. A human with
admin rights has to apply these in the GitHub web UI; until they are applied,
the protections described elsewhere in the documentation are **aspirational, not
enforced**.

## Branches

| Branch | Purpose |
|---|---|
| `main` | Stable, reviewed, playable. Never pushed to directly. |
| `claude/starbound-station-dev-62c8jv` | Active development for this work. |
| `claude/development` | The branch name used in the original specification. |

`.github/workflows/validate.yml` triggers on **both** development branch names,
so consolidating on one later needs no workflow change. See BUILD-002 in
`docs/KNOWN_LIMITATIONS.md`.

## Protecting `main`

*Settings -> Branches -> Add branch ruleset* (or *Branch protection rules*) for
`main`:

- [ ] **Require a pull request before merging** (at least 1 approval)
- [ ] **Dismiss stale approvals when new commits are pushed**
- [ ] **Require status checks to pass**, and select:
      - `Validate / Headless validation`
- [ ] **Require branches to be up to date before merging**
- [ ] **Require conversation resolution before merging**
- [ ] **Block force pushes**
- [ ] **Restrict deletions**
- [ ] Apply the rules to administrators too — a rule an admin can bypass is a
      convention, not a control

The status check only appears in the list after the workflow has run at least
once on a pull request, so open a throwaway PR first if it is missing.

## Actions

*Settings -> Actions -> General*:

- [ ] **Workflow permissions:** *Read repository contents permission* — both
      workflows declare `permissions: contents: read` and need nothing more.
- [ ] Leave "Allow GitHub Actions to create and approve pull requests"
      **unchecked**.
- [ ] Restrict actions to those needed: *Allow actions created by GitHub*
      covers `actions/checkout`, `actions/cache` and `actions/upload-artifact`,
      which are the only three used.

## Security

*Settings -> Code security*:

- [ ] Enable **secret scanning** and **push protection**.
- [ ] Enable **Dependabot alerts** (low value here — there are no package
      dependencies — but free).

There are no repository secrets. Neither workflow needs one; if that ever
changes, the secret must be referenced through `secrets.*` and never echoed.

## Issue labels

Suggested, matching the issue templates: `bug`, `task`, `security`,
`networking`, `performance`, `documentation`, `ci`, `blocked`,
`needs-runtime-verification`.

`needs-runtime-verification` is worth having: it is the honest home for
everything in `docs/KNOWN_LIMITATIONS.md` that only a Windows machine or a
physical LAN can close.

## Verification status

Whether any of this has been applied is **unknown from inside the repository**.
Nothing in CI can check branch protection. Tick the boxes here once applied, and
record the date.

- Applied by: _________________
- Date: _________________
