# plasma-desktop

Development shells for [plasma-desktop](https://invent.kde.org/plasma/plasma-desktop)
(GitHub mirror: [KDE/plasma-desktop](https://github.com/KDE/plasma-desktop)). Linux only.

Below, `<flakes>` is where this repository is cloned and `<checkout>` is where
plasma-desktop is cloned.

## Usage

```sh
cd <checkout>
nix develop <flakes>#plasma-desktop

cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_INSTALL_PREFIX="$HOME/kde/usr"
cmake --build build
LC_ALL=C.UTF-8 ctest --test-dir build
```

`/build*/` is in upstream's `.gitignore`, so the build directory stays out of `git status`.
To try what you built, see [Running what you built](#running-what-you-built).

| Shell | |
| --- | --- |
| `#plasma-desktop` | everything needed to configure, build and test master |
| `#plasma-desktop-clang-tools` | the same, plus clang-format, clangd and clang-tidy ([below](#plasma-desktop-clang-tools)) |

## What is in the shell, and why

- **Its own nixpkgs: nixos-unstable, not the collection's nixos-26.05** — master's
  `CMakeLists.txt` asks for Qt ≥ 6.11, KF6 ≥ 6.30 and Plasma libraries ≥ 6.7.90
  (`QT_MIN_VERSION`, `KF6_MIN_VERSION`, `PROJECT_DEP_VERSION`). nixos-26.05 carries KF6 6.26
  and Plasma 6.6.6 and will not get newer ones, so this project uses the root flake's
  `nixpkgs-unstable` input. As locked: Qt 6.12.0, KF6 6.31.0, Plasma 6.8.0, GCC 16.2,
  CMake 4.4. The compiler comes from unstable as well, so glibc matches the libraries.
- **nixpkgs' own plasma-desktop build inputs** (`inputsFrom`) — cmake, ninja, pkg-config,
  Qt, and the 55 KDE projects that master's `.kde-ci.yml` lists, runtime ones included
  (nixpkgs generates its list from KDE's metadata; checked identical), plus the system
  libraries nixpkgs adds (SDL2, libcanberra, libwacom, ibus, xkeyboard-config, X11).
  Configure finds every REQUIRED package. Taking the inputs rather than copying the list
  means a lock update follows nixpkgs' KDE team when dependencies change.
- **iso-codes** — runtime data the keyboard KCM looks up through `XDG_DATA_DIRS`. It is not
  in `.kde-ci.yml` (KDE's CI images ship it), and `test_iso_codes` fails without it.
- **`fortify` hardening off** — nixpkgs' cc-wrapper puts `-O2` in front of every compile so
  that `_FORTIFY_SOURCE` works, and CMake's `Debug` adds only `-g`: a Debug build would
  quietly come out optimised.
- **Its own Qt plugin and QML paths** — see the first surprise below.
- **No selenium-webdriver-at-spi** — the GUI tests in `appiumtests/` need it, and nixpkgs
  stubs it out as `null`. Configure then skips them; its warning about
  `SeleniumWebDriverATSPI` is expected. The other optional packages it reports missing
  (signon-oauth2plugin, scim, FontNotoColorEmoji) are runtime-only or alternatives.
- **No git** — the system one, with your own configuration.

## Built against Plasma releases, not Plasma master

KDE's CI builds master against the development branches of the frameworks and of the other
Plasma repositories (`'@latest-kf6'` and `'@same'` in `.kde-ci.yml`). This shell has the
latest *releases* in nixos-unstable instead. That is enough today — master at `0c45326f57`
(2026-10-23) configures, builds and passes all 12 unit tests against KF6 6.31 and
Plasma 6.8.0 — but once master starts using an API that so far exists only in, say,
plasma-workspace master, the build breaks here until a release that has it reaches
nixos-unstable. Then:

```sh
nix flake update nixpkgs-unstable --flake <flakes>   # moves only this project's pin
```

Building the other Plasma repositories from source as well is what kde-builder is for.

## Running what you built

```sh
cmake --install build                     # into CMAKE_INSTALL_PREFIX
source build/prefix.sh                    # written by ECM at configure time
kcmshell6 kcm_keyboard                    # a KCM
plasmoidviewer -a org.kde.plasma.pager    # an applet, outside the panel
```

`prefix.sh` puts the install prefix in front of `QT_PLUGIN_PATH`, `QML2_IMPORT_PATH`,
`XDG_DATA_DIRS` and `XDG_CONFIG_DIRS`. Do not skip it: plugins this shell does not carry —
plasma-desktop's own KCMs and applets — are otherwise found in the host system's profile
(see below), so on a machine that runs Plasma, `kcmshell6 kcm_keyboard` opens the
system's KCM instead of yours. Both cases checked with `LD_DEBUG=files`.

`kcmshell6`, `plasmoidviewer`, `plasmashell` and `systemsettings` on `PATH` are
nixos-unstable's (Plasma 6.8.0, Qt 6.12), not the session's.

## `#plasma-desktop-clang-tools`

Adds clang-tools 21 (clang-format, git-clang-format, clangd, clang-tidy) and sets
`CMAKE_EXPORT_COMPILE_COMMANDS=ON`, which CMake reads from the environment, so every
configure writes `build/compile_commands.json`, where clangd finds it on its own. Opt-in
because LLVM's and clang's libraries take the shell from 3.6 GiB to 5.1 GiB.

When it finds clang-format, upstream's configure also writes `<checkout>/.clang-format`
and makes the pre-commit hook run `git clang-format` on the staged changes. The hook needs
clang-format **when you commit**, not just when you configure: committing from anywhere
without it prints `git: 'clang-format' is not a git command`, then the hook's misleading
"You have unformatted changes", and aborts the commit. So either

- commit from inside this shell (or let direnv enter it, below),
- skip the hook once with `git commit --no-verify`, or
- drop the check: from `#plasma-desktop`, `cmake -U KDE_CLANG_FORMAT_EXECUTABLE -B build`.
  Merely reconfiguring is not enough — the build directory's cache still remembers
  clang-format's store path, so the hook comes back unchanged.

## Surprises

### The session's Qt plugins leak into the shell

A Plasma session exports `QT_PLUGIN_PATH`, `NIXPKGS_QT6_QML_IMPORT_PATH` and
`QML2_IMPORT_PATH` for its own Qt and KDE build, and `nix develop` passes them through.
With the host on NixOS 26.05 (Plasma 6.6.6, Qt 6.11), `foldermodeltest` — linked against
unstable's Qt 6.12 — loaded KF6 6.26's `kio_file.so`, ki18n 6.26's `ktranscript.so` and
Qt 6.11's image format plugins, and passed anyway. nixpkgs exports none of these variables
at build time (`wrapQtAppsHook` only collects them for wrapper scripts), so `shells.nix`
adds an env hook that makes the same walk over every input and sets them itself, and
unsets `QML2_IMPORT_PATH` / `QML_IMPORT_PATH`. `foldermodeltest` now loads only 6.31
plugins.

What the shell cannot switch off: nixpkgs patches Qt to also look in
`<dir>/../lib/qt-6/plugins` for every `<dir>` on `PATH`, and `nix develop` keeps your
`PATH` behind its own. A plugin the shell does not have is still found in
`/run/current-system/sw` — the reason `prefix.sh` matters above. Plugins the shell does
have always come first.

### nix develop replaces `XDG_CONFIG_DIRS`

nixpkgs' ECM setup hook exports `XDG_CONFIG_DIRS` for the inputs' `etc/xdg`, and unlike
`XDG_DATA_DIRS`, `nix develop` lets it replace the session's value rather than prepending
it. That drops `/etc/xdg`, and the `~/.config/kdedefaults` a Plasma session adds — the
global theme's defaults, which KCMs compare against. `shells.nix` sets the value aside
while the environment is built and prepends it on entry, falling back to `/etc/xdg` when
the session has none.

### Configuring writes into the checkout

Upstream's CMake (ECM's `KDEGitCommitHooks` and `KDEClangFormat`), not this shell, writes
two things into `<checkout>`. Neither shows up in `git status`:

- `.git/hooks/pre-commit` (and `.git/hooks/scripts/`), on every configure. Without
  clang-format it only runs your `.git/hooks/pre-commit.d/*`; with it, see above.
- `.clang-format`, only when clang-format is on `PATH`; it is in upstream's `.gitignore`.

Both are copied from the Nix store and so arrive read-only. CMake can still replace them
(checked for the hook, whose content changes with clang-format's presence).

### x86_64-darwin

nixos-unstable refuses to evaluate at all on x86_64-darwin ("Nixpkgs 26.11 has dropped
support for x86_64-darwin"), while the root flake still lists that system for the other
projects. `shells.nix` therefore asks the collection's stable `pkgs` whether this is Linux
and only then touches `inputs.nixpkgs-unstable`.

### Tests assume an English locale

`flags_test` compares a layout name with `"English (US)"`; under a Japanese locale it gets
the translated name and fails. Hence `LC_ALL=C.UTF-8` above; with it, all 12 tests pass.

## Automatic activation with direnv

`cd <checkout>` is then enough to enter this shell; the result is the same as running
`nix develop` by hand.

1. Enable the shell hook, if it is not already (for bash, at the end of `~/.bashrc`):

   ```sh
   eval "$(direnv hook bash)"
   ```

2. `<checkout>/.envrc` (or `#plasma-desktop-clang-tools`):

   ```sh
   use flake <flakes>#plasma-desktop
   watch_file <flakes>/flake.nix
   watch_file <flakes>/flake.lock
   watch_file <flakes>/projects/plasma-desktop/shells.nix
   ```

3. Add `.envrc` and `.direnv/` to `<checkout>/.git/info/exclude`. That file is not tracked,
   so it is never committed and the entries keep both out of `git status` — nothing leaks
   into an upstream merge request.

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
