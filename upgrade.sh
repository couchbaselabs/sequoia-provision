#!/bin/bash
#
# Upgrade a running Couchbase cluster provisioned by deploy.sh
#
#   online  - rolling swap rebalance: a spare node with the new version is swapped in for one cluster node at
#             a time (same services and server group); the node swapped out is freshly installed with the new
#             version (install.yml) and becomes the next spare, until every node runs the new version.
#             Order follows the recommended path: all KV (data) nodes first, then the remaining query/index nodes
#             one at a time in random order (--swap-seed replays an order). The first provider host (sequoia's
#             master/orchestrator) is swapped out first and its reinstall is swapped back in for the next node with
#             the same services, so it is a cluster member with its original services after the upgrade.
#             Spares come from --spare-hosts or, when it is empty, from the provider hosts that are not cluster
#             members (e.g. the 12th host when a test uses 11), so the provider file stays the same size.
#   offline - stop Couchbase on every node, dpkg -i the new package over the existing one, start (upgrade.yml)
#
# Hosts in the provider file that are not cluster members (sequoia's inactive nodes) are freshly installed with
# the new version too, so a post-upgrade test that rebalances them in does not bring the old version back.
# The provider file is rewritten with the post-upgrade membership (cluster members first, the original first
# host still first) for the next sequoia run; the original is kept as <provider-file>.pre_upgrade.
#
# Usage: ./upgrade.sh --mode online|offline --cb-version VER --cb-build BUILD [options]
#

set -e
set -o pipefail

MODE=""
PROVIDER_FILE="provider.yaml"
SPARE_HOSTS=""
CB_VERSION=""
CB_BUILD=""
CB_FLAVOR=""
CB_INSTALL_URL=""
REST_USER="Administrator"
REST_PASSWORD="${CB_REST_PASSWORD:-password}"
REST_SCHEME="http"
ADD_NODE_SCHEME="https"
REBALANCE_TIMEOUT=14400
HEALTH_TIMEOUT=1800
REINSTALL_INACTIVE=true
DRY_RUN=false
SWAP_SEED=""
HOSTS_FILE="ansible/hosts_upgrade"
GROUP_NAME="upgrade_targets"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

show_help() {
    cat << EOF
Upgrade a running Couchbase cluster (online rolling swap or offline in-place)

Usage: $0 --mode online|offline --cb-version VERSION --cb-build BUILD [OPTIONS]

Required:
    --mode MODE                   online (rolling swap rebalance) or offline (stop + dpkg -i + start)
    --cb-version VERSION          Version to upgrade to, e.g. 8.5.0
    --cb-build BUILD              Build number to upgrade to

Online mode:
    --spare-hosts "IP IP"         Spare node(s) to swap in; installed with the new version first.
                                  Default: the provider hosts that are not cluster members
    --swap-seed N                 Seed for the random query/index swap order (printed every run; reuse to replay)

Options:
    --provider-file FILE          Provider file written by deploy.sh (default: provider.yaml)
    --cb-flavor FLAVOR            Release codename (auto-detected from version)
    --cb-install-url URL          Custom install URL (overrides version/build/flavor)
    --rest-user USER              Cluster admin user (default: Administrator)
    --rest-password PASS          Cluster admin password (default: \$CB_REST_PASSWORD or 'password')
    --rest-scheme http|https      Scheme for REST calls (default: http)
    --add-node-scheme http|https  Scheme used when adding a node (default: https, like sequoia's add_node)
    --rebalance-timeout SECS      Per swap rebalance timeout (default: 14400)
    --health-timeout SECS         Wait for healthy cluster after offline upgrade (default: 1800)
    --skip-inactive               Don't reinstall provider hosts that are not cluster members
    --dry-run                     Print the plan without changing anything

Environment:
    ANSIBLE_SSH_PASSWORD          SSH password for ansible (as deploy.sh)
    AWS_*/AZURE_*/GCP_SERVICE_ACCOUNT_FILE are passed to install.yml for freshly installed nodes (as deploy.sh)

Examples:
    $0 --mode offline --cb-version 8.5.0 --cb-build 1130
    $0 --mode online --cb-version 8.5.0 --cb-build 1130
    $0 --mode online --cb-version 8.5.0 --cb-build 1130 --spare-hosts "172.23.105.50"
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --mode) MODE="$2"; shift 2 ;;
        --provider-file) PROVIDER_FILE="$2"; shift 2 ;;
        --spare-hosts) SPARE_HOSTS="$2"; shift 2 ;;
        --cb-version) CB_VERSION="$2"; shift 2 ;;
        --cb-build) CB_BUILD="$2"; shift 2 ;;
        --cb-flavor) CB_FLAVOR="$2"; shift 2 ;;
        --cb-install-url) CB_INSTALL_URL="$2"; shift 2 ;;
        --rest-user) REST_USER="$2"; shift 2 ;;
        --rest-password) REST_PASSWORD="$2"; shift 2 ;;
        --rest-scheme) REST_SCHEME="$2"; shift 2 ;;
        --add-node-scheme) ADD_NODE_SCHEME="$2"; shift 2 ;;
        --rebalance-timeout) REBALANCE_TIMEOUT="$2"; shift 2 ;;
        --health-timeout) HEALTH_TIMEOUT="$2"; shift 2 ;;
        --skip-inactive) REINSTALL_INACTIVE=false; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --swap-seed) SWAP_SEED="$2"; shift 2 ;;
        -h|--help) show_help ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

