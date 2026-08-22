# spring-security

Development shells for
[spring-projects/spring-security](https://github.com/spring-projects/spring-security).

Below, `<flakes>` is where this repository is cloned and `<checkout>` is where
spring-security is cloned.

## Usage

```sh
nix develop github:shutx-net/flakes#spring-security
```

## What is in the shell, and why

- **JDK 25** — `buildSrc/src/main/groovy/java-toolchain.gradle` defaults to 25, `.sdkmanrc`
  pins `25-librca`, and CI builds on temurin 25. `JAVA_HOME` points at it.
  (nixpkgs' OpenJDK build; only the vendor differs from CI.)
- **Node 22** — for hands-on work in `javascript/` and `docs/` (antora). The Gradle build
  itself does not use it: `com.github.node-gradle.node` is set to `download = true` and
  fetches its own node 20.17.0.
- **No Gradle** — `gradlew` pins 9.7.0 and verifies its SHA-256, so a second Gradle on
  `PATH` could only ever disagree with the build. Always use `./gradlew`.
- **No JDK 17 / 21 in the default shell** — they add roughly 700MB of closure, and for the
  reason below they would not work transparently anyway, so they live in a separate shell.

## `-PtestToolchain` and `$GRADLE_TOOLCHAINS`

This build registers no foojay resolver, so Gradle cannot download a JDK on demand and can
only use ones it has already detected. And the detection list,
`org.gradle.java.installations.paths`, **is only read from a command-line `-D`** (passing it
through `GRADLE_OPTS` is silently ignored — confirmed by experiment).

So `#spring-security-toolchains` does nothing more than prepare the environment variable
`GRADLE_TOOLCHAINS`, holding `-Dorg.gradle.java.installations.paths=<jdk17>,<jdk21>`. Put it
on the command line yourself:

```sh
nix develop <flakes>#spring-security-toolchains
./gradlew javaToolchains $GRADLE_TOOLCHAINS          # lists 17 / 21 / 25
./gradlew -PtestToolchain=17 $GRADLE_TOOLCHAINS test
```

## Automatic activation with direnv

`cd <checkout>` is then enough to enter this shell; the result is the same as running
`nix develop` by hand.

1. Enable the shell hook, if it is not already (for bash, at the end of `~/.bashrc`):

   ```sh
   eval "$(direnv hook bash)"
   ```

2. `<checkout>/.envrc`:

   ```sh
   use flake <flakes>#spring-security
   watch_file <flakes>/flake.nix
   watch_file <flakes>/flake.lock
   watch_file <flakes>/projects/spring-security/shells.nix
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
