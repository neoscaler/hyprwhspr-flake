{ config, lib, pkgs, ... }:

let
  cfg = config.services.hyprwhspr.system;
in
{
  options.services.hyprwhspr.system = {
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.hyprwhspr;
      description = "hyprwhspr package (the overlay provides pkgs.hyprwhspr).";
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Usernames granted the input/audio/tty groups needed for the virtual
        keyboard (uinput), microphone access and terminal tooling.
      '';
    };

    udevRule = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Add the uinput udev rule so ydotool can inject keystrokes.";
    };

    usrLibSymlink = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Symlink the package to /usr/lib/hyprwhspr. Upstream hardcodes this
        path in its systemd template, waybar module and noctalia bar widget,
        so the symlink makes the store path resolve there.
      '';
    };
  };

  config = lib.mkIf (cfg.udevRule || cfg.usrLibSymlink || cfg.users != [ ]) {
    services.udev.extraRules = lib.mkIf cfg.udevRule ''
      KERNEL=="uinput", GROUP="input", MODE="0660"
    '';

    users.users = lib.mkIf (cfg.users != [ ]) (lib.genAttrs cfg.users (_: {
      extraGroups = [ "input" "audio" "tty" ];
    }));

    systemd.tmpfiles.rules = lib.mkIf cfg.usrLibSymlink [
      "L+ /usr/lib/hyprwhspr - - - - ${cfg.package}/hyprwhspr"
    ];
  };
}
