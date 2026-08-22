---
name: add-flake
description: Add or update a per-OSS-project nix dev shell in the flakes collection — work out what the target checkout actually needs, write projects/<name>/shells.nix, verify it against the project's own build, and commit. Use this whenever someone wants a reproducible dev environment, nix dev shell, or pinned toolchain for a repository they have checked out, or mentions their flakes repo — including phrasings like "add <project> to flakes", "set up nix for this repo", "flakes に追加して", "この repo の開発環境を nix で用意して", or asking to get a specific JDK/Node/Go/Python/Rust version working in a checkout. Also use it when an existing projects/*/shells.nix needs a tool added, a version bumped, or a variant split out.
argument-hint: [path-to-checkout]
---

# Adding a dev shell to the flakes collection

Target checkout: $ARGUMENTS

!`d=$(cd "${CLAUDE_SKILL_DIR}" 2>/dev/null && pwd -P); root=$([ -n "$d" ] && git -C "$d" rev-parse --show-toplevel 2>/dev/null); if [ -n "$root" ]; then printf 'Collection root: %s\nProjects already in it: %s' "$root" "$(ls -1 "$root/projects" 2>/dev/null | tr '\n' ' ')"; else echo "Could not resolve the collection root from ${CLAUDE_SKILL_DIR} -- ask where the flakes repo is checked out."; fi`

Below, `<flakes>` means that collection root and `<checkout>` means the target repository.
If no target was given, work it out from the conversation or the working directory, and
confirm before writing anything.

## The one invariant

The collection exists so that **the upstream checkout stays untouched**. Its clones are
other people's repositories; a stray `flake.nix` or `.envrc` there shows up as untracked
and eventually leaks into a PR. Everything you add goes in `<flakes>`. The only thing that
may ever land in the checkout is an `.envrc`, and only with its `.git/info/exclude` updated
in the same breath.

Read `<flakes>/README.md` first — it is the contract for the layout, and it may have moved
on since this skill was written.

## 1. Work out what the project actually needs

Do not guess from the language. Read the pins the project already carries, in roughly this
order of authority:

| Where | What it tells you |
| --- | --- |
| `.github/workflows/*.yml` | **The strongest signal** — the versions upstream actually tests on and will accept a PR against |
| `.sdkmanrc`, `.tool-versions`, `.nvmrc`, `.python-version`, `rust-toolchain.toml` | The version the maintainers use day to day |
| `go.mod`, `package.json` engines, `pyproject.toml` requires-python, `Cargo.toml` rust-version | The floor, not the target — usually looser than CI |
| `Dockerfile`, `.devcontainer/` | A full environment someone already assembled; often lists system libs you would miss |
| `CONTRIBUTING.md` | Prerequisites written for humans, including "you also need X installed" |

When CI and a version file disagree, follow CI and say so in a comment — a build that
matches CI is one whose failures are reproducible upstream.

## 2. Decide what to leave out

A dev shell is not "every tool the project mentions". Leave out anything the project
already pins for itself:

- **Wrapper scripts** — `gradlew`, `mvnw`, `sbt` bootstrappers fetch an exact version and
  often verify its checksum. Putting a second copy of that tool on `PATH` cannot make the
  build more correct, only differently broken. Supply the runtime it needs (the JDK) and
  let the wrapper do its job.
- **Toolchains a build plugin downloads** — many builds fetch their own Node, Python, or
  protoc. You may still want that tool in the shell for hands-on work, but say in a comment
  that the build does not use it, so nobody later "fixes" a version mismatch that is not one.
- **Anything the system already provides and the user has configured** — `git` in
  particular. A nixpkgs git can shadow their credential helper.

Keep the default shell small. Heavy extras (a second JDK, CUDA, a browser for e2e tests)
belong in an opt-in variant, and the reason belongs in a comment next to it.

## 3. Write `projects/<name>/shells.nix`