die() { echo -e "${RED}Error: $*${NC}" >&2; exit 1; }
log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*"; }

[[ "$MODE" == "online" || "$MODE" == "offline" ]] || die "--mode must be online or offline"
[[ -n "$CB_VERSION" && -n "$CB_BUILD" ]] || [[ -n "$CB_INSTALL_URL" && -n "$CB_VERSION" ]] \
    || die "--cb-version and --cb-build (or --cb-install-url with --cb-version) are required"
[[ -f "$PROVIDER_FILE" ]] || die "Provider file $PROVIDER_FILE not found (run deploy.sh first)"
command -v jq >/dev/null 2>&1 || die "jq is required"
command -v ansible-playbook >/dev/null 2>&1 || die "ansible-playbook is required"

if [[ -z "$CB_FLAVOR" ]]; then
    case "$CB_VERSION" in
        6.5*|6.6*) CB_FLAVOR="mad-hatter" ;;
        7.0*) CB_FLAVOR="cheshire-cat" ;;
        7.1*|7.2*) CB_FLAVOR="neo" ;;
        7.5*) CB_FLAVOR="elixir" ;;
        7.6*) CB_FLAVOR="trinity" ;;
        7.7*) CB_FLAVOR="cypher" ;;
        8.0*) CB_FLAVOR="morpheus" ;;
        8.1*|8.5*) CB_FLAVOR="totoro" ;;
        *) die "Cannot auto-detect flavor for $CB_VERSION, pass --cb-flavor" ;;
    esac
fi

if [[ "$REST_SCHEME" == "https" ]]; then REST_PORT=18091; else REST_PORT=8091; fi

# ---------------------------------------------------------------- REST helpers

rest_get() {
    curl -sS -f -k -u "$REST_USER:$REST_PASSWORD" "$REST_SCHEME://$1:$REST_PORT$2"
}

# rest_post HOST PATH [curl -d args...]; fails with the response body on non-2xx
rest_post() {
    local host=$1 path=$2 out code
    shift 2
    out=$(curl -sS -k -u "$REST_USER:$REST_PASSWORD" -w '\n%{http_code}' -X POST "$REST_SCHEME://$host:$REST_PORT$path" "$@")
    code=$(tail -n1 <<< "$out")
    if [[ "$code" != 2* ]]; then
        echo -e "${RED}POST $path on $host failed ($code): $(sed '$d' <<< "$out")${NC}" >&2
        return 1
    fi
    sed '$d' <<< "$out"
}

# Active members as TSV: ip  otpNode  services  version  status
cluster_members() {
    rest_get "$1" /pools/default | jq -r '.nodes[] | select(.clusterMembership == "active")
        | [(.hostname | sub(":[0-9]+$"; "")), .otpNode, (.services | join(",")), .version, .status] | @tsv'
}

member_field() {  # member_field ORCH IP COLUMN
    cluster_members "$1" | awk -F'\t' -v ip="$2" -v col="$3" '$1 == ip {print $col}'
}

# Data and index paths a node uses ("<data>\t<index>"), from its own /nodes/self
node_paths() {
    rest_get "$1" /nodes/self | jq -r '[.storage.hdd[0].path, .storage.hdd[0].index_path] | @tsv'
}

