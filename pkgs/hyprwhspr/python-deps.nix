# Runtime-Python-Deps für hyprwhspr.
# Einzige Quelle für Paket (pythonEnv) und Home-Manager-Venv (venvPython),
# damit die Listen nicht auseinanderdriften.
# pygobject3 + requests bewusst auch im Paket: der HM-Setup-Service braucht sie
# für MEDIA_PAUSER (MPRIS via PyGObject/dbus) bzw. den Backends-Router-Import.
ps: with ps; [
  sounddevice
  soxr
  pyudev
  pulsectl
  rich
  evdev
  numpy
  pygobject3
  requests
]
