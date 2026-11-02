# Dev shells for https://github.com/caddyserver/caddy (master, v2.11.7+88).
#
# Consumed by the root flake, which turns the attribute name below into
# devShells.<system>.caddy.
{
  pkgs,
  system,
  inputs,
  ...
}:

let
  # go.mod says `go 1.26.0`, and every CI workflow (ci.yml, lint.yml, cross-build.yml) runs
  # Go 1.26 only -- `~1.26.0` with check-latest, i.e. the newest 1.26 patch. go_1_26 rather
  # than `go`, so that a lock update cannot move this shell to 1.27 before upstream's CI does.
  # The patch level is not cosmetic: govulncheck holds the toolchain's own fixed bugs against
  # the code, so a stale nixpkgs pin fails a check that passes upstream (README).
  go = pkgs.go_1_26;

  # lint.yml runs golangci-lint `latest`, and golangci-lint-action verifies the config first.
  # nixos-26.05 is stuck on 2.12.2, which rejects the `canonicalheader` settings in upstream's
  # .golangci.yml (they arrived in 2.14) and ships older staticcheck, errcheck, gosec and
  # modernize than CI runs. nixos-unstable tracks releases. It is a standalone binary that
  # runs this shell's `go`, so the toolchain stays on 26.05. nixos-unstable no longer
  # evaluates on x86_64-darwin, which keeps 26.05's 2.12.2.
  golangci-lint =
    if system == "x86_64-darwin" then
      pkgs.golangci-lint
    else
      inputs.nixpkgs-unstable.legacyPackages.${system}.golangci-lint;
in
{
  # mkShell, not mkShellNoCC: on Linux `go test -race` needs cgo, and so a C compiler.
  default = pkgs.mkShell {
    name = "caddy";

    packages = [
      go
      golangci-lint
      pkgs.govulncheck # lint.yml's govulncheck job
      pkgs.xcaddy # the README's build "with version information and/or plugins"
    ];

    # The workflow-level env of ci.yml and cross-build.yml.
    #
    # nixpkgs ships go.env with GOTOOLCHAIN=auto, under which a go.mod asking for a newer Go
    # makes the go command download that release and run it instead of this shell's.
    GOTOOLCHAIN = "local";
    # Leaves smallstep/nosql's badger, MySQL and PostgreSQL drivers out of every build, as
    # CI's tests and cross-builds, .golangci.yml (build-tags), xcaddy and the README's manual
    # build all do.
    GOFLAGS = "-tags=nobadger,nomysql,nopgx";

    shellHook = ''
      echo "caddy dev shell"
      echo "  go    : ${go.version}  (GOTOOLCHAIN=local, GOFLAGS=$GOFLAGS)"
      echo "  build : cd cmd/caddy && CGO_ENABLED=0 go build -trimpath -ldflags='-w -s'"
      echo "  test  : GODEBUG=http2xconnect=1 go test -race -short ./..."
      echo "  lint  : golangci-lint run --timeout 10m   (${golangci-lint.version})"
    '';
  };
}
