#!/usr/bin/env bash
set -euo pipefail

# Configure these values before running the build.
KEYSTORE_NAME="upload.keystore"
ANDROID_STORE_PASSWORD="android"
ANDROID_KEY_ALIAS="androiddebugkey"
ANDROID_KEY_PASSWORD="android"
BUILD_APK="true"
BUILD_AAB="true"
IMAGE_NAME="clipcascade/android-builder:local"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ARTIFACTS_DIR="$SCRIPT_DIR/artifacts"
KEYSTORE_PATH="$SCRIPT_DIR/$KEYSTORE_NAME"

mkdir -p "$ARTIFACTS_DIR"

if [[ ! -f "$KEYSTORE_PATH" ]]; then
  echo "Missing signing file: $KEYSTORE_PATH" >&2
  echo "Place your own signing keystore at that location, then update the variables at the top of this script." >&2
  exit 1
fi

# Build an image containing the source and signing file.
docker build \
  --no-cache \
  -f "$SCRIPT_DIR/Dockerfile" \
  --build-arg "KEYSTORE_NAME=$KEYSTORE_NAME" \
  -t "$IMAGE_NAME" \
  "$REPO_ROOT"

CONTAINER_ID="$(docker create \
  --env ANDROID_STORE_PASSWORD="$ANDROID_STORE_PASSWORD" \
  --env ANDROID_KEY_ALIAS="$ANDROID_KEY_ALIAS" \
  --env ANDROID_KEY_PASSWORD="$ANDROID_KEY_PASSWORD" \
  --env KEYSTORE_NAME="$KEYSTORE_NAME" \
  --env BUILD_APK="$BUILD_APK" \
  --env BUILD_AAB="$BUILD_AAB" \
  "$IMAGE_NAME" bash -lc ' \
    set -euo pipefail
    cd /workspace/ClipCascade_Mobile/src/android
    SIGNING_ARGS=(
      -PMYAPP_UPLOAD_STORE_FILE=/workspace/signing/"$KEYSTORE_NAME"
      -PMYAPP_UPLOAD_STORE_PASSWORD="$ANDROID_STORE_PASSWORD"
      -PMYAPP_UPLOAD_KEY_ALIAS="$ANDROID_KEY_ALIAS"
      -PMYAPP_UPLOAD_KEY_PASSWORD="$ANDROID_KEY_PASSWORD"
    )
    if [[ "$BUILD_APK" == "true" ]]; then ./gradlew --no-daemon assembleRelease "${SIGNING_ARGS[@]}"; fi
    if [[ "$BUILD_AAB" == "true" ]]; then ./gradlew --no-daemon bundleRelease "${SIGNING_ARGS[@]}"; fi
  ')"

cleanup() {
  docker rm -f "$CONTAINER_ID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker start -a "$CONTAINER_ID"

mkdir -p "$ARTIFACTS_DIR/apk" "$ARTIFACTS_DIR/aab"
docker cp "$CONTAINER_ID:/workspace/ClipCascade_Mobile/src/android/app/build/outputs/apk/release/." \
  "$ARTIFACTS_DIR/apk/" 2>/dev/null || true
docker cp "$CONTAINER_ID:/workspace/ClipCascade_Mobile/src/android/app/build/outputs/bundle/release/." \
  "$ARTIFACTS_DIR/aab/" 2>/dev/null || true

echo "Build output copied to: $ARTIFACTS_DIR"
find "$ARTIFACTS_DIR" -type f -printf '%P\n' | sort