# A freshly installed node is uninitialized and would keep the default paths under /opt (root disk); give it the
# same data/index paths as the node it replaces before it joins (what couchbase-cli node-init does)
init_node_paths() {
    local node=$1 data=$2 index=$3
    rest_post "$node" /nodes/self/controller/settings --data-urlencode "path=$data" \
        --data-urlencode "index_path=$index" > /dev/null || die "Setting data/index paths on $node failed"
    local now
    now=$(node_paths "$node")
    [[ "$now" == "$data"$'\t'"$index" ]] || die "$node paths are '$now' after init, expected '$data' / '$index'"
    log "$node data path $data, index path $index"
}

wait_for_rebalance() {
    local orch=$1 deadline=$((SECONDS + REBALANCE_TIMEOUT)) status progress
    while (( SECONDS < deadline )); do
        progress=$(rest_get "$orch" /pools/default/rebalanceProgress) || { sleep 30; continue; }
        status=$(jq -r '.status' <<< "$progress")
        if [[ "$status" == "none" ]]; then
            local err
            err=$(rest_get "$orch" /pools/default/tasks | jq -r '.[] | select(.type == "rebalance") | .errorMessage // empty')
            [[ -z "$err" ]] || die "Rebalance failed: $err"
            return 0
        fi
        log "Rebalance running: $(jq -c '[to_entries[] | select(.value.progress?) | {(.key): ((.value.progress * 100) | floor)}] | add' <<< "$progress" 2>/dev/null)"
        sleep 60
    done
    die "Rebalance did not finish within ${REBALANCE_TIMEOUT}s"
}

wait_for_healthy_cluster() {
    local orch=$1 deadline=$((SECONDS + HEALTH_TIMEOUT)) members bad
    while (( SECONDS < deadline )); do
        if members=$(cluster_members "$orch" 2>/dev/null); then
            bad=$(awk -F'\t' -v v="$CB_VERSION" '$5 != "healthy" || index($4, v) != 1 {print $1" ("$4", "$5")"}' <<< "$members")
            if [[ -z "$bad" ]]; then
                log "${GREEN}All $(wc -l <<< "$members" | tr -d ' ') nodes healthy on $CB_VERSION${NC}"
                return 0
            fi
            log "Waiting for nodes: $(tr '\n' ' ' <<< "$bad")"
        else
            log "Waiting for REST on $orch"
        fi
        sleep 30
    done
    die "Cluster not healthy on $CB_VERSION within ${HEALTH_TIMEOUT}s"
}

# ---------------------------------------------------------------- ansible helpers

run_playbook() {  # run_playbook PLAYBOOK "IP IP" [extra -e args...]
    local playbook=$1 hosts=$2
    shift 2
    ./populate_hosts.sh --hosts-file "$HOSTS_FILE" --cb-hosts "$hosts" --cb-group-name "$GROUP_NAME" \
        --no-backup ${ANSIBLE_SSH_PASSWORD:+--ssh-password "$ANSIBLE_SSH_PASSWORD"} > /dev/null
    local cmd=(ansible-playbook -i "$HOSTS_FILE" "$playbook" --limit "$GROUP_NAME"
               -e "target_hosts=$GROUP_NAME" -e "FLAVOR=$CB_FLAVOR" -e "VER=$CB_VERSION" -e "BUILD_NO=$CB_BUILD")
    [[ -n "$CB_INSTALL_URL" ]] && cmd+=(-e "URL=$CB_INSTALL_URL")
    cmd+=("$@")
    log "Running: ${cmd[*]} on [$hosts]"
    "${cmd[@]}"
}

