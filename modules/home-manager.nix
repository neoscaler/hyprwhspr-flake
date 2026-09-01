{ config, lib, pkgs, ... }:

let
  cfg = config.services.hyprwhspr;
  # Wrapper (setzt pythonEnv-PATH für CLI-Kommandos wie `setup auto`)
  bin = "${cfg.package}/bin/hyprwhspr";
  # Python fürs Venv: per Option festlegbar (faster-whisper braucht Python 3.13),
  # sonst das vom Modul mitgelieferte pkgs.python3.
  pyPkgs = if cfg.python != null then cfg.python else pkgs.python3;
  # site-packages eines Python-Pakets im Store (Version folgt dem Venv-Python)
  pySite = p: "${p}/lib/${p.libPrefix}/site-packages";
in
{
  options.services.hyprwhspr = {
    enable = lib.mkEnableOption "hyprwhspr speech-to-text dictation";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.hyprwhspr;
      description = "hyprwhspr package (the overlay provides pkgs.hyprwhspr).";
    };

    backend = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Backend für `hyprwhspr setup auto` (--backend). Lokale ML-Backends:
        'nvidia' (whisper.cpp CUDA, braucht System-CUDA-Toolkit), 'vulkan',
        'cpu', 'onnx-asr', 'faster-whisper' (CTranslate2, NVIDIA-Treiber reicht).
        Null lässt hyprwhspr automatisch erkennen.
      '';
    };

    python = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        Python-Interpreter fürs hyprwhspr-Venv. Standard: pkgs.python3. Für das
        faster-whisper-Backend pkgs.python313 verwenden ('av' hat für das
        nicht-free-threaded 3.14 keine fertigen Wheels).
      '';
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "small";
      description = "Whisper model downloaded and configured (e.g. 'base', 'small', 'large-v3').";
    };

    language = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Language locked in the config, e.g. 'de'. Null leaves it auto-detect.";
    };

    noctalia = {
      enable = lib.mkEnableOption "Noctalia bar widget (noctwhspr)";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      cfg.package
      pkgs.wl-clipboard
      pkgs.wtype
      # pactl für die Mic-Erkennung des Noctalia/Waybar-Tray-Scripts
      pkgs.pulseaudio
    ];

    systemd.user.services = {
      # Provisioniert Venv + Backend (erster Login bzw. bei Backend-Wechsel) und
      # hält danach Konfiguration + gewähltes Whisper-Modell auf Stand.
      hyprwhspr-setup = {
        Unit = {
          Description = "hyprwhspr venv + model provision";
          PartOf = [ "graphical-session.target" ];
        };

        Service = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "hyprwhspr-setup" ''
            set -euo pipefail
            VENV="''${XDG_DATA_HOME:-$HOME/.local/share}/hyprwhspr/venv/bin/python"
            CFG="$HOME/.config/hyprwhspr/config.json"
            # Setup nur, wenn venv fehlt oder das gewünschte Backend nicht
            # konfiguriert ist (hyprwhspr legt das venv bei Backend-Wechsel neu an).
            needs_setup=0
            if [ ! -x "$VENV" ]; then
              needs_setup=1
            fi
            ${lib.optionalString (cfg.backend != null) ''
            if [ -f "$CFG" ] && [ -x "$VENV" ]; then
              current="$("$VENV" -c 'import json,sys; print(json.load(open(sys.argv[1])).get("transcription_backend",""))' "$CFG" 2>/dev/null || true)"
              if [ "$current" != "${cfg.backend}" ]; then
                needs_setup=1
              fi
            fi
            ''}
            if [ "$needs_setup" = 1 ]; then
              ${bin} setup auto --model ${cfg.model} \
                ${lib.optionalString (cfg.backend != null) "--backend ${cfg.backend}"} \
                ${lib.optionalString (cfg.python != null) "--python ${cfg.python}/bin/python"} \
                --no-systemd --no-mic-osd --no-waybar
            fi
            # Modell-Download ist idempotent; danach Config deterministisch setzen.
            if ${bin} model download ${cfg.model}; then
              "$VENV" - "$CFG" <<'PY'
            import json
            import sys

            p = sys.argv[1]
            with open(p) as f:
                d = json.load(f)
            d["model"] = ${builtins.toJSON cfg.model}
            ${lib.optionalString (cfg.backend != null) ''
            d["transcription_backend"] = ${builtins.toJSON cfg.backend}''}
            ${lib.optionalString (cfg.language != null) ''
            d["language"] = ${builtins.toJSON cfg.language}''}
            with open(p, "w") as f:
                json.dump(d, f, indent=2)
            PY
            fi
            ${lib.optionalString cfg.noctalia.enable ''
            # Noctalia-Widget: Da Noctalia Plugins nur lädt, wenn sie in [plugins].enabled
            # seines settings.toml stehen (Laufzeit-State), aktiviert der idempotente
            # `noctalia install`-Aufruf das Widget best-effort beim Login.
            if ${bin} noctalia install; then
              :
            else
              echo "noctalia integration failed (best effort)" >&2
            fi
            ''}
          '';
          TimeoutStartSec = 0;
          StandardOutput = "journal";
          StandardError = "journal";
        };

        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };

      hyprwhspr = {
        Unit = {
          Description = "hyprwhspr stt";
          PartOf = [ "graphical-session.target" ];
          After = [
            "graphical-session.target"
            "hyprwhspr-setup.service"
            "pipewire.service"
            "wireplumber.service"
          ];
          Requires = [ "hyprwhspr-setup.service" ];
          Wants = [ "pipewire.service" "wireplumber.service" ];
        };

        Service = {
          Type = "simple";
          ExecStartPre = pkgs.writeShellScript "hyprwhspr-wait-wl" ''
            for i in $(seq 1 60); do
              if [ -n "$WAYLAND_DISPLAY" ]; then
                case "$WAYLAND_DISPLAY" in
                  /*) ws="$WAYLAND_DISPLAY" ;;
                  *)  ws="''${XDG_RUNTIME_DIR}/$WAYLAND_DISPLAY" ;;
                esac
                [ -S "$ws" ] && exit 0
              fi
              [ -n "$DISPLAY" ] && exit 0
              if [ -n "$XDG_RUNTIME_DIR" ]; then
                for ws in "$XDG_RUNTIME_DIR"/wayland-*; do
                  [ -S "$ws" ] && exit 0
                done
              fi
              sleep 0.25
            done
            echo "No usable Wayland socket or X11 DISPLAY found" >&2
            exit 1
          '';
          ExecStart = bin;
          ExecStopPost = pkgs.writeShellScript "hyprwhspr-cleanup" ''
            pkill -9 -f "hyprwhspr-virtual-keyboar[d]" 2>/dev/null
            pkill -9 -f "hyprwhspr-ydotool.soc[k]" 2>/dev/null
            true
          '';
          Environment = [
            "HYPRWHSPR_ROOT=${cfg.package}/hyprwhspr"
            "PYTHONUNBUFFERED=1"
            # dbus-python + PyGObject für MEDIA_PAUSER (MPRIS pausieren) und
            # SUSPEND_MONITOR; GLib-Typelibs über GI_TYPELIB_PATH/LD_LIBRARY_PATH.
            # Site-Packages folgen dem Venv-Python (pyPkgs), sonst Version-Mismatch.
            "PYTHONPATH=${pySite pyPkgs.pkgs.pygobject3}:${pySite pyPkgs.pkgs.dbus-python}"
            "GI_TYPELIB_PATH=${pkgs.glib.out}/lib/girepository-1.0"
            "LD_LIBRARY_PATH=${pkgs.glib.out}/lib"
          ];
          Restart = "on-failure";
          RestartSec = 2;
          StandardOutput = "journal";
          StandardError = "journal";
        };

        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };
    };
  };
}
