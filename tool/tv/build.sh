#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export KAZUMI_BUILD_TV=1
# Bound the shared build host's memory use; callers may supply an explicit budget.
export GRADLE_OPTS="${GRADLE_OPTS:--Dorg.gradle.daemon=false -Dorg.gradle.workers.max=1 -Dorg.gradle.jvmargs=-Xmx2048m -Dorg.gradle.project.kotlin.compiler.execution.strategy=in-process}"
flutter build apk --release --split-per-abi --flavor livingroom \
  --dart-define=KAZUMI_TV=true \
  --dart-define="KAZUMI_TV_REVISION=${KAZUMI_TV_REVISION:-r5.4}" "$@"
