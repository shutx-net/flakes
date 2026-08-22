# Dev shells for https://github.com/spring-projects/spring-security (main, 7.2.0-SNAPSHOT).
#
# Consumed by the root flake, which turns the attribute names below into
# devShells.<system>.spring-security and devShells.<system>.spring-security-toolchains.
{ pkgs, ... }:

let
  # buildSrc/src/main/groovy/java-toolchain.gradle defaults to 25, .sdkmanrc pins
  # 25-librca, and CI builds on temurin 25.
  jdk = pkgs.jdk25;

  common = {
    # No gradle package on purpose: gradlew pins 9.7.0 and verifies its SHA-256, so a
    # second gradle on PATH could only ever disagree with the build.
    packages = [
      jdk
      # For hands-on work in javascript/ and docs/ (antora). The Gradle build does not
      # use it: com.github.node-gradle.node downloads its own node 20.17.0.
      pkgs.nodejs_22
    ];
    JAVA_HOME = jdk.home;
  };

  banner = extra: ''
    echo "spring-security dev shell"
    java -version 2>&1 | head -n1 | sed 's/^/  java  : /'
    echo "  node  : $(node --version)"
    echo "  build : ./gradlew   (wrapper pins Gradle 9.7.0)"
    ${extra}
  '';
in
{
  default = pkgs.mkShell (
    common
    // {
      name = "spring-security";
      shellHook = banner "";
    }
  );

  # Opt-in, because it costs ~700MB of extra closure. `./gradlew -PtestToolchain=N` needs a
  # JDK N that Gradle can find, and the build registers no foojay resolver, so Gradle will
  # not fetch one on demand. Gradle reads this path list only from a command-line -D --
  # passing it through GRADLE_OPTS is silently ignored -- hence a variable to paste onto the
  # command line rather than something that just works.
  toolchains =
    let
      extraJdks = [
        pkgs.jdk17
        pkgs.jdk21
      ];
    in
    pkgs.mkShell (
      common
      // {
        name = "spring-security-toolchains";

        GRADLE_TOOLCHAINS =
          "-Dorg.gradle.java.installations.paths="
          + builtins.concatStringsSep "," (map (j: j.home) extraJdks);

        shellHook = banner ''
          echo '  tests : ./gradlew -PtestToolchain=17|21 ''$GRADLE_TOOLCHAINS test'
        '';
      }
    );
}
