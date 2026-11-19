# shellcheck shell=bash
# Shared by deploy.sh and upgrade.sh (source this file, then call resolve_cb_install_url).
#
# GA builds are purged from latestbuilds after a while and kept under releases/<version>/ without the build
# number in the file name: when the latestbuilds package is gone, install that one instead.
#
# Reads/sets CB_INSTALL_URL and reads CB_BUILD, CB_FLAVOR, CB_VERSION and the YELLOW/RED/NC colour vars,
# all defined by the sourcing script.
resolve_cb_install_url() {
    [[ -n "$CB_INSTALL_URL" || -z "$CB_BUILD" ]] && return 0
    local builds="http://172.23.126.166/builds"
    local latest="$builds/latestbuilds/couchbase-server/$CB_FLAVOR/$CB_BUILD/couchbase-server-enterprise_${CB_VERSION}-${CB_BUILD}-linux_amd64.deb"
    local release="$builds/releases/$CB_VERSION/couchbase-server-enterprise_${CB_VERSION}-linux_amd64.deb"
    local manifest="$builds/releases/$CB_VERSION/couchbase-server-$CB_VERSION-manifest.xml"
    local code
    code=$(curl -s -o /dev/null -I -m 30 -w '%{http_code}' "$latest" || true)
    [[ "$code" == "404" ]] || return 0

    # latestbuilds is gone. The releases/<version>/ package carries no build number in its name, so the
    # GA build there is not necessarily the one requested: confirm the release manifest's VERSION and
    # BLD_NUM match $CB_VERSION-$CB_BUILD before using it, and fail loudly rather than install a mismatch.
    local xml mver mbld
    xml=$(curl -sSf --connect-timeout 15 --max-time 60 "$manifest" 2>/dev/null || true)
    mver=$(printf '%s\n' "$xml" | sed -n 's/.*name="VERSION" value="\([^"]*\)".*/\1/p' | head -1)
    mbld=$(printf '%s\n' "$xml" | sed -n 's/.*name="BLD_NUM" value="\([0-9]*\)".*/\1/p' | head -1)
    code=$(curl -s -o /dev/null -I -m 30 -w '%{http_code}' "$release" || true)
    if [[ "$code" == "200" && "$mver" == "$CB_VERSION" && "$mbld" == "$CB_BUILD" ]]; then
        CB_INSTALL_URL=$release
        echo -e "${YELLOW}${CB_VERSION}-${CB_BUILD} is no longer in latestbuilds; installing the GA package $release${NC}"
    else
        echo -e "${RED}${CB_VERSION}-${CB_BUILD} is not available as the GA release (manifest VERSION='$mver' BLD_NUM='$mbld', $release: HTTP $code); pass --cb-install-url to override${NC}" >&2
        exit 1
    fi
}
