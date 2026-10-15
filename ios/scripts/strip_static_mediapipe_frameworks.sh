#!/bin/sh
# Google's MediaPipe iOS "frameworks" are static archives with incomplete Info.plist.
# Xcode embeds them into Runner.app/Frameworks/ where App Store validation rejects them
# (ITMS-90056/90057: missing CFBundleVersion / CFBundleShortVersionString). Code is
# already statically linked.
set -eu

for fw in MediaPipeTasksCommon MediaPipeTasksVision; do
  path="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/${fw}.framework"
  if [ -d "${path}" ]; then
    rm -rf "${path}"
    echo "note: removed static ${fw}.framework from app bundle"
  fi
done
