# flakes

[![check](https://github.com/shutx-net/flakes/actions/workflows/check.yml/badge.svg)](https://github.com/shutx-net/flakes/actions/workflows/check.yml)
[![nixpkgs](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Fshutx-net%2Fflakes%2Fmain%2Fflake.lock&search=releases%5C.nixos%5C.org%2Fnixos%2F%5B%5E%2F%5D%2B%2Fnixos-%28%5B%5E%2F%5D%2B%29%2Fnixexprs&replace=%241&label=nixpkgs&color=5277C3&logo=nixos&logoColor=white)](flake.lock)

Nix development shells for OSS projects, one per upstream repository.

Nothing is added to the target repository itself; the toolchain is supplied from outside.
A `flake.nix` dropped into an upstream clone shows up as an untracked file and can end up
in a pull request.

## Usage

```sh
# Remote reference, no clone needed
nix develop github:shutx-net/flakes#spring-security

# From inside this repository, once cloned
nix develop .#spring-security

# From the target repository's working directory (<flakes> is where this repo is cloned)
cd <spring-security checkout>
nix develop <flakes>#spring-security
```

## Projects

| Shell | Upstream | Notes |
| --- | --- | --- |
| `#spring-security` | [spring-projects/spring-security](https://github.com/spring-projects/spring-security) |  |
| `#spring-security-toolchains` | same | for `-PtestToolchain` |

See each `projects/<name>/README.md` for details.

## Layout

```
flakes/
├── flake.nix                       # the only entry point
├── flake.lock                      # pins nixpkgs to one revision, shared by every project
└── projects/
    └── <project>/
        ├── shells.nix              # { pkgs, system, inputs, ... } -> { <variant> = devShell; }
        └── README.md
```

## Adding a project

The quickest route is `/add-flake <path to checkout>` from Claude Code
(see [Claude Code skill](#claude-code-skill)). By hand, from inside this repository:

```sh
mkdir -p projects/<name>
$EDITOR projects/<name>/shells.nix
git add projects/<name>          # required -- see below
nix flake show                   # confirm it was picked up
```

## Claude Code skill

`.claude/skills/add-flake/` carries the procedure for adding a project as a Claude Code
skill. Invoked as `/add-flake <path to checkout>`, it works out the required toolchain from
the target repository's CI and version files, then writes, verifies, and commits
`projects/<name>/shells.nix`.

## Nix cannot see files that are not in git

When a flake lives in a git repository, Nix only sees **files that git has been told
about** ([manual](https://nix.dev/manual/nix/latest/command-ref/new-cli/nix3-flake): "files
are fetched directly from the local path as long as they have been added to the Git
repository"). Forget to `git add` a new project and it will not appear in `nix flake show`,
failing instead with a `path does not exist` style error.

Uncommitted changes only produce a `dirty` warning; evaluation still goes through.

## CI

`.github/workflows/check.yml` runs on every push and pull request, on Ubuntu and macOS.

## License

MIT. See [LICENSE](LICENSE).