# Fresh install (wipes the node) - only for spares and nodes already removed from the cluster
fresh_install() {
    local extra=()
    [[ -n "$NFS_SERVER_IP" ]] && extra+=(-e "nfs_server=$NFS_SERVER_IP")  # mount only; no backup-dir cleanup flags
    [[ -n "$AWS_ACCESS_KEY_ID" && -n "$AWS_SECRET_ACCESS_KEY" ]] && \
        extra+=(-e "aws_access_key_id=$AWS_ACCESS_KEY_ID" -e "aws_secret_access_key=$AWS_SECRET_ACCESS_KEY")
    if [[ -n "$AZURE_STORAGE_ACCOUNT" && -n "$AZURE_STORAGE_KEY" ]]; then
        extra+=(-e "azure_storage_account=$AZURE_STORAGE_ACCOUNT" -e "azure_storage_key=$AZURE_STORAGE_KEY")
        [[ -n "$AZURE_STORAGE_ENDPOINT" ]] && extra+=(-e "azure_storage_endpoint=$AZURE_STORAGE_ENDPOINT")
    fi
    [[ -n "$GCP_SERVICE_ACCOUNT_FILE" ]] && extra+=(-e "gcp_service_account_file=$GCP_SERVICE_ACCOUNT_FILE")
    run_playbook install.yml "$*" "${extra[@]}"
}

# ---------------------------------------------------------------- provider file

