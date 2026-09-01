{ lib, stdenv, python3, hyprwhspr-src, wl-clipboard, wtype, ydotool, pciutils }:

let
  runtimeDeps = [ wl-clipboard wtype ydotool pciutils ];
  binPath = lib.makeBinPath runtimeDeps;
  pythonEnv = python3.withPackages (ps: [
    ps.sounddevice
    ps.soxr
    ps.pyudev
    ps.pulsectl
    ps.rich
    ps.evdev
    ps.numpy
  ]);
in
stdenv.mkDerivation {
  pname = "hyprwhspr";
  version = "unstable";

  src = hyprwhspr-src;

  # Drop-in-Patch: erlaubt `faster-whisper` in `hyprwhspr setup auto` (nicht-interaktiv).
  postPatch = ''
    patch -p1 < ${./faster-whisper-auto.patch}
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/hyprwhspr $out/bin
    cp -r lib config share scripts bin $out/hyprwhspr/
    cp requirements*.txt $out/hyprwhspr/

    cat > $out/bin/hyprwhspr <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
export HYPRWHSPR_ROOT="$out/hyprwhspr"
export PATH="${pythonEnv}/bin:${binPath}:\$PATH"
export PYTHONUNBUFFERED=1
exec "$out/hyprwhspr/bin/hyprwhspr" "\$@"
WRAPPER
    chmod +x $out/bin/hyprwhspr

    runHook postInstall
  '';

  meta = with lib; {
    description = "Native speech-to-text for Linux (dictation)";
    homepage = "https://github.com/goodroot/hyprwhspr";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
