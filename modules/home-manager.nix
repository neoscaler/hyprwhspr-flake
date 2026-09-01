{ config, lib, pkgs, ... }:

let
  cfg = config.services.hyprwhspr;

  # Wrapper (setzt pythonEnv-PATH für CLI-Kommandos wie `setup auto`)
  bin = "${cfg.package}/bin/hyprwhspr";

  # Backend-Klassifikation
  whisperFamily = [ "cpu" "nvidia" "vulkan" "faster-whisper" ];
  mlLocal = whisperFamily ++ [ "onnx-asr" "cohere-transcribe" ];
  cloudBackends = [ "rest-api" "realtime-ws" ];
  isWhisper = builtins.elem cfg.backend whisperFamily;
  isMlLocal = builtins.elem cfg.backend mlLocal;
  autoDetect = cfg.backend == null;

  # Python-Interpreter fürs Venv: per Option festlegbar (faster-whisper/cohere
  # brauchen Python 3.13), sonst pkgs.python3. `withPackages` legt dieselben
  # Runtime-Deps wie das Paket hinein (numpy, evdev, sounddevice, …); das Venv
  # nutzt sie via --system-site-packages, damit pip nichts selbst kompiliert.
  interp = if cfg.python != null then cfg.python else pkgs.python3;
  venvPython = interp.withPackages (ps: with ps; [
    sounddevice
    soxr
    pyudev
    pulsectl
    rich
    evdev
    numpy
  ]);
  # site-packages eines Python-Pakets im Store (Version folgt dem Venv-Python)
  pySite = p: "${p}/lib/${interp.libPrefix}/site-packages";

  # Cohere akzeptiert nur diese Sprachen (das Modell hat keine Auto-Detection).
  cohereLanguages = [ "ar" "de" "el" "en" "es" "fr" "it" "ja" "ko" "nl" "pl" "pt" "vi" "zh" ];

  langKey = lib.optionalAttrs (cfg.language != null) { language = cfg.language; };

  # Deterministische Config-Keys je Backend (werden beim Setup in config.json
  # geschrieben; 'auto' lässt hyprwhspr das Backend selbst erkennen).
  keys =
    if autoDetect then
      { model = cfg.model; }
      // langKey
    else if cfg.backend == "faster-whisper" then
      { transcription_backend = "faster-whisper"; model = cfg.model; faster_whisper_model = cfg.model; }
      // lib.optionalAttrs (cfg.fasterWhisper.device != null) { faster_whisper_device = cfg.fasterWhisper.device; }
      // lib.optionalAttrs (cfg.fasterWhisper.computeType != null) { faster_whisper_compute_type = cfg.fasterWhisper.computeType; }
      // langKey
    else if isWhisper then
      { transcription_backend = cfg.backend; model = cfg.model; }
      // langKey
    else if cfg.backend == "onnx-asr" then
      { transcription_backend = "onnx-asr"; onnx_asr_model = cfg.onnxAsr.model; }
      // langKey
    else if cfg.backend == "cohere-transcribe" then
      { transcription_backend = "cohere-transcribe"; }
      // langKey
    else if cfg.backend == "rest-api" then
      { transcription_backend = "rest-api"; rest_endpoint_url = cfg.restApi.endpointUrl; }
      // lib.optionalAttrs (cfg.restApi.provider != null) { rest_api_provider = cfg.restApi.provider; }
      // lib.optionalAttrs (cfg.restApi.apiKey != null) { rest_api_key = cfg.restApi.apiKey; }
      // lib.optionalAttrs (cfg.restApi.timeout != null) { rest_timeout = cfg.restApi.timeout; }
      // lib.optionalAttrs (cfg.restApi.headers != null) { rest_headers = cfg.restApi.headers; }
      // lib.optionalAttrs (cfg.restApi.body != null) { rest_body = cfg.restApi.body; }
      // langKey
    else if cfg.backend == "realtime-ws" then
      { transcription_backend = "realtime-ws"; websocket_url = cfg.realtimeWs.url; }
      // lib.optionalAttrs (cfg.realtimeWs.model != null) { websocket_model = cfg.realtimeWs.model; }
      // langKey
    else
      { };

  # setup auto bekommt nur für lokale ML-Backends ein --backend; das --model
  # ist Whisper-Modell (auto/Whisper-Familie) bzw. das onnx-asr-Modell.
  modelArg =
    if cfg.backend == "onnx-asr" then
      "--model ${cfg.onnxAsr.model}"
    else if (autoDetect || isWhisper) then
      "--model ${cfg.model}"
    else
      "";
  backendArg = lib.optionalString (cfg.backend != null && isMlLocal) "--backend ${cfg.backend}";
  pythonArg = "--python ${venvPython}/bin/python";

  # Modell-Download nur für die Whisper-Familie (+ auto); onnx-asr/cohere/Cloud
  # laden beim Install bzw. ersten Lauf.
  downloadModel = autoDetect || isWhisper;
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
      type = lib.types.nullOr (lib.types.enum (mlLocal ++ cloudBackends));
      default = null;
      description = ''
        Backend für `hyprwhspr setup auto`. Lokale ML-Backends: 'faster-whisper'
        (CTranslate2, NVIDIA-Treiber reicht – Empfehlung), 'nvidia'/'vulkan'/'cpu'
        (whisper.cpp; nvidia/vulkan brauchen zusätzlich System-Toolchains),
        'onnx-asr' (Parakeet), 'cohere-transcribe'. Cloud ('rest-api',
        'realtime-ws') installieren nichts, nur Config. Null lässt hyprwhspr
        automatisch erkennen.
      '';
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "small";
      description = "Whisper model downloaded and configured (e.g. 'base', 'small', 'large-v3').";
    };

    onnxAsr = {
      model = lib.mkOption {
        type = lib.types.str;
        default = "nemo-parakeet-tdt-0.6b-v3";
        description = "onnx-asr model id (relevant bei backend = 'onnx-asr').";
      };
    };

    language = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Language locked in the config, e.g. 'de'. Null leaves it auto-detect.";
    };

    python = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        Python-Interpreter fürs hyprwhspr-Venv (wird automatisch mit den
        Runtime-Deps numpy/evdev/sounddevice/… gewrappt). Standard: pkgs.python3.
        Für faster-whisper/cohere pkgs.python313 verwenden ('av' hat für das
        nicht-free-threaded 3.14 keine fertigen Wheels).
      '';
    };

    fasterWhisper = {
      device = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "auto" "cpu" "cuda" ]);
        default = null;
        description = "faster-whisper device override; Null = 'auto'.";
      };
      computeType = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "auto" "int8" "int8_float16" "float16" "float32" ]);
        default = null;
        description = "faster-whisper compute_type override; Null = 'auto' (CUDA: int8).";
      };
    };

    restApi = {
      endpointUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "REST-API endpoint URL (backend = 'rest-api').";
      };
      provider = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "REST-API provider id (optional, für bekannte Provider).";
      };
      apiKey = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "REST-API key (optional, je nach Endpoint).";
      };
      timeout = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "REST-API timeout in Sekunden (optional).";
      };
      headers = lib.mkOption {
        type = lib.types.nullOr lib.types.attrs;
        default = null;
        description = "Zusätzliche REST-Headers (optional).";
      };
      body = lib.mkOption {
        type = lib.types.nullOr lib.types.attrs;
        default = null;
        description = "Zusätzliche REST-Body-Felder (optional).";
      };
    };

    realtimeWs = {
      url = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Realtime-WebSocket-URL (backend = 'realtime-ws').";
      };
      model = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Realtime-WebSocket-Modell (optional).";
      };
    };

    noctalia = {
      enable = lib.mkEnableOption "Noctalia bar widget (noctwhspr)";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.backend != "cohere-transcribe" || cfg.language == null || builtins.elem cfg.language cohereLanguages;
        message = "services.hyprwhspr: cohere-transcribe unterstützt language '${toString cfg.language}' nicht (erlaubt: ${builtins.concatStringsSep ", " cohereLanguages}).";
      }
      {
        assertion = cfg.backend != "rest-api" || cfg.restApi.endpointUrl != null;
        message = "services.hyprwhspr: backend 'rest-api' braucht services.hyprwhspr.restApi.endpointUrl.";
      }
      {
        assertion = cfg.backend != "realtime-ws" || cfg.realtimeWs.url != null;
        message = "services.hyprwhspr: backend 'realtime-ws' braucht services.hyprwhspr.realtimeWs.url.";
      }
    ];
    home.packages = [
      cfg.package
      pkgs.wl-clipboard
      pkgs.wtype
      # pactl für die Mic-Erkennung des Noctalia/Waybar-Tray-Scripts
      pkgs.pulseaudio
    ];

    systemd.user.services = {
      # Provisioniert Venv + Backend (erster Login bzw. bei Backend-Wechsel),
      # lädt für Whisper-Backends das Modell und schreibt die Config deterministisch.
      hyprwhspr-setup = {
        Unit = {
          Description = "hyprwhspr provision + config";
          PartOf = [ "graphical-session.target" ];
        };

        Service = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "hyprwhspr-setup" ''
            set -euo pipefail
            VENV="''${XDG_DATA_HOME:-$HOME/.local/share}/hyprwhspr/venv/bin/python"
            CFG="$HOME/.config/hyprwhspr/config.json"

            # --- Backend/venv-Provisioning (nur lokale ML-Backends) ---
            ${lib.optionalString (autoDetect || isMlLocal) ''
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
              ${bin} setup auto ${modelArg} ${backendArg} ${pythonArg} --no-systemd --no-mic-osd --no-waybar
            fi
            ''}

            # --- Modell-Download (Whisper-Familie) — idempotent, nicht fatal ---
            ${lib.optionalString downloadModel ''
            if ${bin} model download ${cfg.model}; then
              :
            else
              echo "model download failed (best effort)" >&2
            fi
            ''}

            # --- Config deterministisch setzen (alle Backends) ---
            ${venvPython}/bin/python - "$CFG" <<'PY'
            import json
            import sys
            import os

            p = sys.argv[1]
            if os.path.exists(p):
                with open(p) as f:
                    d = json.load(f)
            else:
                d = {}
            for k, v in ${builtins.toJSON keys}.items():
                d[k] = v
            with open(p, "w") as f:
                json.dump(d, f, indent=2)
            PY

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
            # Site-Packages folgen dem Venv-Python (interp), sonst Version-Mismatch.
            "PYTHONPATH=${pySite interp.pkgs.pygobject3}:${pySite interp.pkgs.dbus-python}"
            "GI_TYPELIB_PATH=${pkgs.glib.out}/lib/girepository-1.0"
            # NixOS: Pip-Wheels (av/ffmpeg) laden schwachgebundene System-Libs
            # (libz, libbz2, liblzma, libstdc++) — ohne LD_LIBRARY_PATH findet
            # sie der Loader auf NixOS nicht (kein globales ld.so.conf).
            # /run/opengl-driver/lib liefert libcuda.so.1 (NVIDIA-Treiber).
            "LD_LIBRARY_PATH=${pkgs.glib.out}/lib:${pkgs.zlib}/lib:${pkgs.bzip2}/lib:${pkgs.xz}/lib:${pkgs.stdenv.cc.cc.lib}/lib:/run/opengl-driver/lib"
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