PROVIDER_CB_HOSTS=()
PROVIDER_OTHER_LINES=()
while IFS= read -r line; do
    line=$(tr -d '[:space:]' <<< "$line")
    [[ -z "$line" || "$line" == "---" ]] && continue
    if [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        PROVIDER_CB_HOSTS+=("$line")
    else
        PROVIDER_OTHER_LINES+=("$line")   # syncgateway:IP, nfs_server:IP
    fi
done < "$PROVIDER_FILE"
NFS_SERVER_IP=$(printf '%s\n' "${PROVIDER_OTHER_LINES[@]}" | sed -n 's/^nfs_server://p' | head -n1)
(( ${#PROVIDER_CB_HOSTS[@]} > 0 )) || die "No Couchbase hosts in $PROVIDER_FILE"

# Find a reachable cluster member to drive REST calls from
ORCH=""
for ip in "${PROVIDER_CB_HOSTS[@]}"; do
    if members=$(cluster_members "$ip" 2>/dev/null) && [[ -n "$members" ]]; then ORCH=$ip; break; fi
done
[[ -n "$ORCH" ]] || die "No provider host answered /pools/default"

# Members in provider order (orchestrator first) followed by any member not in the provider file
MEMBERS=()
for ip in "${PROVIDER_CB_HOSTS[@]}"; do
    awk -F'\t' -v ip="$ip" '$1 == ip {found=1} END {exit !found}' <<< "$members" && MEMBERS+=("$ip")
done
while IFS=$'\t' read -r ip _; do
    [[ " ${MEMBERS[*]} " == *" $ip "* ]] || MEMBERS+=("$ip")
done <<< "$members"
INACTIVE=()
for ip in "${PROVIDER_CB_HOSTS[@]}"; do
    [[ " ${MEMBERS[*]} " == *" $ip "* ]] || INACTIVE+=("$ip")
done
read -r -a SPARES <<< "$SPARE_HOSTS"
for ip in "${SPARES[@]}"; do
    [[ " ${MEMBERS[*]} " == *" $ip "* ]] && die "Spare $ip is already a cluster member"
done
SPARE_SOURCE="--spare-hosts"
if [[ "$MODE" == "online" && ${#SPARES[@]} -eq 0 ]]; then
    # No explicit spares: use the provider hosts the test keeps out of the cluster
    SPARES=("${INACTIVE[@]}")
    INACTIVE=()
    SPARE_SOURCE="provider hosts not in the cluster"
    (( ${#SPARES[@]} > 0 )) || die "Online upgrade needs a spare: no provider host is outside the cluster and --spare-hosts is empty"
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Couchbase ${MODE} upgrade -> ${CB_VERSION}-${CB_BUILD} (${CB_FLAVOR})${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Cluster members (version / services):"
awk -F'\t' '{printf "  %-16s %-24s %s\n", $1, $4, $3}' <<< "$members"
echo "Inactive provider hosts: ${INACTIVE[*]:-none}"
[[ "$MODE" == "online" ]] && echo "Spare hosts: ${SPARES[*]} (from ${SPARE_SOURCE})"
echo ""

# Online swap order (recommended upgrade path): every node running kv first, then the query/index nodes one at
# a time in random order. The master (first provider host) goes first: swapped-out nodes are reinstalled and
# become the next spare, so the master is swapped back in for the second node, which must run the same services
# for the master to keep its role.
MASTER=${MEMBERS[0]}
SWAP_ORDER=()
if [[ "$MODE" == "online" ]]; then
    master_svc=$(awk -F'\t' -v ip="$MASTER" '$1 == ip {print $3}' <<< "$members")
    KV_NODES=()
    OTHER_NODES=()
    for ip in "${MEMBERS[@]:1}"; do
        svc=$(awk -F'\t' -v ip="$ip" '$1 == ip {print $3}' <<< "$members")
        if [[ ",$svc," == *",kv,"* ]]; then KV_NODES+=("$ip"); else OTHER_NODES+=("$ip"); fi
    done
    # the node the master replaces: first other member with the master's services
    partner=""
    for ip in "${KV_NODES[@]}" "${OTHER_NODES[@]}"; do
        [[ "$(awk -F'\t' -v ip="$ip" '$1 == ip {print $3}' <<< "$members")" == "$master_svc" ]] && { partner=$ip; break; }
    done
    if [[ -n "$partner" ]]; then
        rest=()
        for ip in "${KV_NODES[@]}"; do [[ "$ip" != "$partner" ]] && rest+=("$ip"); done
        others=()
        for ip in "${OTHER_NODES[@]}"; do [[ "$ip" != "$partner" ]] && others+=("$ip"); done
        KV_NODES=("$MASTER" "$partner" "${rest[@]}")
        OTHER_NODES=("${others[@]}")
    else
        echo -e "${YELLOW}No other member runs the master's services ($master_svc): $MASTER will come back with other services${NC}"
        KV_NODES=("$MASTER" "${KV_NODES[@]}")
    fi
    [[ -n "$SWAP_SEED" ]] || SWAP_SEED=$RANDOM
    RANDOM=$SWAP_SEED
    for ((i = ${#OTHER_NODES[@]} - 1; i > 0; i--)); do
        j=$((RANDOM % (i + 1)))
        tmp=${OTHER_NODES[$i]}; OTHER_NODES[$i]=${OTHER_NODES[$j]}; OTHER_NODES[$j]=$tmp
    done
    SWAP_ORDER=("${KV_NODES[@]}" "${OTHER_NODES[@]}")
    echo "Swap order (master $MASTER first, then KV, then query/index in random order, --swap-seed $SWAP_SEED):"
    for ip in "${SWAP_ORDER[@]}"; do
        echo "  $ip ($(awk -F'\t' -v ip="$ip" '$1 == ip {print $3}' <<< "$members"))"
    done
    echo ""
fi

if [[ "$DRY_RUN" == true ]]; then
    if [[ "$MODE" == "online" ]]; then
        echo "Plan: install ${CB_VERSION} on spares ${SPARES[*]}, then swap in the order above"
    else
        echo "Plan: stop, dpkg -i, start on ${MEMBERS[*]}"
    fi
    [[ "$REINSTALL_INACTIVE" == true && ${#INACTIVE[@]} -gt 0 ]] && echo "Plan: fresh install ${CB_VERSION} on inactive ${INACTIVE[*]}"
    exit 0
fi

cp "$PROVIDER_FILE" "$PROVIDER_FILE.pre_upgrade"

# ---------------------------------------------------------------- upgrade

FINAL_MEMBERS=()
if [[ "$MODE" == "offline" ]]; then
    run_playbook upgrade.yml "${MEMBERS[*]}"
    wait_for_healthy_cluster "${MEMBERS[0]}"
    FINAL_MEMBERS=("${MEMBERS[@]}")
    LEFTOVER=()
else
    to_install=("${SPARES[@]}")
    [[ "$REINSTALL_INACTIVE" == true ]] && to_install+=("${INACTIVE[@]}")
    log "Installing ${CB_VERSION} on ${to_install[*]}"
    fresh_install "${to_install[@]}"

    FINAL_MEMBERS=("${MEMBERS[@]}")
    step=0
    for old in "${SWAP_ORDER[@]}"; do
        step=$((step + 1))
        new=${SPARES[0]}
        SPARES=("${SPARES[@]:1}")
        # drive REST from a member that stays in the cluster
        orch=""
        for ip in "${FINAL_MEMBERS[@]}"; do [[ "$ip" != "$old" ]] && { orch=$ip; break; }; done
        [[ -n "$orch" ]] || die "Cannot swap the only cluster node"

        services=$(member_field "$orch" "$old" 3)
        old_otp=$(member_field "$orch" "$old" 2)
        [[ -n "$old_otp" ]] || die "$old is not an active member"
        group_uri=$(rest_get "$orch" /pools/default/serverGroups | jq -r --arg ip "$old" \
            '.groups[] | select(any(.nodes[]; (.hostname | sub(":[0-9]+$"; "")) == $ip)) | .addNodeURI')
        [[ -n "$group_uri" ]] || group_uri="/controller/addNode"

        echo -e "${YELLOW}Swap $step/${#SWAP_ORDER[@]}: $old ($services) -> $new${NC}"
        old_paths=$(node_paths "$old") || die "Cannot read data/index paths of $old"
        init_node_paths "$new" "$(cut -f1 <<< "$old_paths")" "$(cut -f2 <<< "$old_paths")"
        if [[ "$ADD_NODE_SCHEME" == "https" ]]; then add_host="https://$new"; else add_host="$new"; fi
        rest_post "$orch" "$group_uri" --data-urlencode "hostname=$add_host" \
            --data-urlencode "user=$REST_USER" --data-urlencode "password=$REST_PASSWORD" \
            --data-urlencode "services=$services" > /dev/null

        known=$(rest_get "$orch" /pools/default | jq -r '[.nodes[].otpNode] | join(",")')
        rest_post "$orch" /controller/rebalance --data-urlencode "knownNodes=$known" \
            --data-urlencode "ejectedNodes=$old_otp" > /dev/null
        sleep 10
        wait_for_rebalance "$orch"

        [[ -z "$(member_field "$orch" "$old" 1)" ]] || die "$old still a member after swap rebalance"
        [[ "$(member_field "$orch" "$new" 3)" == "$services" ]] || die "$new did not come in with services $services"
        log "${GREEN}$new ($(member_field "$orch" "$new" 4)) replaced $old${NC}"
        for i in "${!FINAL_MEMBERS[@]}"; do [[ "${FINAL_MEMBERS[$i]}" == "$old" ]] && FINAL_MEMBERS[$i]=$new; done

        # The removed node is still on the old version: reinstall it as the next spare
        fresh_install "$old"
        SPARES+=("$old")
    done
    # keep the master first in the provider file (sequoia's orchestrator) when it is back in the cluster
    if [[ " ${FINAL_MEMBERS[*]} " == *" $MASTER "* ]]; then
        reordered=("$MASTER")
        for ip in "${FINAL_MEMBERS[@]}"; do [[ "$ip" != "$MASTER" ]] && reordered+=("$ip"); done
        FINAL_MEMBERS=("${reordered[@]}")
    else
        echo -e "${YELLOW}$MASTER is not a cluster member after the upgrade${NC}"
    fi
    wait_for_healthy_cluster "${FINAL_MEMBERS[0]}"
    LEFTOVER=("${SPARES[@]}")
fi

if [[ "$MODE" == "offline" && "$REINSTALL_INACTIVE" == true && ${#INACTIVE[@]} -gt 0 ]]; then
    log "Installing ${CB_VERSION} on inactive provider hosts ${INACTIVE[*]}"
    fresh_install "${INACTIVE[@]}"
fi

# ---------------------------------------------------------------- provider file for the post-upgrade run

{
    echo "---"
    echo ""
    for ip in "${FINAL_MEMBERS[@]}"; do echo "$ip"; done
    if [[ "$MODE" == "offline" ]]; then
        for ip in "${INACTIVE[@]}"; do echo "$ip"; done
    else
        # spare + swapped-out nodes, all on the new version now; inactive hosts were in the spare pool too
        for ip in "${LEFTOVER[@]}" "${INACTIVE[@]}"; do
            [[ " ${FINAL_MEMBERS[*]} " == *" $ip "* ]] || echo "$ip"
        done | awk '!seen[$0]++'
    fi
    echo ""
    for line in "${PROVIDER_OTHER_LINES[@]}"; do echo "$line"; done
} > "$PROVIDER_FILE"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Upgrade Complete (${MODE})${NC}"
echo -e "${GREEN}========================================${NC}"
cluster_members "${FINAL_MEMBERS[0]}" | awk -F'\t' '{printf "  %-16s %-24s %s\n", $1, $4, $3}'
echo "Provider file for the post-upgrade run: $PROVIDER_FILE (previous: $PROVIDER_FILE.pre_upgrade)"
