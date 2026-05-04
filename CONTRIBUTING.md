# Contributing Guide

Contributions are **welcome** in the `deckclip` directory. We gladly accept:

1. Issue Discussions
2. PR
3. Docs PR
4. Bug Reproductions
5. Security Reports

## Pull Request Scope

External contributions are accepted **only inside the `deckclip/` directory**
(the Rust CLI, MCP server, and shared crates). Everything outside `deckclip/`
— including the Swift macOS app, assets, and release scripts — is
source-available but not open to external PRs.

If you open a pull request that touches files outside `deckclip/`, the
**PR Scope Guard** check will fail and the bot will leave a comment on the PR
explaining how to unblock it. You have two options:

1. Limit the diff to `deckclip/` and push again.
2. Ask the repository owner ([@yuzeguitarist](https://github.com/yuzeguitarist))
   to leave an approval comment (`/allow`, `allow edit`, `approve`, `lgtm`,
   `批准`, `允许`, or `放行` on its own line). The check will re-run automatically
   and turn green — no need to push another commit.

Pull requests authored by the repository owner or by recognized AI-agent bots
(Claude, Devin, Copilot, Codex, Cursor, etc.) bypass the scope check.

## Required CI Checks

All pull requests must pass the following CI checks before they can be merged:

| Check                  | What it does                                                |
| ---------------------- | ----------------------------------------------------------- |
| `PR Scope Guard`       | Enforces the `deckclip/`-only scope rule (see above).       |
| `Rust CI / rustfmt`    | `cargo fmt --all -- --check` — formatting must be clean.    |
| `Rust CI / clippy`     | `cargo clippy --workspace --all-targets -- -D warnings`.    |
| `Rust CI / build`      | `cargo build --workspace --all-targets` (`-D warnings`).    |
| `Rust CI / test`       | `cargo test --workspace`.                                   |

The repository owner is expected to enable these as **required status checks**
in branch protection settings for `main`:

> GitHub → Settings → Branches → `main` → *Require status checks to pass before merging*
>
> Required checks:
> - `PR Scope Guard`
> - `rustfmt`
> - `clippy`
> - `build`
> - `test`
>
> Recommended toggles: *Require branches to be up to date before merging*,
> *Require linear history*, *Do not allow bypassing the above settings*.

## Local Verification

Before opening a PR, please verify your changes locally:

```bash
cd deckclip
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo build --workspace --all-targets
cargo test --workspace
```

All four commands must succeed.
