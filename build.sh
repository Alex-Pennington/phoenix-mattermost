#!/bin/bash
# Build the Phoenix Nest Mattermost Team Edition image: the stock image with
# its server binary replaced by one built from the AGPL source plus
# gitlab-sso-team-edition.patch.
#
# Usage: bash build.sh [WORKDIR]
#
# WORKDIR (default $HOME/mm-phoenix-build) holds the downloaded source, the
# Go caches and the built binary. It must be outside this repo: the source
# is untrusted and is only ever compiled inside a container.
#
# Environment overrides (defaults are the current release):
#   MM_VERSION     upstream tag without the v      (11.11.1)
#   PHOENIX_REV    our build suffix                (phoenix1)
#   BASE_DIGEST    digest of the stock image to build FROM
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MM_VERSION="${MM_VERSION:-11.11.1}"
PHOENIX_REV="${PHOENIX_REV:-phoenix1}"
BASE_DIGEST="${BASE_DIGEST:-sha256:6ad5912b45875ef2fafc41886b5a70a3ec1b6c17ec706e0492566e8a2fd8aa85}"
BUILD_NUMBER="${MM_VERSION}-${PHOENIX_REV}"
BASE_IMAGE="mattermost/mattermost-team-edition:${MM_VERSION}@${BASE_DIGEST}"
TARGET_IMAGE="phoenix/mattermost-team-edition:${BUILD_NUMBER}"

WORKDIR="${1:-$HOME/mm-phoenix-build}"
case "$WORKDIR" in /*) ;; *) echo "WORKDIR must be absolute" >&2; exit 2 ;; esac
REPO_ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
case "$WORKDIR/" in "$REPO_ROOT"/*) echo "WORKDIR must be outside $REPO_ROOT" >&2; exit 2 ;; esac

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
SRC="$WORKDIR/src-v${MM_VERSION}-${STAMP}"
OUT="$WORKDIR/out-${BUILD_NUMBER}"
CACHE="$WORKDIR/gocache"
mkdir -p "$WORKDIR" "$OUT" "$CACHE/build" "$CACHE/mod"

echo "== 1. fetch source v${MM_VERSION} into a fresh dir: $SRC"
git clone --quiet --depth 1 --branch "v${MM_VERSION}" https://github.com/mattermost/mattermost.git "$SRC"
BUILD_HASH="$(git -C "$SRC" rev-parse HEAD)"
echo "   commit $BUILD_HASH"

echo "== 2. apply patch"
git -C "$SRC" apply --verbose "$HERE/gitlab-sso-team-edition.patch"

GO_VERSION="$(awk '$1=="go"{print $2; exit}' "$SRC/server/go.mod")"
GO_IMAGE="golang:${GO_VERSION}-bookworm"
echo "== 3. go.mod wants go ${GO_VERSION}; building in ${GO_IMAGE}"
echo "   (bookworm = Debian 12, the same glibc as the distroless base)"

BUILD_DATE="$(date -u)"
LDFLAGS="-X 'github.com/mattermost/mattermost/server/public/model.BuildNumber=${BUILD_NUMBER}'"
LDFLAGS+=" -X 'github.com/mattermost/mattermost/server/public/model.BuildDate=${BUILD_DATE}'"
LDFLAGS+=" -X 'github.com/mattermost/mattermost/server/public/model.BuildHash=${BUILD_HASH}'"
LDFLAGS+=" -X 'github.com/mattermost/mattermost/server/public/model.BuildHashEnterprise=none'"
LDFLAGS+=" -X 'github.com/mattermost/mattermost/server/public/model.BuildEnterpriseReady=false'"
# Tags: "production" only, as server/build/release.mk uses. Never
# "enterprise" or "sourceavailable" (see README).
BUILD_TAGS="production"

docker run --rm \
  --platform linux/amd64 \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -e GOCACHE=/cache/build \
  -e GOMODCACHE=/cache/mod \
  -e GOFLAGS=-buildvcs=false \
  -e GOTOOLCHAIN=local \
  -e CGO_ENABLED=1 \
  -e GOOS=linux -e GOARCH=amd64 \
  -e LDFLAGS="$LDFLAGS" \
  -e BUILD_TAGS="$BUILD_TAGS" \
  -v "$SRC:/src" \
  -v "$CACHE:/cache" \
  -v "$OUT:/out" \
  -w /src/server \
  "$GO_IMAGE" \
  bash -euc '
    go version
    rm -f go.work go.work.sum
    go work init
    go work use . ./public
    go build -trimpath -tags "$BUILD_TAGS" -ldflags "$LDFLAGS" -o /out/mattermost ./cmd/mattermost
    echo "-- build tags in binary:"
    go version -m /out/mattermost | grep -E "^\s+build\s+(-tags|CGO_ENABLED|GOOS|GOARCH)"
  '

echo "== 4. binary"
file "$OUT/mattermost"
if go_tags="$(strings "$OUT/mattermost" | grep -E '^build\s+-tags=' | head -1)"; then echo "   $go_tags"; fi
if echo "${go_tags:-}" | grep -Eq 'enterprise|sourceavailable'; then
  echo "binary was built with a source-available tag; refusing" >&2; exit 1
fi

echo "== 5. image $TARGET_IMAGE FROM $BASE_IMAGE"
cp "$HERE/Dockerfile" "$OUT/Dockerfile"
docker build --platform linux/amd64 \
  --build-arg "BASE_IMAGE=$BASE_IMAGE" \
  -t "$TARGET_IMAGE" "$OUT"
docker run --rm "$TARGET_IMAGE" /mattermost/bin/mattermost version
docker image ls "$TARGET_IMAGE"
echo "done: $TARGET_IMAGE (source kept at $SRC)"
