#!/bin/bash
#
# Complete Deployment Script
# Supports both QE Config Server and Manual IP input
#
# Usage: ./deploy.sh [options]
#

set -e

# Default values
# QE Config Server options
CONFIG_SERVER="172.23.105.178"
CONFIG_PORT="8093"
CONFIG_USER="Administrator"
CONFIG_PASS="${CONFIG_PASSWORD:-}"
BUCKET="QE-server-pool"
SCOPE="_default"
COLLECTION="system_longevity_machines"
CB_POOL_ID=""
WITH_SGW=false

# Manual IP options
CB_HOSTS=""
CB_HOSTS_FILE=""
SGW_HOSTS=""
SGW_HOSTS_FILE=""

# Common options
CB_VERSION="7.6.8"
CB_BUILD="7151"
CB_FLAVOR=""  # Will be auto-computed from version if not specified
CB_INSTALL_URL=""
SGW_VERSION="3.3.0"
SGW_BUILD="271"
SGW_INSTALL_URL=""
WITH_SGW=false
SKIP_UNINSTALL=false
DRY_RUN=false
HOSTS_FILE="ansible/hosts"
CB_GROUP_NAME="couchbase_servers"
SGW_GROUP_NAME="sync_gateways"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Help function
show_help() {
    cat << EOF
Complete Deployment Script

Usage: $0 [OPTIONS]

INPUT OPTIONS (Choose one):
  QE Config Server (Fetch IPs from pool):
    --cb-pool-id ID                 Pool ID (e.g., longevity_cluster_2)
    --with-sgw true|false           Also deploy SGW (fetches hosts tagged with "sgw", default: false)
    --config-server IP              QE Config server (default: 172.23.105.178)
    --config-port PORT              Query port (default: 8093)
    --config-user USERNAME          Username (default: Administrator)
    --config-pass PASSWORD          Password (or set CONFIG_PASSWORD env var)
    --bucket NAME                   Bucket (default: QE-server-pool)
    --scope NAME                    Scope (default: _default)
    --collection NAME               Collection (default: system_longevity_machines)
  
  Manual IPs:
    --cb-hosts "IP1 IP2"            Space-separated CB IPs
    --cb-hosts-file FILE            File with CB IPs (one per line)
    --sgw-hosts "IP1 IP2"           Space-separated SGW IPs
    --sgw-hosts-file FILE           File with SGW IPs (one per line)

VERSION OPTIONS:
    --cb-version VERSION            CB Server version (default: 7.6.8)
    --cb-build BUILD                CB Server build (default: 7151)
    --cb-flavor FLAVOR              CB Server flavor (auto-detected from version, can override)
    --cb-install-url URL            Custom CB install URL (overrides version/build/flavor)
    
    --with-sgw true|false           Also install Sync Gateway on hosts tagged with 'sgw' (default: false)
    --sgw-version VERSION           SGW version (default: 3.3.0)
    --sgw-build BUILD               SGW build (default: 271)
    --sgw-install-url URL           Custom SGW install URL (overrides version/build)

BEHAVIOR OPTIONS:
    --skip-uninstall                Skip uninstall step
    --dry-run                       Fetch IPs and generate hosts but don't install
    --hosts-file PATH               Custom hosts file path (default: ansible/hosts)
    --cb-group-name NAME            CB group name (default: couchbase_servers)
    --sgw-group-name NAME           SGW group name (default: sync_gateways)
    
    -h, --help                      Show this help message

EXAMPLES:
    # CB only (excludes hosts tagged with "sgw")
    CONFIG_PASSWORD="pass" $0 --cb-pool-id longevity_cluster_2
    
    # CB + SGW (also deploys to hosts tagged with "sgw")
    CONFIG_PASSWORD="pass" $0 --cb-pool-id longevity_cluster_2 --with-sgw true
    
    # With custom versions
    CONFIG_PASSWORD="pass" $0 --cb-pool-id longevity_cluster_2 --with-sgw true \
      --cb-version 7.6.8 --cb-build 7151
    
    # From Manual IPs
    $0 --cb-hosts "172.23.105.1 172.23.105.2"

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        # QE Config Server options
        --config-server) CONFIG_SERVER="$2"; shift 2 ;;
        --config-port) CONFIG_PORT="$2"; shift 2 ;;
        --config-user) CONFIG_USER="$2"; shift 2 ;;
        --config-pass) CONFIG_PASS="$2"; shift 2 ;;
        --bucket) BUCKET="$2"; shift 2 ;;
        --scope) SCOPE="$2"; shift 2 ;;
        --collection) COLLECTION="$2"; shift 2 ;;
        --cb-pool-id) CB_POOL_ID="$2"; shift 2 ;;
        --with-sgw) WITH_SGW="$2"; shift 2 ;;
        # Manual IP options
        --cb-hosts) CB_HOSTS="$2"; shift 2 ;;
        --cb-hosts-file) CB_HOSTS_FILE="$2"; shift 2 ;;
        --sgw-hosts) SGW_HOSTS="$2"; shift 2 ;;
        --sgw-hosts-file) SGW_HOSTS_FILE="$2"; shift 2 ;;
        # Common options
        --cb-version) CB_VERSION="$2"; shift 2 ;;
        --cb-build) CB_BUILD="$2"; shift 2 ;;
        --cb-flavor) CB_FLAVOR="$2"; shift 2 ;;
        --cb-install-url) CB_INSTALL_URL="$2"; shift 2 ;;
        --sgw-version) SGW_VERSION="$2"; shift 2 ;;
        --sgw-build) SGW_BUILD="$2"; shift 2 ;;
        --sgw-install-url) SGW_INSTALL_URL="$2"; shift 2 ;;
        --skip-uninstall) SKIP_UNINSTALL=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --hosts-file) HOSTS_FILE="$2"; shift 2 ;;
        --cb-group-name) CB_GROUP_NAME="$2"; shift 2 ;;
        --sgw-group-name) SGW_GROUP_NAME="$2"; shift 2 ;;
        -h|--help) show_help ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Auto-compute CB_FLAVOR from CB_VERSION if not explicitly set
