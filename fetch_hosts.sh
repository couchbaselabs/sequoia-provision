#!/bin/bash
#
# Fetch Host IPs from QE Config Server
# Queries Couchbase QE-server-pool to get IP addresses dynamically
#
# Usage: ./fetch_hosts.sh [options]
#

set -e

# Default values
CONFIG_SERVER="172.23.105.178"
CONFIG_PORT="8093"
CONFIG_USER="Administrator"
CONFIG_PASS="${CONFIG_PASSWORD:-}"  # Read from environment or command line
BUCKET="QE-server-pool"
SCOPE="_default"
COLLECTION="system_longevity_machines"
POOL_ID=""
OUTPUT_FILE=""
OUTPUT_FORMAT="list"  # list or file
QUERY_TYPE="cb"  # cb or sgw

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Help function
show_help() {
    cat << EOF
Fetch Host IPs from QE Config Server

Usage: $0 [OPTIONS]

CONFIG SERVER OPTIONS:
    --config-server IP              QE Config server IP (default: 172.23.105.178)
    --config-port PORT              Query service port (default: 8093)
    --config-user USERNAME          Admin username (default: Administrator)
    --config-pass PASSWORD          Admin password (REQUIRED, or set CONFIG_PASSWORD env var)

QUERY OPTIONS:
    --bucket NAME                   Bucket name (default: QE-server-pool)
    --scope NAME                    Scope name (default: _default)
    --collection NAME               Collection name (default: system_longevity_machines)
    --pool-id ID                    Pool ID to query (REQUIRED)
    --query-type TYPE               Query type: cb or sgw (default: cb)

OUTPUT OPTIONS:
    --output-file FILE              Save IPs to file (one per line)
    --output-format FORMAT          Output format: list or file (default: list)
    
    -h, --help                      Show this help message

EXAMPLES:
    # Get CB hosts from longevity_cluster_2
    $0 --pool-id longevity_cluster_2

    # Get and save to file
    $0 --pool-id longevity_cluster_2 --output-file cb_ips.txt

    # Custom config server
    $0 --config-server 172.23.105.100 \\
       --config-user admin \\
       --config-pass password \\
       --pool-id my_cluster

    # Get SGW hosts
    $0 --pool-id longevity_cluster_2 --query-type sgw

INTEGRATION WITH DEPLOY:
    # Fetch IPs and deploy in one go
    CB_IPS=\$(./fetch_hosts.sh --pool-id longevity_cluster_2)
    ./deploy.sh --cb-hosts "\$CB_IPS" --cb-version 7.6.8 --cb-build 7151

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --config-server) CONFIG_SERVER="$2"; shift 2 ;;
        --config-port) CONFIG_PORT="$2"; shift 2 ;;
        --config-user) CONFIG_USER="$2"; shift 2 ;;
        --config-pass) CONFIG_PASS="$2"; shift 2 ;;
        --bucket) BUCKET="$2"; shift 2 ;;
        --scope) SCOPE="$2"; shift 2 ;;
        --collection) COLLECTION="$2"; shift 2 ;;
        --pool-id) POOL_ID="$2"; shift 2 ;;
        --query-type) QUERY_TYPE="$2"; shift 2 ;;
        --output-file) OUTPUT_FILE="$2"; OUTPUT_FORMAT="file"; shift 2 ;;
        --output-format) OUTPUT_FORMAT="$2"; shift 2 ;;
        -h|--help) show_help ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$POOL_ID" ]]; then
    echo -e "${RED}Error: --pool-id is required${NC}"
    echo "Use --help for usage information"
    exit 1
fi

if [[ -z "$CONFIG_PASS" ]]; then
    echo -e "${RED}Error: --config-pass is required${NC}"
    echo "Provide via --config-pass argument or CONFIG_PASSWORD environment variable"
    echo "Example: CONFIG_PASSWORD=mypass ./fetch_hosts.sh --pool-id longevity_cluster_2"
    exit 1
fi

# Build the N1QL query
if [[ "$QUERY_TYPE" == "sgw" ]]; then
    # Query for Sync Gateway hosts: pool_id AND "sgw" tag
    QUERY="SELECT ipaddr FROM \`${BUCKET}\`.\`${SCOPE}\`.\`${COLLECTION}\` WHERE \"${POOL_ID}\" IN poolId AND \"sgw\" IN poolId"
else
    # Query for Couchbase Server hosts: pool_id but NOT "sgw" tag
    QUERY="SELECT ipaddr FROM \`${BUCKET}\`.\`${SCOPE}\`.\`${COLLECTION}\` WHERE \"${POOL_ID}\" IN poolId AND \"sgw\" NOT IN poolId"
fi

# Build config server URL
CONFIG_URL="http://${CONFIG_SERVER}:${CONFIG_PORT}/query/service"

# Execute query
echo -e "${BLUE}Querying QE Config Server...${NC}" >&2
echo -e "  Server: ${CONFIG_URL}" >&2
echo -e "  Pool ID: ${POOL_ID}" >&2
echo -e "  Query Type: ${QUERY_TYPE}" >&2
echo -e "  Query: ${QUERY}" >&2
echo "" >&2

# Execute with explicit error handling
set +e
RESPONSE=$(curl --silent --location --request POST "$CONFIG_URL" \
    --data-urlencode "statement=${QUERY}" \
    -u "${CONFIG_USER}:${CONFIG_PASS}")
CURL_EXIT=$?
set -e

if [[ $CURL_EXIT -ne 0 ]]; then
    echo -e "${RED}Error: curl command failed (exit code: $CURL_EXIT)${NC}" >&2
    echo "Is the QE config server accessible?" >&2
    exit 1
fi

# Check for errors in response
if echo "$RESPONSE" | grep -q '"status": "errors"'; then
    echo -e "${RED}Error: Query failed${NC}" >&2
    echo "$RESPONSE" | jq '.' >&2
    exit 1
fi

# Extract IP addresses from JSON response
# Response format: {"results":[{"ipaddr":"172.23.105.1"},{"ipaddr":"172.23.105.2"}],...}
IPS=$(echo "$RESPONSE" | jq -r '.results[].ipaddr' 2>/dev/null)

# Check if we got any IPs
if [[ -z "$IPS" ]]; then
    echo -e "${RED}Error: No IP addresses found for pool ID: ${POOL_ID}${NC}" >&2
    echo "Response:" >&2
    echo "$RESPONSE" | jq '.' >&2
    exit 1
fi

# Count IPs
IP_COUNT=$(echo "$IPS" | wc -l | tr -d ' ')
echo -e "${GREEN}✓ Found ${IP_COUNT} IP address(es)${NC}" >&2
echo "" >&2

# Output based on format
if [[ "$OUTPUT_FORMAT" == "file" ]]; then
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$IPS" > "$OUTPUT_FILE"
        echo -e "${GREEN}✓ Saved IPs to: ${OUTPUT_FILE}${NC}" >&2
        echo "" >&2
        echo "IPs:" >&2
        cat "$OUTPUT_FILE" | while read ip; do
            echo -e "  ${ip}" >&2
        done
    else
        echo "$IPS"
    fi
else
    # Output as space-separated list (for command line use)
    echo "$IPS" | tr '\n' ' ' | sed 's/ $//'
fi

