{ lib, stdenv, python3, hyprwhspr-src, wl-clipboard, wtype, ydotool, pciutils }:

let
  # NixOS hat kein dpkg/pacman/rpm, und ydotool 1.0+ hat keinen --version-Flag:
  # der hyprwhspr-Versionscheck fiele sonst auf das hartkodierte "0.1.0 (too
  # old)" zurück. Der Wrapper beantwortet --version mit der echten Version und
  # reicht alle anderen Aufrufe an das echte ydotool durch.
  ydotoolWrap = stdenv.mkDerivation {
    pname = "ydotool-wrap";
    version = ydotool.version;
    dontUnpack = true;
    nativeBuildInputs = [ ];
    installPhase = ''
      mkdir -p $out/bin
      cat > $out/bin/ydotool <<EOF
      #!/usr/bin/env bash
      if [ "\$1" = "--version" ] || [ "\$1" = "-V" ]; then
        echo "ydotool ${ydotool.version}"
        exit 0
      fi
      exec "${ydotool}/bin/ydotool" "\$@"
      EOF
      chmod +x $out/bin/ydotool
    '';
  };
  runtimeDeps = [ wl-clipboard wtype ydotoolWrap pciutils ];
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
