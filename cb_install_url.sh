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
    local code
    code=$(curl -s -o /dev/null -I -m 30 -w '%{http_code}' "$latest" || true)
    if [[ "$code" == "404" ]]; then
        code=$(curl -s -o /dev/null -I -m 30 -w '%{http_code}' "$release" || true)
        if [[ "$code" == "200" ]]; then
            CB_INSTALL_URL=$release
            echo -e "${YELLOW}${CB_VERSION}-${CB_BUILD} is no longer in latestbuilds; installing the GA package $release${NC}"
        else
            echo -e "${RED}${CB_VERSION}-${CB_BUILD} is neither in latestbuilds nor in releases ($release: HTTP $code)${NC}" >&2
            exit 1
        fi
    fi
}
