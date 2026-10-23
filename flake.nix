{
  description = "Per-project Nix development shells for OSS repositories";

  inputs = {
    # Channel tarball rather than `github:NixOS/nixpkgs/nixos-26.05`: some networks block
    # api.github.com, and that is the only host nix's `github:` fetcher will talk to.
    # channels.nixos.org redirects to an immutable releases.nixos.org snapshot, so the lock
    # file still pins one exact nixpkgs revision.
    nixpkgs.url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz";

    # Only for projects whose default branch builds against libraries newer than the stable
    # release carries -- projects/plasma-desktop needs KDE Frameworks and Plasma releases
    # that nixos-26.05 will never get. Everything else stays on the stable pin above.
    nixpkgs-unstable.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      # One directory per upstream project. A directory joins the flake by containing
      # shells.nix; anything else under ./projects (notes, work in progress) is ignored,
      # so adding a project means adding a directory, not editing this file.
      projects = lib.attrNames (
        lib.filterAttrs (
          name: type: type == "directory" && builtins.pathExists (./projects + "/${name}/shells.nix")
        ) (builtins.readDir ./projects)
      );

      # devShells.<system>.<name> is a flat namespace, so a project's variants are
      # suffixed: `default` becomes <project>, anything else becomes <project>-<variant>.
      shellsFor =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          shellsOf =
            project:
            lib.mapAttrs'
              (
                variant: shell:
                lib.nameValuePair (if variant == "default" then project else "${project}-${variant}") shell
              )
              (
                import (./projects + "/${project}/shells.nix") {
                  inherit pkgs system inputs;
                }
              );
        in
        lib.foldl' (acc: project: acc // shellsOf project) { } projects;
    in
    {
      devShells = lib.genAttrs systems shellsFor;

      # nixfmt-tree rather than bare nixfmt: `nix fmt` with no arguments passes none on to
      # the formatter, and nixfmt then reads stdin instead of the tree (and 1.4 deprecates
      # directory arguments outright). The treefmt wrapper is what its own message points at.
      formatter = lib.genAttrs systems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
