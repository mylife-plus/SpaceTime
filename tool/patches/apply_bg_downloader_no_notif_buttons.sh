#!/usr/bin/env bash
# Strip Cancel/Pause/Resume action buttons from background_downloader Android notifications.
# Re-run after `flutter pub get` if buttons reappear.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PKG=$(ls -d "$HOME/.pub-cache/hosted/pub.dev/background_downloader-"* 2>/dev/null | sort -V | tail -1)
FILE="$PKG/android/src/main/kotlin/com/bbflight/background_downloader/Notifications.kt"
if [[ ! -f "$FILE" ]]; then
  echo "background_downloader Notifications.kt not found in pub-cache"
  exit 1
fi
if grep -q "SpaceTime product: tile download notification is progress-only" "$FILE"; then
  echo "Already patched: $FILE"
  exit 0
fi
python3 - <<'PY' "$FILE"
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
# Replace addNotificationActions body to tap-only
pat1 = re.compile(
    r"private fun addNotificationActions\(\s*taskWorker: TaskJobContext, notificationType: NotificationType, builder: Builder\s*\) \{.*?\n    \}",
    re.S,
)
repl1 = '''private fun addNotificationActions(
        taskWorker: TaskJobContext, notificationType: NotificationType, builder: Builder
    ) {
        val taskJsonString = Json.encodeToString<Task>(taskWorker.task)
        // Tap opens the app — no Cancel / Pause / Resume action buttons.
        // (SpaceTime product: tile download notification is progress-only.)
        addTapIntent(taskWorker, taskJsonString, notificationType, builder)
    }'''
text2, n1 = pat1.subn(repl1, text, count=1)
pat2 = re.compile(
    r"private fun addGroupNotificationActions\(\s*taskWorker: TaskJobContext,\s*notificationType: NotificationType,\s*groupNotification: GroupNotification,\s*builder: Builder\s*\) \{.*?\n    \}",
    re.S,
)
repl2 = '''private fun addGroupNotificationActions(
        taskWorker: TaskJobContext,
        notificationType: NotificationType,
        groupNotification: GroupNotification,
        builder: Builder
    ) {
        // Tap only — no Cancel button on group notifications (SpaceTime).
        addTapIntent(taskWorker, "", notificationType, builder)
    }'''
text3, n2 = pat2.subn(repl2, text2, count=1)
if n1 != 1 or n2 != 1:
    print(f"Patch failed (addNotificationActions={n1}, addGroupNotificationActions={n2})")
    sys.exit(1)
path.write_text(text3)
print(f"Patched: {path}")
PY