Name the directory after the upstream repository. The file is a plain function, not a
flake — the root flake discovers it by scanning `./projects`:

```nix
# Dev shells for https://github.com/<owner>/<repo> (<branch>, <version>).
{ pkgs, ... }:

let
  toolchain = pkgs.<something>;   # comment WHY this version, citing the file you read
in
{
  default = pkgs.mkShell {
    name = "<project>";
    packages = [ toolchain ];
    SOME_VAR = "...";
  };
}
```

The function also receives `system` and `inputs`, so a project that genuinely needs a
different nixpkgs can use `inputs.<other>.legacyPackages.${system}` once you add that input
to the root flake. Do not add one just to get a newer package — check the pinned nixpkgs
first.

Attribute names flatten into the flat `devShells.<system>.<name>` namespace:

| attribute in `shells.nix` | how it is invoked |
| --- | --- |
| `default` | `nix develop <flakes>#<project>` |
| `toolchains` | `nix develop <flakes>#<project>-toolchains` |

## 4. Make it visible to Nix

```sh
git -C <flakes> add projects/<name>
```

Nix reads a flake in a git repository through git: **files that were never added are
invisible to evaluation**, and the failure looks like the directory does not exist rather
than like a missing `git add`. Do this before the first `nix flake show`, not after
debugging a phantom error.

## 5. Verify against the project's own build

Entering the shell is not evidence that it works. Run all three:

```sh
nix flake show <flakes>                              # the new attribute is listed
nix develop <flakes>#<name> --command <tool> --version
cd <checkout> && nix develop <flakes>#<name> --command <the project's own build>
```

The third one is the real test — configure or compile something, not `--help`. A shell that
starts but cannot build the project is worse than no shell, because it looks fine.

**Check that env vars actually arrive.** Setting a variable in `mkShell` proves only that
the variable exists. Tools have their own rules about which channel they read config from,
and a value that is silently ignored is indistinguishable from one that works until much
later. Make the tool report its own resolved configuration (`gradle javaToolchains`,
`go env`, `python -c 'import sys; print(sys.executable)'`, `cargo --version --verbose`) and
read the answer. If a variable turns out not to reach the tool, do not ship it — either
find the channel that works or expose the value for the user to pass explicitly, and say
which in a comment.

## 6. Format, document, commit

In `<flakes>`:

```sh
nix fmt                                    # nixfmt-tree; must leave no diff afterwards
```

Add `projects/<name>/README.md` covering what is in the shell, **why each version**, and
anything surprising you hit. The surprises are the part nobody can reconstruct later. Write
paths in it as `<flakes>` / `<checkout>` placeholders rather than the paths on this machine
— the collection is meant to be usable from someone else's clone.

Then update the project table in the root `README.md` and commit. CI builds every shell it
finds, so a broken one is caught at push time rather than by whoever pulls next.

## 7. Optional: direnv in the checkout

Only if asked. It is the one thing that touches the upstream clone, so it comes with its
own cleanup:

```sh
# <checkout>/.envrc
use flake <flakes>#<name>
watch_file <flakes>/flake.nix
watch_file <flakes>/flake.lock
watch_file <flakes>/projects/<name>/shells.nix
```

`use_flake`'s built-in `watch_file` calls are relative to the `.envrc`, so an out-of-tree
flake needs the absolute ones above or edits never trigger a reload. Add `.envrc` and
`.direnv/` to the checkout's `.git/info/exclude` — that file is not tracked, so it keeps
both out of `git status` without touching `.gitignore`. Then `direnv allow <checkout>`,
again after every `.envrc` edit.

If direnv may be entered from a non-login shell (editors, agents), guard the top of
`.envrc` so a missing `nix` on `PATH` does not fail with a bare "command not found":

```sh
if ! command -v nix >/dev/null 2>&1 && [ -e /etc/profile.d/nix.sh ]; then
  . /etc/profile.d/nix.sh
fi
```
