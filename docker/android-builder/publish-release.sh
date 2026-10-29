#!/usr/bin/env bash
set -euo pipefail
#bash docker/android-builder/publish-release.sh --publish
# Configure these values before publishing.
APK_SOURCE=""
TAG=""
RELEASE_TITLE=""
RELEASE_NOTES_FILE=""
PUBLISH="false"
RELEASE_ASSET_NAME="app-release.apk"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ASSET_DIR="$SCRIPT_DIR/release-assets"

usage() {
  cat <<'EOF'
Usage: bash docker/android-builder/publish-release.sh [options]

Options:
  --apk PATH                 Local release APK (default: artifacts/apk/app-release.apk)
  --tag TAG                  GitHub release tag (default: v<version.json release>)
  --title TITLE              Release title (default: ClipCascade v<version>)
  --notes PATH               Release notes Markdown file
  --publish                  Publish immediately; without this option, create/update a draft
  -h, --help                 Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apk) APK_SOURCE="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --title) RELEASE_TITLE="$2"; shift 2 ;;
    --notes) RELEASE_NOTES_FILE="$2"; shift 2 ;;
    --publish) PUBLISH="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

cd "$REPO_ROOT"

ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
if [[ "$ORIGIN_URL" =~ github\.com[:/]([^/]+/[^/.]+)(\.git)?$ ]]; then
  export GH_REPO="${BASH_REMATCH[1]}"
else
  echo "Could not determine the GitHub repository from origin: $ORIGIN_URL" >&2
  exit 1
fi

if [[ -z "$APK_SOURCE" ]]; then
  APK_SOURCE="$SCRIPT_DIR/artifacts/apk/app-release.apk"
fi
if [[ ! -f "$APK_SOURCE" ]]; then
  echo "Missing APK: $APK_SOURCE" >&2
  echo "Run docker/android-builder/build-release.sh first." >&2
  exit 1
fi

command -v gh >/dev/null 2>&1 || { echo "GitHub CLI 'gh' is required" >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

RELEASE_VERSION="$(python3 -c 'import json; print(json.load(open("version.json", encoding="utf-8"))["release"])')"
if [[ -z "$TAG" ]]; then
  TAG="v$RELEASE_VERSION"
fi
if [[ -z "$RELEASE_TITLE" ]]; then
  RELEASE_TITLE="ClipCascade v$RELEASE_VERSION"
fi

if [[ -z "$RELEASE_NOTES_FILE" ]]; then
  RELEASE_NOTES_FILE="$(mktemp "${TMPDIR:-/tmp}/clipcascade-release-notes.XXXXXX.md")"
  trap 'rm -f "$RELEASE_NOTES_FILE"' EXIT

  LOCAL_BASE="$(git merge-base main HEAD 2>/dev/null || printf '%s' main)"
  LOCAL_COMMITS="$(git log --reverse --format='- %s (%h)' "$LOCAL_BASE"..HEAD 2>/dev/null || true)"
  cat > "$RELEASE_NOTES_FILE" <<EOF
## 🚀 ClipCascade-shizuku v$RELEASE_VERSION Android 


## Changes

EOF

  if [[ -n "$LOCAL_COMMITS" ]]; then
    echo "$LOCAL_COMMITS" >> "$RELEASE_NOTES_FILE"
  else
    echo "- No commits unique to this local branch were found." >> "$RELEASE_NOTES_FILE"
  fi

fi
if [[ ! -f "$RELEASE_NOTES_FILE" ]]; then
  echo "Release notes file not found: $RELEASE_NOTES_FILE" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI is not authenticated. Run: gh auth login" >&2
  exit 1
fi

mkdir -p "$ASSET_DIR"
cp -f "$APK_SOURCE" "$ASSET_DIR/$RELEASE_ASSET_NAME"

TARGET_SHA="$(git rev-parse HEAD)"
ASSET_SHA="$(sha256sum "$ASSET_DIR/$RELEASE_ASSET_NAME" | awk '{print $1}')"

echo "Tag: $TAG"
echo "Asset: $RELEASE_ASSET_NAME"
echo "SHA-256: $ASSET_SHA"

if release_json=$(gh release view "$TAG" --json isDraft,assets 2>/dev/null); then
  release_state="$(python3 - "$release_json" "$RELEASE_ASSET_NAME" <<'PY'
import json, sys
release = json.loads(sys.argv[1])
asset_name = sys.argv[2]
has_asset = any(asset["name"] == asset_name for asset in release.get("assets", []))
if release.get("isDraft"):
    print("draft")
elif has_asset:
    print("published")
else:
    raise SystemExit(f"Published release is missing the expected asset: {asset_name}")
PY
)"
  if [[ "$release_state" == "published" ]]; then
    echo "Release $TAG is already published with $RELEASE_ASSET_NAME; no changes made."
    exit 0
  fi
else
  gh release create "$TAG" --draft --title "$RELEASE_TITLE" \
    --notes-file "$RELEASE_NOTES_FILE" --target "$TARGET_SHA"
fi

gh release upload "$TAG" "$ASSET_DIR/$RELEASE_ASSET_NAME" --clobber

if [[ "$PUBLISH" == "true" ]]; then
  gh release edit "$TAG" --draft=false --latest
  echo "Release published: $TAG"
else
  echo "Draft release updated: $TAG"
fi
