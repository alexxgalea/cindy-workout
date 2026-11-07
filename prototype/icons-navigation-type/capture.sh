#!/bin/zsh
# Re-capture the real screens over adb into captures/, replacing the 2026-11-06 ones.
# Put the phone on each screen as asked, then press Enter. Needs one attached device.
ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
HERE="${0:A:h}"
"$ADB" devices -l
[ -n "$("$ADB" devices | sed -n '2p')" ] || { echo "No device attached. Nothing captured."; exit 1; }
for pair in "camera:Camera, idle, with yourself in the picture" "menu:Menu, top of the page" \
            "progress:Progress, top of the page" "session:Session page, top (a finished session)" \
            "you:You, top of the page" "sheet:Movements sheet (Menu > Movements)"; do
  name="${pair%%:*}"; what="${pair#*:}"
  read "?$what, then Enter (s to skip): " ans
  [ "$ans" = "s" ] && continue
  "$ADB" exec-out screencap -p > "$HERE/captures/$name.png" && echo "  saved captures/$name.png"
done
