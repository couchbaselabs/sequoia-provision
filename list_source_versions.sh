#!/usr/bin/env bash
# Prints the GA releases of the given release lines as VERSION-BUILD, one per line, oldest first, e.g. 7.6.12-8946.
# Used by Jenkinsfile_upgrade_series to default UPGRADE_SOURCE_VERSIONS to every minor version.
#
# Every plain <major>.<minor>.<patch>/ directory under the releases URL is a GA release (MP / build-number / toy
# directories are skipped). The build number comes from that release's couchbase-server-<ver>-manifest.xml
# (BLD_NUM annotation); a release is listed only if its manifest says the same VERSION and the amd64 enterprise
# .deb (what deploy.sh installs) exists. Skipped releases are reported on stderr.
#
# Usage: list_source_versions.sh [--url http://host/builds/releases] [--lines 7.2,7.6,8.0]
set -u

URL="http://172.23.126.166/builds/releases"
LINES="7.2,7.6,8.0"
while [ $# -gt 0 ]; do
    case "$1" in
        --url) URL="${2%/}"; shift 2 ;;
        --lines) LINES="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

index=$(curl -sSf --connect-timeout 15 --max-time 60 "$URL/") || { echo "cannot read $URL/" >&2; exit 1; }

found=0
for line in ${LINES//,/ }; do
    case "$line" in
        [0-9]*.[0-9]*) ;;
        *) echo "bad release line '$line' (expected e.g. 7.6)" >&2; exit 2 ;;
    esac
    pattern="^${line//./\\.}\\.[0-9]+\$"
    versions=$(printf '%s\n' "$index" | grep -oE 'href="[0-9]+\.[0-9]+\.[0-9]+/"' | sed -e 's/href="//' -e 's/\/"$//' \
               | grep -E "$pattern" | sort -t. -k1,1n -k2,2n -k3,3n)
    for version in $versions; do
        manifest=$(curl -sSf --connect-timeout 15 --max-time 60 "$URL/$version/couchbase-server-$version-manifest.xml") || {
            echo "skip $version: manifest not readable" >&2; continue; }
        manifest_version=$(printf '%s\n' "$manifest" | sed -n 's/.*name="VERSION" value="\([^"]*\)".*/\1/p' | head -1)
        build=$(printf '%s\n' "$manifest" | sed -n 's/.*name="BLD_NUM" value="\([0-9]*\)".*/\1/p' | head -1)
        if [ "$manifest_version" != "$version" ] || [ -z "$build" ]; then
            echo "skip $version: manifest has VERSION='$manifest_version' BLD_NUM='$build'" >&2; continue
        fi
        if ! curl -sSfI --connect-timeout 15 --max-time 60 -o /dev/null \
             "$URL/$version/couchbase-server-enterprise_${version}-linux_amd64.deb"; then
            echo "skip $version: no amd64 enterprise .deb" >&2; continue
        fi
        echo "$version-$build"
        found=$((found + 1))
    done
done

if [ "$found" -eq 0 ]; then
    echo "no releases found for lines: $LINES" >&2
    exit 1
fi
