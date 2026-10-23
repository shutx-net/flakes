# Dev shells for https://invent.kde.org/plasma/plasma-desktop (master, 6.8.80).
#
# Consumed by the root flake, which turns the attribute names below into
# devShells.<system>.plasma-desktop and devShells.<system>.plasma-desktop-clang-tools.
#
# Linux only. Upstream's CI covers Linux and FreeBSD (.gitlab-ci.yml), the build needs X11,
# Wayland, udev and libwacom, and nixpkgs marks every KDE package Linux/FreeBSD-only; of
# the systems the root flake lists, that leaves the Linux ones.
{
  pkgs,
  system,
  inputs,
  ...
}:

let
  # master asks for Qt >= 6.11, KF6 >= 6.30 and Plasma libraries >= 6.7.90 (QT_MIN_VERSION,
  # KF6_MIN_VERSION and PROJECT_DEP_VERSION in CMakeLists.txt). nixos-26.05 stops at
  # KF6 6.26 and Plasma 6.6.6, so the whole shell comes from nixos-unstable -- the compiler
  # too, so that glibc matches the libraries it links against. Only ever evaluated on
  # Linux: nixos-unstable throws on x86_64-darwin.
  unstable = inputs.nixpkgs-unstable.legacyPackages.${system};
  kde = unstable.kdePackages;

  # A Plasma session exports QT_PLUGIN_PATH and NIXPKGS_QT6_QML_IMPORT_PATH for its own Qt
  # and KDE build, and nix develop passes both through, so binaries and tests run from here
  # loaded the host's plugins into a process linked against unstable's Qt (caught: KF6
  # 6.26's kio_file.so inside foldermodeltest). Nothing in nixpkgs exports these at build
  # time -- wrapQtAppsHook only collects them for wrapper scripts -- so this env hook makes
  # the same walk over every input, propagated ones included, and the shell's values
  # replace the host's. (nixpkgs' Qt also derives plugin dirs from PATH, which still
  # reaches the host profile for plugins the shell lacks; no variable turns that off --
  # hence `source build/prefix.sh` in the README.)
  qtRuntimePathsHook = unstable.makeSetupHook { name = "qt-runtime-paths-hook"; } (
    unstable.writeText "qt-runtime-paths-hook.sh" ''
      qtRuntimePaths() {
        addToSearchPath QT_PLUGIN_PATH "$1/''${qtPluginPrefix:?}"
        addToSearchPath NIXPKGS_QT6_QML_IMPORT_PATH "$1/''${qtQmlPrefix:?}"
      }
      addEnvHooks "$targetOffset" qtRuntimePaths
    ''
  );

  mkPlasmaShell =
    name: extra:
    unstable.mkShell (
      {
        inherit name;

        # Everything nixpkgs' own plasma-desktop derivation builds with: cmake, ninja,
        # pkg-config, Qt, every KDE project upstream's .kde-ci.yml lists (runtime ones
        # included), and the system libraries the derivation adds on top.
        inputsFrom = [ kde.plasma-desktop ];

        packages = [
          qtRuntimePathsHook
          # Runtime data the keyboard KCM looks up through XDG_DATA_DIRS. Not in
          # .kde-ci.yml (KDE's CI images ship it); test_iso_codes fails without it.
          unstable.isocodes
        ]
        ++ extra.packages or [ ];

        # fortify makes the cc-wrapper put -O2 in front of every compile, so a
        # CMAKE_BUILD_TYPE=Debug build (CMake adds only -g) would still come out optimised.
        hardeningDisable = [ "fortify" ];

        # nixpkgs' ECM setup hook exports XDG_CONFIG_DIRS for the inputs, and nix develop
        # lets that replace the session's value -- dropping /etc/xdg and the
        # ~/.config/kdedefaults that holds the global theme's defaults, which KCMs compare
        # against. Set it aside at env build time and prepend it on entry instead, the way
        # nix develop already treats XDG_DATA_DIRS.
        postHook = ''
          plasmaDesktopXdgConfigDirs=$XDG_CONFIG_DIRS
          unset XDG_CONFIG_DIRS
        '';

        shellHook = ''
          export XDG_CONFIG_DIRS=$plasmaDesktopXdgConfigDirs:''${XDG_CONFIG_DIRS:-/etc/xdg}
          # Qt 6 reads these as well, and the session's values point into its own Qt.
          unset QML2_IMPORT_PATH QML_IMPORT_PATH

          echo "${name} dev shell (nixos-unstable)"
          echo "  Qt     : ${kde.qtbase.version}"
          echo "  KF6    : ${kde.kcoreaddons.version}"
          echo "  Plasma : ${kde.libplasma.version}"
          echo "  build  : cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug"
        '';
      }
      // removeAttrs extra [ "packages" ]
    );
in
pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  default = mkPlasmaShell "plasma-desktop" { };

  # Opt-in, because LLVM and clang's libraries add ~1.5 GiB to a ~3.6 GiB shell.
  # clang-format is what upstream's configure step wires in when it finds one: ECM writes
  # .clang-format into the checkout and a pre-commit hook that runs git clang-format.
  # clangd reads the compile_commands.json that every configure writes once
  # CMAKE_EXPORT_COMPILE_COMMANDS is in the environment (CMake reads it from there).
  clang-tools = mkPlasmaShell "plasma-desktop-clang-tools" {
    packages = [ unstable.clang-tools ];
    CMAKE_EXPORT_COMPILE_COMMANDS = "ON";
  };
}
