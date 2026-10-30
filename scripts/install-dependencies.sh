#!/usr/bin/env sh
set -eu

MODE="${1:-build}"

if command -v apk >/dev/null 2>&1; then
  case "${MODE}" in
    lint)
      apk add --no-cache bash dub ldc
      ;;
    build|runtime)
      # ldc delegates final linking to cc; build-base provides gcc/cc on Alpine.
      # gstreamer is loaded dynamically by the generated gtk-d bindings, so the
      # shared libraries are needed to run the test suite.
      apk add --no-cache bash dub ldc build-base gtk+3.0-dev \
        gstreamer-dev gst-plugins-base-dev gst-plugins-bad-dev
      ;;
    *)
      echo "Unknown mode: ${MODE}" >&2
      exit 1
      ;;
  esac
  exit 0
fi

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  case "${MODE}" in
    lint)
      apt-get install -y --no-install-recommends bash dub ldc
      ;;
    build|runtime)
      apt-get install -y --no-install-recommends bash dub ldc libgtk-3-dev \
        libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
        libgstreamer-plugins-bad1.0-dev
      ;;
    *)
      echo "Unknown mode: ${MODE}" >&2
      exit 1
      ;;
  esac
  exit 0
fi

echo "Unsupported distribution/package manager for dependency installation" >&2
exit 1
