#!/bin/bash
#
# Simple wrapper script to use unified playbooks
# Usage: ./provision_simple.sh centos2 7.6.8 7151
#

set -e

TARGET_HOSTS="${1:-centos2}"
VERSION="${2:-7.6.8}"
BUILD="${3:-7151}"

# Determine flavor from version
FLAVOR="trinity"
case "${VERSION}" in
    6.5*) FLAVOR="mad-hatter" ;;
    6.6*) FLAVOR="mad-hatter" ;;
    7.0*) FLAVOR="cheshire-cat" ;;
    7.1*) FLAVOR="neo" ;;
    7.2*) FLAVOR="neo" ;;
    7.5*) FLAVOR="elixir" ;;
    7.6*) FLAVOR="trinity" ;;
    7.7*) FLAVOR="cypher" ;;
    8.0*) FLAVOR="morpheus" ;;
esac

echo "=========================================="
echo "Provisioning Couchbase"
echo "=========================================="
echo "Target Hosts: ${TARGET_HOSTS}"
echo "Version: ${VERSION}"
echo "Build: ${BUILD}"
echo "Flavor: ${FLAVOR}"
echo "=========================================="
echo ""

# Uninstall
echo "Running uninstall..."
ansible-playbook -i ansible/hosts uninstall_unified.yml \
  -e "target_hosts=${TARGET_HOSTS}"

sleep 15

# Install
echo ""
echo "Running install..."
ansible-playbook -i ansible/hosts install_unified.yml \
  -e "target_hosts=${TARGET_HOSTS}" \
  -e "FLAVOR=${FLAVOR}" \
  -e "VER=${VERSION}" \
  -e "BUILD_NO=${BUILD}"

echo ""
echo "=========================================="
echo "Complete!"
echo "=========================================="

