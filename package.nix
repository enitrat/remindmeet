# Built with swiftc directly: no SwiftPM, so nothing to fetch inside the build.
{
  lib,
  stdenv,
  swift,
}:
stdenv.mkDerivation {
  pname = "remindmeet";
  version = "0.1";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Sources
      ./Resources
    ];
  };
  nativeBuildInputs = [ swift ];

  buildPhase = ''
    runHook preBuild
    swiftc -O -module-name RemindMeet -target arm64-apple-macosx14.0 \
      Sources/RemindMeet/*.swift -o RemindMeet
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    contents=$out/Applications/RemindMeet.app/Contents
    install -Dm755 RemindMeet $contents/MacOS/RemindMeet
    install -Dm644 Resources/Info.plist $contents/Info.plist
    runHook postInstall
  '';

  # TCC remembers the calendar grant by the bundle's signature, so the whole bundle is
  # sealed with Apple's codesign; nixpkgs' sigtool signs only bare binaries. Doing it
  # after fixup keeps strip from breaking the seal. A source change gives a new
  # signature, and macOS asks for calendar access once more. Reaching /usr/bin needs
  # the Nix sandbox off, which is the default on macOS.
  postFixup = ''
    /usr/bin/codesign --force --sign - $out/Applications/RemindMeet.app
  '';

  meta = {
    description = "Full-screen reminder one minute before each meeting";
    mainProgram = "RemindMeet";
    platforms = [ "aarch64-darwin" ];
  };
}
