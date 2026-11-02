# caddy

Development shell for [caddyserver/caddy](https://github.com/caddyserver/caddy).

Below, `<flakes>` is where this repository is cloned and `<checkout>` is where caddy is
cloned.

## Usage

```sh
cd <checkout>
nix develop <flakes>#caddy
```

What upstream's CI runs, as it runs there:

```sh
# .github/workflows/ci.yml
(cd cmd/caddy && CGO_ENABLED=0 go build -trimpath -ldflags="-w -s")
(cd cmd/caddy && ./caddy start && ./caddy stop)
GODEBUG=http2xconnect=1 go test -race -short ./...

# .github/workflows/lint.yml
golangci-lint config verify && golangci-lint run --timeout 10m
govulncheck ./...
```

`cmd/caddy/caddy` is in upstream's `.gitignore`. AGENTS.md adds the integration tests,
`go test ./caddytest/integration/...`, which CI never runs — see
[below](#ci-never-runs-the-integration-tests).

To build Caddy with plugins on top of the checkout, as upstream's README does with xcaddy:

```sh
xcaddy build --with github.com/caddyserver/caddy/v2=. --with <plugin module> --output cmd/caddy/caddy
```

`--output` matters when running from the checkout: xcaddy's default, `./caddy`, is not in
upstream's `.gitignore`.

## What is in the shell, and why

- **Go 1.26.10** (`go_1_26`) — `go.mod` says `go 1.26.0`, and every CI workflow (`ci.yml`,
  `lint.yml`, `cross-build.yml`) runs Go 1.26 only: `~1.26.0` with `check-latest`, i.e. the
  newest 1.26 patch, which is the same 1.26.10 today. `go_1_26` rather than `go`, so a lock
  update cannot move the shell to 1.27 before upstream's matrix does; when it moves, move
  this. Keep the pin fresh — see [the first surprise](#a-stale-go-patch-fails-govulncheck).
- **`GOTOOLCHAIN=local`** — CI's setting. nixpkgs ships `go.env` with `GOTOOLCHAIN=auto`,
  under which a `go.mod` asking for a newer Go — a plugin's, say — makes the go command
  print `go: downloading go1.27.0` and quietly run that instead of this shell's Go. With
  `local` it stops with `go.mod requires go >= 1.27.0 (running go 1.26.10;
  GOTOOLCHAIN=local)`. Being in the environment, it also beats a `go env -w GOTOOLCHAIN=…`
  in your own Go config.
- **`GOFLAGS=-tags=nobadger,nomysql,nopgx`** — CI's setting for tests and cross-builds. The
  tags leave smallstep/nosql's badger, MySQL and PostgreSQL drivers out; `.golangci.yml`
  (`build-tags`), xcaddy and upstream's README build with the same three.
  `go version -m` on a binary built in the shell shows `-tags=nobadger,nomysql,nopgx`.
- **A C compiler** (`mkShell`'s gcc; clang on macOS) — on Linux, `-race` requires cgo.
- **golangci-lint 2.15.0, from nixos-unstable** — `lint.yml` runs golangci-lint-action with
  `version: latest`, and the action runs `golangci-lint config verify` before linting (its
  `verify` input defaults to true). nixos-26.05 carries 2.12.2, whose schema does not know
  the `canonicalheader` settings in upstream's `.golangci.yml` (they arrived in 2.14), so
  `config verify` fails with it; and it lints with older versions of linters upstream
  enables — errcheck 1.10 against CI's 1.30, gosec 2.26 against 2.29, modernize 0.44 against
  0.52 (several new analyzers), and older staticcheck, exhaustive and gofumpt. On master at
  `1a870400` both report 0 issues; new code is where they part. The binary is built with
  Go 1.27.3 and runs the shell's `go` to load packages, which is the direction golangci-lint
  supports: it refuses only code targeting a Go newer than its own.
- **govulncheck 1.3.0** — `lint.yml`'s govulncheck job. CI installs `@latest` (1.9.0), but
  the vulnerability data comes from vuln.go.dev, not the binary, and on master 1.3.0 and
  1.9.0 report the same findings, so it stays on the stable pin.
- **xcaddy 0.4.7** — upstream README's build "with version information and/or plugins", and
  `ci.yml`'s goreleaser-check job. (0.4.5, which nixos-26.05 had until the lock update that
  came with this project, did not embed `time/tzdata` the way `cmd/caddy/main.go` does.)
- **No `GODEBUG`** — CI sets `http2xconnect=1` on its test step only, so that Go's HTTP/2
  server advertises extended CONNECT (WebSockets over HTTP/2). The `-short` suite passes
  with and without it; set in the shell, it would also switch the feature on in every caddy
  you run from there.
- **No gopls, delve or goreleaser** — upstream does not use the first two, and an editor
  that installs gopls itself builds it with the shell's `go`. goreleaser runs only in the
  release workflow and in a CI job limited to pull requests from caddyserver/caddy's own
  branches.
- **No git** — the system one, with your own configuration.
- **No setcap** — upstream's README uses `sudo setcap` (and `cmd/caddy/setcap.sh`) to let a
  binary bind ports below 1024. That is system administration, not part of the build; the
  tests use high ports.

## Surprises

### A stale Go patch fails govulncheck

govulncheck holds the toolchain's own fixed bugs against the code, not just the module
dependencies. With the lock as it was before this project (nixos-26.05 of 2026-08-20,
Go 1.26.6), `govulncheck ./...` exited 3 on 14 standard-library vulnerabilities that
caddy's code reaches — eight in net/http, two in html/template, and one each in crypto/tls,
crypto/x509, net/textproto and os — all fixed by 1.26.9 or 1.26.10. CI, on the newest
patch, sees none of them. Hence the lock update that came with this project, and the
remedy when it happens again:

```sh
nix flake update nixpkgs --flake <flakes>   # moves every project's stable packages
```

### A plain `go build` is not CI's binary

The shell has gcc, so cgo is on, and `go build` links against the shell's glibc. nixpkgs'
Go gives such binaries the Nix store's `ld.so` as interpreter, so they run on NixOS too,
but only while that store path exists. CI's build step sets `CGO_ENABLED=0` and gets a
static binary; use its command for anything you copy elsewhere. The shell cannot set
`CGO_ENABLED=0` for you, because `-race` needs cgo.

### `golangci-lint fmt` rewrites test files CI never checks

`.golangci.yml` sets `run.tests: false`, so `golangci-lint run` — CI's check, formatters
included — never looks at `_test.go` files. `golangci-lint fmt` does: run over the whole
tree at `1a870400`, it rewrites 20 of them (19 with 2.12.2), none of which you touched.
Name the files you changed instead: `golangci-lint fmt path/to/file.go`.

### CI's test command writes into the checkout

The test step in `ci.yml` adds `-coverprofile="cover-profile.out"`, which lands in the
checkout root, and upstream's `.gitignore` does not cover it. The commands above leave it
off; point it outside the checkout if you want the profile.

### CI never runs the integration tests

Every CI test run passes `-short`, and under `-short` caddytest's `Tester` skips each test
that starts a server — 125 of the 135 in `caddytest/integration`. Run in full at
`1a870400`, `TestReverseProxyReloadStressUpgradedStreamsHeapProfiles` fails ("detached mode
kept 0/1 upgraded streams alive after reloads"), exactly as it does with the official
Go 1.26.10 outside Nix. With `HTTPS_PROXY` set in the environment, the HTTP/2
proxy-protocol tests (`TestProxyProtocolV1WithH2`, `…V2WithH2`, `…ServerAndProxy`) fail as
well, with either toolchain.

### x86_64-darwin

nixos-unstable no longer evaluates on x86_64-darwin, so there golangci-lint stays at
nixos-26.05's 2.12.2, with the `config verify` failure above. As locked, xcaddy 0.4.7 is
also missing from cache.nixos.org for that system and is built locally.

## Automatic activation with direnv

`cd <checkout>` is then enough to enter this shell; the result is the same as running
`nix develop` by hand.

1. Enable the shell hook, if it is not already (for bash, at the end of `~/.bashrc`):

   ```sh
   eval "$(direnv hook bash)"
   ```

2. `<checkout>/.envrc`:

   ```sh
   use flake <flakes>#caddy
   watch_file <flakes>/flake.nix
   watch_file <flakes>/flake.lock
   watch_file <flakes>/projects/caddy/shells.nix
   ```

3. Add `.envrc` and `.direnv/` to `<checkout>/.git/info/exclude`. That file is not tracked,
   so it is never committed and the entries keep both out of `git status` — nothing leaks
   into an upstream pull request.

4. `direnv allow <checkout>`

Notes:

- `use_flake`'s built-in `watch_file` calls are relative to the current directory, so they
  do not cover an out-of-tree flake. Spell out the absolute paths as above.
- Entering from a non-login shell (editors, agents) can fail with `nix: command not found`,
  because direnv inherits the calling shell's PATH. Guarding the top of `.envrc` prevents it:

  ```sh
  if ! command -v nix >/dev/null 2>&1 && [ -e /etc/profile.d/nix.sh ]; then
    . /etc/profile.d/nix.sh
  fi
  ```
