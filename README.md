# hyprwhspr-flake

Declarative [hyprwhspr](https://github.com/goodroot/hyprwhspr) speech-to-text
dictation for NixOS + Home Manager: Nix package, Home Manager module and
NixOS module. Upstream is pinned to the release tag **v1.43.0** (not the
moving `main` branch).

## Usage

NixOS module (groups, udev rule, upstream-compatible `/usr/lib/hyprwhspr`):

```nix
{
  inputs.hyprwhspr-flake.url = "github:neoscaler/hyprwhspr-flake";

  nixosConfigurations.host = nixpkgs.lib.nixosSystem {
    modules = [
      hyprwhspr-flake.nixosModules.hyprwhspr
      {
        nixpkgs.overlays = [ hyprwhspr-flake.overlays.default ];
        services.hyprwhspr.system.users = [ "youruser" ];
        # services.hyprwhspr.system.udevRule = true;     # default
        # services.hyprwhspr.system.usrLibSymlink = true; # default
      }
    ];
  };
}
```

Home Manager module (houseup service, model provisioning):

```nix
{ config, pkgs, ... }:
{
  imports = [ hyprwhspr-flake.homeManagerModules.hyprwhspr ];

  services.hyprwhspr = {
    enable = true;
    # model = "small";        # default: small, language locked to null
    # language = "de";        # German: pair with model = "large-v3"
    # noctalia.enable = true; # Noctalia bar widget (see below)
  };
}
```

German dictation with best quality:

```nix
services.hyprwhspr = {
  enable = true;
  model = "large-v3";
  language = "de";
};
```

## Options

### Home Manager (`services.hyprwhspr.*`)

| Option          | Default   | Description                                             |
| --------------- | --------- | ------------------------------------------------------- |
| `enable`        | `false`   | Enable the user service, tray deps and model provisioning |
| `package`       | `pkgs.hyprwhspr` | Package to use (overlay provides `pkgs.hyprwhspr`)       |
| `backend`       | `null`    | Backend: `"faster-whisper"`, `"nvidia"`, `"vulkan"`, `"cpu"`, `"onnx-asr"`, `"cohere-transcribe"`, `"rest-api"`, `"realtime-ws"`; `null` = auto-detect |
| `python`        | `null`    | Python for the venv (e.g. `pkgs.python313` for faster-whisper; `null` = `pkgs.python3`) |
| `model`         | `small`   | Whisper model (cpu/nvidia/vulkan/faster-whisper)          |
| `onnxAsr.model` | `nemo-parakeet-tdt-0.6b-v3` | onnx-asr model id                       |
| `language`      | `null`    | Locked language (e.g. `"de"`); `null` = auto-detect      |
| `fasterWhisper.device` | `null` | `"auto"`/`"cpu"`/`"cuda"` override                    |
| `fasterWhisper.computeType` | `null` | `"auto"`/`"int8"`/`"int8_float16"`/`"float16"`/`"float32"` |
| `restApi.*`     | `null`    | `endpointUrl` (Pflicht), `provider`, `timeout`, `secretsFile` (JSON-Datei mit `rest_api_key`/`rest_headers`/`rest_body`) |
| `realtimeWs.*`  | `null`    | `url` (Pflicht), `model`                                  |
| `noctalia.enable` | `false` | Install/enable the Noctalia bar widget (noctwhspr)      |

### NixOS (`services.hyprwhspr.system.*`)

| Option          | Default | Description                                               |
| --------------- | ------- | --------------------------------------------------------- |
| `package`       | `pkgs.hyprwhspr` | Package to symlink                                        |
| `users`         | `[]`    | Usernames granted `input`/`audio`/`tty` groups            |
| `udevRule`      | `true`  | `uinput` udev rule for the virtual keyboard (ydotool)     |
| `usrLibSymlink` | `true`  | Symlink to `/usr/lib/hyprwhspr` (upstream-hardcoded path) |

## Notes

- **Secrets**: REST-Secrets (`rest_api_key`/`rest_headers`/`rest_body`) gehen
  nicht über Moduloptionen, sondern über `restApi.secretsFile` (absoluter Pfad
  zu einer JSON-Datei, z.B. sops/agenix unter `/run/secrets/…`). Der
  Setup-Service merged sie zur Laufzeit in `~/.config/hyprwhspr/config.json`,
  damit sie nie im Nix-Store landen.
- **CUDA-Libs** werden nur bei `backend = "faster-whisper"` oder `"nvidia"`
  eingebunden. Bei `backend = null` (auto) und NVIDIA also explizit setzen,
  sonst fehlen `libcudart`/`libcublas`/`libcudnn` zur Laufzeit. Vulkan/CPU
  ziehen kein CUDA mehr in die Closure.
- **Venv + model** are provisioned once at first login by the
  `hyprwhspr-setup` user service (idempotent; layer-config updates on later
  logins). Model downloads land in `~/.local/share/hyprwhspr`.
- **Waybar**: the widget files ship under `/usr/lib/hyprwhspr/config/waybar`
  (see the `usrLibSymlink`). v1 has no declarative waybar wiring — install the
  module manually: `hyprwhspr waybar install`.
- **Noctalia**: files live in the store, but Noctalia only *loads* a plugin
  when its id is in `[plugins].enabled` (its own runtime `settings.toml`), so
  activation is delegated to the idempotent `hyprwhspr noctalia install` run
  best-effort at login. Requires `usrLibSymlink` for the widget's tray lookup.

- **mic-OSD-Overlay wird NICHT unterstützt.** Das Layer-Shell-Overlay
  (`hyprwhspr mic-osd`) braucht GTK4- + `gtk4-layer-shell`-GIR/Typelibs,
  die im NixOS-Store nicht sauber auflösbar sind (fehlendes `Cairo-1.0.typelib`).
  Der Modul-Setup läuft deshalb immer mit `--no-mic-osd`;
  `mic_osd_enabled` wird nicht in `config.json` gesetzt. Aufnahme-Status
  erscheint stattdessen über eure Bare-Übersicht (z.B. Noctalia-/Waybar-Tray).
- Requires `nixpkgs.overlays = [ hyprwhspr-flake.overlays.default ]` for the
  `pkgs.hyprwhspr` default (or set the `package` option explicitly).

## Development

```sh
nix flake check
nix build .#hyprwhspr
```
