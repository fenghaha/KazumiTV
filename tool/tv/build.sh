#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export KAZUMI_BUILD_TV=1
tv_device_profile="${KAZUMI_TV_DEVICE_PROFILE:-generic}"
case "$tv_device_profile" in
  generic|xgimi-z9x|hisense-mt9655) ;;
  *) echo "Unsupported KAZUMI_TV_DEVICE_PROFILE; use generic, xgimi-z9x or hisense-mt9655" >&2; exit 2 ;;
esac
tv_revision="${KAZUMI_TV_REVISION:-r5.7-$tv_device_profile}"
# Bound the shared build host's memory use; callers may supply an explicit budget.
export GRADLE_OPTS="${GRADLE_OPTS:--Dorg.gradle.daemon=false -Dorg.gradle.workers.max=1 -Dorg.gradle.jvmargs=-Xmx2048m -Dorg.gradle.project.kotlin.compiler.execution.strategy=in-process}"
flutter build apk --release --split-per-abi --flavor livingroom \
  --dart-define=KAZUMI_TV=true \
  --dart-define="KAZUMI_TV_REVISION=$tv_revision" \
  --dart-define="KAZUMI_TV_DEVICE_PROFILE=$tv_device_profile" "$@"