if [[ -z "$CB_FLAVOR" ]]; then
    # Default flavor
    CB_FLAVOR="sherlock"
    
    # Determine flavor based on version
    if echo "$CB_VERSION" | grep -q "^6\.5"; then
        CB_FLAVOR="mad-hatter"
    elif echo "$CB_VERSION" | grep -q "^6\.6"; then
        CB_FLAVOR="mad-hatter"
    elif echo "$CB_VERSION" | grep -q "^7\.0"; then
        CB_FLAVOR="cheshire-cat"
    elif echo "$CB_VERSION" | grep -q "^7\.1"; then
        CB_FLAVOR="neo"
    elif echo "$CB_VERSION" | grep -q "^7\.2"; then
        CB_FLAVOR="neo"
    elif echo "$CB_VERSION" | grep -q "^7\.5"; then
        CB_FLAVOR="elixir"
    elif echo "$CB_VERSION" | grep -q "^7\.6"; then
        CB_FLAVOR="trinity"
    elif echo "$CB_VERSION" | grep -q "^7\.7"; then
        CB_FLAVOR="cypher"
    elif echo "$CB_VERSION" | grep -q "^8\.0"; then
        CB_FLAVOR="morpheus"
    elif echo "$CB_VERSION" | grep -q "^8\.1"; then
        CB_FLAVOR="totoro"
    fi
    
    echo -e "${GREEN}Auto-detected CB_FLAVOR: $CB_FLAVOR (from version $CB_VERSION)${NC}"
fi

# Validate input method
USE_QE_CONFIG=false
USE_MANUAL_IPS=false

if [[ -n "$CB_POOL_ID" ]]; then
    USE_QE_CONFIG=true
fi

if [[ -n "$CB_HOSTS" || -n "$CB_HOSTS_FILE" ]]; then
    USE_MANUAL_IPS=true
fi

if [[ "$USE_QE_CONFIG" == false && "$USE_MANUAL_IPS" == false ]]; then
    echo -e "${RED}Error: Must specify either --cb-pool-id (QE config) or --cb-hosts/--cb-hosts-file (manual)${NC}"
    echo "Use --help for usage information"
    exit 1
fi

if [[ "$USE_QE_CONFIG" == true && "$USE_MANUAL_IPS" == true ]]; then
    echo -e "${RED}Error: Cannot use both QE config and manual IPs${NC}"
    exit 1
fi

# Validate QE config password if using QE config server
if [[ "$USE_QE_CONFIG" == true && -z "$CONFIG_PASS" ]]; then
    echo -e "${RED}Error: Config server password is required when using --cb-pool-id${NC}"
    echo "Provide via --config-pass argument or CONFIG_PASSWORD environment variable"
    echo "Example: CONFIG_PASSWORD=mypass ./deploy.sh --cb-pool-id longevity_cluster_2"
    exit 1
fi


echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Couchbase Deployment${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Determine IP source
if [[ "$USE_QE_CONFIG" == true ]]; then
    echo "Input Method: QE Config Server"
    echo "Config Server: ${CONFIG_SERVER}:${CONFIG_PORT}"
    echo "CB Pool ID: ${CB_POOL_ID}"
    if [[ "$WITH_SGW" == "true" ]]; then
        echo "SGW Mode: Enabled (will fetch hosts tagged with 'sgw')"
    fi
else
    echo "Input Method: Manual IPs"
fi
echo ""

# Step 1: Get CB IPs
if [[ "$USE_QE_CONFIG" == true ]]; then
    # Step 1a: Fetch master node IP first
    echo -e "${YELLOW}Step 1: Fetching master node IP from QE Config Server...${NC}"
    echo ""
    
MASTER_IP=$(./fetch_hosts.sh \
    --config-server "$CONFIG_SERVER" \
    --config-port "$CONFIG_PORT" \
    --config-user "$CONFIG_USER" \
    --config-pass "$CONFIG_PASS" \
    --bucket "$BUCKET" \
    --scope "$SCOPE" \
    --collection "$COLLECTION" \
    --pool-id "$CB_POOL_ID" \
    --query-type master)

    if [[ -z "$MASTER_IP" ]]; then
        echo -e "${YELLOW}Warning: No master node found${NC}"
    else
        echo -e "${GREEN}Found master node: $MASTER_IP${NC}"
    fi
    
    # Step 1b: Fetch remaining CB IPs
    echo ""
    echo -e "${YELLOW}Fetching remaining Couchbase Server IPs...${NC}"
    echo ""

CB_IPS=$(./fetch_hosts.sh \
    --config-server "$CONFIG_SERVER" \
    --config-port "$CONFIG_PORT" \
    --config-user "$CONFIG_USER" \
    --config-pass "$CONFIG_PASS" \
    --bucket "$BUCKET" \
    --scope "$SCOPE" \
    --collection "$COLLECTION" \
    --pool-id "$CB_POOL_ID" \
    --query-type cb)

    if [[ -z "$CB_IPS" ]]; then
        echo -e "${RED}Error: Failed to fetch CB IPs${NC}"
        exit 1
    fi
    
    # Create provider YAML file with CB IPs (master first)
    TEMP_YAML="provider.yaml"
    echo "---" > "$TEMP_YAML"
    echo "" >> "$TEMP_YAML"
    
    # Add master node first if found
    if [[ -n "$MASTER_IP" ]]; then
        echo "$MASTER_IP" >> "$TEMP_YAML"
    fi
    
    # Add remaining CB IPs (excluding master if it was in the list)
    for ip in $CB_IPS; do
        if [[ "$ip" != "$MASTER_IP" ]]; then
            echo "$ip" >> "$TEMP_YAML"
        fi
    done
    echo "" >> "$TEMP_YAML"
    echo -e "${GREEN}Created provider IP list: $TEMP_YAML${NC}"

    # Fetch SGW IPs from QE if specified
    SGW_IPS=""
    if [[ "$WITH_SGW" == "true" ]]; then
        echo ""
        echo -e "${YELLOW}Step 2: Fetching Sync Gateway IPs (hosts tagged with 'sgw')...${NC}"
        echo ""
        
        SGW_IPS=$(./fetch_hosts.sh \
            --config-server "$CONFIG_SERVER" \
            --config-port "$CONFIG_PORT" \
            --config-user "$CONFIG_USER" \
            --config-pass "$CONFIG_PASS" \
            --bucket "$BUCKET" \
            --scope "$SCOPE" \
            --collection "$COLLECTION" \
            --pool-id "$CB_POOL_ID" \
            --query-type sgw)
        
        if [[ -z "$SGW_IPS" ]]; then
            echo -e "${YELLOW}Warning: No SGW IPs found (no hosts tagged with 'sgw' in pool)${NC}"
        else
            # Add SGW IPs to temporary YAML file with syncgateway: prefix
            for ip in $SGW_IPS; do
                echo "syncgateway:$ip" >> "$TEMP_YAML"
            done
            echo -e "${GREEN}Added SGW IPs to $TEMP_YAML${NC}"
        fi
    fi
else
    # Using manual IPs
    echo -e "${YELLOW}Step 1: Using provided IPs...${NC}"
    echo ""
    
    # Get CB IPs from file or command line
    if [[ -n "$CB_HOSTS_FILE" ]]; then
        CB_HOSTS=$(grep -v '^#' "$CB_HOSTS_FILE" | grep -v '^[[:space:]]*$' | tr '\n' ' ')
    fi
    CB_IPS="$CB_HOSTS"
    
    # Get SGW IPs from file or command line
    SGW_IPS=""
    if [[ -n "$SGW_HOSTS_FILE" ]]; then
        SGW_HOSTS=$(grep -v '^#' "$SGW_HOSTS_FILE" | grep -v '^[[:space:]]*$' | tr '\n' ' ')
    fi
    SGW_IPS="$SGW_HOSTS"
    
    if [[ -z "$CB_IPS" ]]; then
        echo -e "${RED}Error: No IPs provided${NC}"
        exit 1
    fi
    
    # Create provider YAML file with manual IPs
    TEMP_YAML="provider.yaml"
    echo "---" > "$TEMP_YAML"
    echo "" >> "$TEMP_YAML"
    for ip in $CB_IPS; do
        echo "$ip" >> "$TEMP_YAML"
    done
    echo "" >> "$TEMP_YAML"
    
    if [[ -n "$SGW_IPS" ]]; then
        for ip in $SGW_IPS; do
            echo "syncgateway:$ip" >> "$TEMP_YAML"
        done
    fi
    
    echo -e "${GREEN}Created provider IP list: $TEMP_YAML${NC}"
fi

# Step 2: Generate hosts file
echo ""
echo -e "${YELLOW}Step 2: Generating hosts file...${NC}"
echo ""

POPULATE_CMD="./populate_hosts.sh --hosts-file $HOSTS_FILE"
POPULATE_CMD="$POPULATE_CMD --cb-hosts \"$CB_IPS\" --cb-group-name $CB_GROUP_NAME"

if [[ -n "$SGW_IPS" ]]; then
    POPULATE_CMD="$POPULATE_CMD --sgw-hosts \"$SGW_IPS\" --sgw-group-name $SGW_GROUP_NAME"
fi

# Pass SSH password if set via environment
if [[ -n "$ANSIBLE_SSH_PASSWORD" ]]; then
    POPULATE_CMD="$POPULATE_CMD --ssh-password \"$ANSIBLE_SSH_PASSWORD\""
    echo -e "${GREEN}✓ SSH password will be added to hosts file${NC}"
else
    echo -e "${YELLOW}⚠ No SSH password provided - ensure SSH keys are set up or add SSH_PASSWORD parameter${NC}"
fi

eval $POPULATE_CMD

if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo -e "${YELLOW}Dry run mode - stopping here${NC}"
    echo ""
    echo "Generated hosts file:"
    cat "$HOSTS_FILE"
    exit 0
fi

# Step 3: Deploy
echo ""
echo -e "${YELLOW}Step 3: Deploying Couchbase...${NC}"
echo ""

INSTALL_CMD="ansible-playbook -i $HOSTS_FILE install.yml"
INSTALL_CMD="$INSTALL_CMD -e \"target_hosts=$CB_GROUP_NAME\""
INSTALL_CMD="$INSTALL_CMD -e \"FLAVOR=$CB_FLAVOR\""
INSTALL_CMD="$INSTALL_CMD -e \"VER=$CB_VERSION\""
INSTALL_CMD="$INSTALL_CMD -e \"BUILD_NO=$CB_BUILD\""

# Add custom install URL if provided
if [[ -n "$CB_INSTALL_URL" ]]; then
    INSTALL_CMD="$INSTALL_CMD -e \"URL=$CB_INSTALL_URL\""
    echo -e "${GREEN}Using custom CB install URL: $CB_INSTALL_URL${NC}"
fi

if [[ -n "$SGW_IPS" ]]; then
    INSTALL_CMD="$INSTALL_CMD -e \"sgw_target_hosts=$SGW_GROUP_NAME\""
    INSTALL_CMD="$INSTALL_CMD -e \"SGW_VER=$SGW_VERSION\""
    INSTALL_CMD="$INSTALL_CMD -e \"SGW_BUILD_NO=$SGW_BUILD\""
    
    # Add custom SGW install URL if provided
    if [[ -n "$SGW_INSTALL_URL" ]]; then
        INSTALL_CMD="$INSTALL_CMD -e \"SGW_URL=$SGW_INSTALL_URL\""
        echo -e "${GREEN}Using custom SGW install URL: $SGW_INSTALL_URL${NC}"
    fi
else
    # Skip SGW play by targeting non-existent host
    INSTALL_CMD="$INSTALL_CMD --limit '$CB_GROUP_NAME'"
fi

if [[ "$SKIP_UNINSTALL" == true ]]; then
    INSTALL_CMD="$INSTALL_CMD -e \"PERFORM_UNINSTALL=false\""
    INSTALL_CMD="$INSTALL_CMD -e \"PERFORM_SGW_UNINSTALL=false\""
fi

echo "Running: $INSTALL_CMD"
echo ""

eval $INSTALL_CMD

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Keep provider.yaml for downstream jobs (don't clean up)
if [[ -f "$TEMP_YAML" ]]; then
    echo -e "${GREEN}Provider file available for downstream jobs: $TEMP_YAML${NC}"
    echo ""
fi

echo "Summary:"
echo "  CB IPs: $CB_IPS"
if [[ -n "$SGW_IPS" ]]; then
    echo "  SGW IPs: $SGW_IPS"
fi
echo "  CB Version: $CB_VERSION-$CB_BUILD ($CB_FLAVOR)"
if [[ -n "$SGW_IPS" ]]; then
    echo "  SGW Version: $SGW_VERSION-$SGW_BUILD"
fi
echo ""

