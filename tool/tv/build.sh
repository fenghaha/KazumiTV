#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export KAZUMI_BUILD_TV=1
flutter build apk --release --split-per-abi --flavor livingroom \
  --dart-define=KAZUMI_TV=true \
  --dart-define="KAZUMI_TV_REVISION=${KAZUMI_TV_REVISION:-r4}" "$@"
