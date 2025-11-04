# Couchbase Deployment Automation

Automated deployment of Couchbase Server and Sync Gateway using Ansible with dynamic host management.

## Quick Start

```bash
# Option 1: Deploy CB from QE Config Server (CB only, excludes SGW hosts)
CONFIG_PASSWORD="your_pass" ./deploy.sh --cb-pool-id longevity_cluster_2

# Option 2: Deploy CB + SGW from QE Config Server (includes hosts tagged with "sgw")
CONFIG_PASSWORD="your_pass" ./deploy.sh --cb-pool-id longevity_cluster_2 --with-sgw true

# Option 3: Deploy from Manual IPs
./deploy.sh --cb-hosts "172.23.105.1 172.23.105.2 172.23.105.3"

# Option 4: Deploy from IP file
./deploy.sh --cb-hosts-file /tmp/cb_ips.txt
```

## How It Works

The deployment follows a simple 3-step flow:

```
Step 1: Get IPs           Step 2: Generate        Step 3: Deploy
┌─────────────────┐       ┌───────────────┐       ┌────────────────┐
│ QE Config Server│       │ populate_hosts│       │   install.yml  │
│      OR         │  -->  │   (ansible/   │  -->  │   (Ansible     │
│  Manual IPs     │       │    hosts)     │       │   Playbook)    │
└─────────────────┘       └───────────────┘       └────────────────┘
```

### Step 1: Get IPs

**From QE Config Server:**
- Queries: `QE-server-pool` bucket for pool IDs
- Fetches IP addresses dynamically based on tags:
  - **Master Node**: Hosts with `master_node=true` (fetched first)
  - **CB Hosts**: Hosts in pool without "sgw" tag
  - **SGW Hosts**: Hosts in pool with "sgw" tag (only if `--with-sgw true`)
- Requires: `CONFIG_PASSWORD` environment variable
- Generates: `provider.yaml` file with ordered IPs (master first)

**From Manual Input:**
- Command line: `--cb-hosts "IP1 IP2 IP3"`
- File: `--cb-hosts-file /path/to/ips.txt`
- No password required
- Generates: `provider.yaml` file for downstream jobs

### Step 2: Generate Hosts File

The `populate_hosts.sh` script creates `ansible/hosts`:

```ini
[couchbase_servers]
172.23.105.1
172.23.105.2
172.23.105.3

[sync_gateways]
172.23.105.234

[all:vars]
ansible_connection=ssh
ansible_ssh_user=root
```

### Step 3: Deploy

Runs Ansible playbooks:
- `install.yml` - Installs Couchbase Server + optional Sync Gateway
- Handles uninstall, download, installation, and verification

## Usage Examples

### Basic Deployment

```bash
# From QE pool
CONFIG_PASSWORD="pass" ./deploy.sh --cb-pool-id longevity_cluster_2

# From IPs
./deploy.sh --cb-hosts "172.23.105.1 172.23.105.2"

# With specific version
./deploy.sh --cb-pool-id longevity_cluster_2 \
  --cb-version 7.6.8 --cb-build 7151
```

### With Sync Gateway

```bash
# From QE pool (deploys CB + hosts tagged with "sgw")
CONFIG_PASSWORD="pass" ./deploy.sh \
  --cb-pool-id longevity_cluster_2 \
  --with-sgw true

# From manual IPs (separate CB and SGW hosts)
./deploy.sh \
  --cb-hosts "172.23.105.1 172.23.105.2" \
  --sgw-hosts "172.23.105.234"

# With custom versions
CONFIG_PASSWORD="pass" ./deploy.sh \
  --cb-pool-id longevity_cluster_2 \
  --with-sgw true \
  --cb-version 7.6.8 --cb-build 7151 \
  --sgw-version 3.3.0 --sgw-build 271
```

### Advanced Options

```bash
# Dry run (test without deploying)
./deploy.sh --cb-pool-id longevity_cluster_2 --dry-run

# Skip uninstall step
./deploy.sh --cb-hosts "172.23.105.1" --skip-uninstall

# Custom versions
./deploy.sh --cb-pool-id longevity_cluster_2 \
  --cb-version 7.6.8 --cb-build 7151 \
  --sgw-version 3.3.0 --sgw-build 271
```

## Command Reference

### deploy.sh

Main deployment script supporting both QE config server and manual IPs.

```bash
./deploy.sh [OPTIONS]
```

**Input Methods (Choose One):**

| Option | Description |
|--------|-------------|
| `--cb-pool-id ID` | Fetch CB IPs from QE pool (requires CONFIG_PASSWORD) |
| `--with-sgw true/false` | Also deploy to hosts tagged with "sgw" in pool (default: false) |
| `--cb-hosts "IP IP"` | Provide CB IPs directly (space-separated) |
| `--cb-hosts-file FILE` | Read CB IPs from file (one per line) |
| `--sgw-hosts "IP IP"` | Provide SGW IPs directly (space-separated) |
| `--sgw-hosts-file FILE` | Read SGW IPs from file (one per line) |

**Version Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--cb-version VERSION` | 7.6.8 | Couchbase Server version |
| `--cb-build BUILD` | 7151 | Build number |
| `--cb-flavor FLAVOR` | trinity | Release codename (auto-detected from version) |
| `--cb-install-url URL` | *(auto)* | Custom CB install URL (overrides version/build/flavor) |
| `--sgw-version VERSION` | 3.3.0 | Sync Gateway version |
| `--sgw-build BUILD` | 271 | SGW build number |
| `--sgw-install-url URL` | *(auto)* | Custom SGW install URL (overrides version/build) |

**Other Options:**

| Option | Description |
|--------|-------------|
| `--skip-uninstall` | Don't uninstall existing installations |
| `--dry-run` | Generate hosts file only, don't deploy |
| `--hosts-file PATH` | Custom hosts file location (default: ansible/hosts) |
| `--cb-group-name NAME` | Custom Ansible group name for CB hosts (default: couchbase_servers) |
| `--sgw-group-name NAME` | Custom Ansible group name for SGW hosts (default: sync_gateways) |

### fetch_hosts.sh

Fetch IPs from QE config server (used internally by deploy.sh).

```bash
# Fetch CB hosts (excludes "sgw" tagged hosts)
CONFIG_PASSWORD="pass" ./fetch_hosts.sh --pool-id longevity_cluster_2

# Fetch master node
CONFIG_PASSWORD="pass" ./fetch_hosts.sh --pool-id longevity_cluster_2 --query-type master

# Fetch SGW hosts (only "sgw" tagged hosts)
CONFIG_PASSWORD="pass" ./fetch_hosts.sh --pool-id longevity_cluster_2 --query-type sgw
```

### populate_hosts.sh

Generate ansible hosts file from IP lists (used internally by deploy.sh).

```bash
./populate_hosts.sh --cb-hosts "172.23.105.1 172.23.105.2"
```

## Configuration

### QE Config Server

Default configuration for querying the pool management system:

| Setting | Default Value | Override |
|---------|--------------|----------|
| Server | 172.23.105.178 | `--config-server` |
| Port | 8093 | `--config-port` |
| Username | Administrator | `--config-user` |
| Password | *(required)* | `--config-pass` or `CONFIG_PASSWORD` env var |
| Bucket | QE-server-pool | `--bucket` |
| Scope | _default | `--scope` |
| Collection | system_longevity_machines | `--collection` |

### Version Mappings

Automatic flavor detection based on version:

| Version | Flavor | Notes |
|---------|--------|-------|
| 6.5.x, 6.6.x | mad-hatter | |
| 7.0.x | cheshire-cat | |
| 7.1.x, 7.2.x | neo | |
| 7.5.x | elixir | |
| 7.6.x | trinity | Default |
| 7.7.x | cypher | |
| 8.0.x | morpheus | |
| 8.1.x | totoro | |

## Security

### Passwords

**Never hardcoded.** Provide passwords securely:

```bash
# Environment variable (recommended)
export CONFIG_PASSWORD="your_password"
./deploy.sh --cb-pool-id longevity_cluster_2

# Command line argument
./deploy.sh --cb-pool-id longevity_cluster_2 --config-pass "your_password"

# Jenkins with credentials
withCredentials([string(credentialsId: 'qe-config-pass', variable: 'CONFIG_PASSWORD')]) {
    sh './deploy.sh --cb-pool-id longevity_cluster_2'
}
```

### Ansible SSH

**Option 1: SSH Keys (Recommended)**

```bash
# Set up SSH keys
ssh-copy-id root@172.23.105.1

# Ansible will use keys automatically
./deploy.sh --cb-hosts "172.23.105.1"
```

**Option 2: SSH Password (via Environment Variable)**

```bash
# Set SSH password for Ansible
export ANSIBLE_SSH_PASSWORD="your_ssh_password"
./deploy.sh --cb-hosts "172.23.105.1"
```

**Option 3: Interactive Password Prompt**

```bash
ansible-playbook -i ansible/hosts install.yml \
  -e "target_hosts=couchbase_servers" --ask-pass
```

## CI/CD Integration

### Jenkins Pipeline

**Option 1: Using QE Config Server**

```groovy
pipeline {
    agent any
    
    parameters {
        string(name: 'CB_POOL_ID', description: 'CB Pool ID from QE config')
        booleanParam(name: 'WITH_SGW', defaultValue: false, 
                     description: 'Also deploy to hosts tagged with "sgw"')
        string(name: 'CB_VERSION', defaultValue: '7.6.8', description: 'Couchbase version')
        string(name: 'CB_BUILD', defaultValue: '7151', description: 'Build number')
        string(name: 'SGW_VERSION', defaultValue: '3.3.0', description: 'Sync Gateway version')
        string(name: 'SGW_BUILD', defaultValue: '271', description: 'SGW build number')
        password(name: 'CONFIG_PASSWORD', description: 'QE Config Server Password')
    }
    
    stages {
        stage('Deploy') {
            steps {
                dir('/root/sequoia-provision') {
                    sh '''
                        export CONFIG_PASSWORD="${CONFIG_PASSWORD}"
                        
                        CMD="./deploy.sh --cb-pool-id ${CB_POOL_ID}"
                        CMD="${CMD} --cb-version ${CB_VERSION} --cb-build ${CB_BUILD}"
                        
                        if [ "${WITH_SGW}" = "true" ]; then
                            CMD="${CMD} --with-sgw true"
                            CMD="${CMD} --sgw-version ${SGW_VERSION} --sgw-build ${SGW_BUILD}"
                        fi
                        
                        eval $CMD
                    '''
                }
            }
        }
    }
    
    post {
        success {
            echo "Deployment successful!"
        }
        failure {
            echo "Deployment failed!"
        }
    }
}
```

**Option 2: Using Pre-configured Hosts (Static ansible/hosts)**

```groovy
pipeline {
    agent any
    
    parameters {
        choice(name: 'TARGET_HOSTS', 
               choices: ['centos2', 'centos3', 'component1', 'component2'],
               description: 'Target host group from ansible/hosts')
        string(name: 'CB_VERSION', defaultValue: '7.6.8')
        string(name: 'CB_BUILD', defaultValue: '7151')
        booleanParam(name: 'SKIP_UNINSTALL', defaultValue: false, 
                     description: 'Skip uninstall step')
    }
    
    stages {
        stage('Uninstall') {
            when {
                expression { !params.SKIP_UNINSTALL }
            }
            steps {
                dir('/root/sequoia-provision') {
                    sh """
                        ansible-playbook -i ansible/hosts uninstall.yml \
                          -e "target_hosts=${params.TARGET_HOSTS}"
                        sleep 15
                    """
                }
            }
        }
        
        stage('Install') {
            steps {
                dir('/root/sequoia-provision') {
                    sh """
                        ansible-playbook -i ansible/hosts install.yml \
                          -e "target_hosts=${params.TARGET_HOSTS}" \
                          -e "VER=${params.CB_VERSION}" \
                          -e "BUILD_NO=${params.CB_BUILD}"
                    """
                }
            }
        }
    }
}
```

**Jenkins Credentials Setup:**

1. Go to Jenkins → Manage Jenkins → Credentials
2. Add **Secret text**: `qe-config-password`
3. Reference in Jenkinsfile:
   ```groovy
   withCredentials([string(credentialsId: 'qe-config-password', variable: 'CONFIG_PASSWORD')]) {
       sh './deploy.sh --cb-pool-id "${CB_POOL_ID}"'
   }
   ```

### GitLab CI

```yaml
deploy_from_qe:
  stage: deploy
  script:
    - cd /root/sequoia-provision
    - export CONFIG_PASSWORD="$QE_CONFIG_PASSWORD"
    - ./deploy.sh --cb-pool-id longevity_cluster_2 --cb-version 7.6.8
  variables:
    QE_CONFIG_PASSWORD: $QE_CONFIG_PASSWORD  # Set in GitLab CI/CD variables as protected
  only:
    - main

deploy_manual:
  stage: deploy
  script:
    - cd /root/sequoia-provision
    - ./deploy.sh --cb-hosts "172.23.105.1 172.23.105.2"
  only:
    - manual
```

## Project Structure

```
sequoia-provision/
├── deploy.sh                   # ⭐ Main deployment script (single entry point)
├── fetch_hosts.sh             # Fetch IPs from QE config server
├── populate_hosts.sh           # Generate ansible hosts file
│
├── install.yml                # Ansible playbook for CB + SGW (combined)
├── install_sgw.yml            # Standalone SGW playbook
├── uninstall.yml              # Uninstall playbook
├── Jenkinsfile                # Jenkins pipeline example
│
├── ansible/
│   ├── ansible.cfg            # Ansible configuration
│   ├── hosts                  # Generated dynamically (by deploy.sh)
│   └── hosts.template         # Template for reference
│
├── examples/
│   ├── cb_hosts.txt.example   # Example CB IPs file format
│   └── sgw_hosts.txt.example  # Example SGW IPs file format
│
└── provider.yaml              # Auto-generated IP list (created by deploy.sh)
```

**Key Points:**
- `deploy.sh` is the **single entry point** for all deployments
- It internally calls `fetch_hosts.sh` and `populate_hosts.sh` as needed
- Automatically generates `provider.yaml` with ordered IPs (master node first)
- The `provider.yaml` file is kept for downstream jobs/integration

## Troubleshooting

### No IPs Found

**QE Config Server:**
```bash
# Test the query manually
CONFIG_PASSWORD="pass" ./fetch_hosts.sh --pool-id longevity_cluster_2

# Check if pool ID is correct
# Verify config server is accessible: curl http://172.23.105.178:8093
```

**Manual IPs:**
```bash
# Check file format (one IP per line, no comments)
cat your_ips.txt

# Test with explicit IPs
./deploy.sh --cb-hosts "172.23.105.1"
```

### Ansible Connection Failed

```bash
# Test SSH connectivity
ssh root@172.23.105.1

# Test Ansible ping
ansible -i ansible/hosts couchbase_servers -m ping

# Use --ask-pass if no SSH keys
ansible-playbook -i ansible/hosts install.yml \
  -e "target_hosts=couchbase_servers" --ask-pass
```

### Permission Denied

```bash
# Make scripts executable
chmod +x deploy.sh fetch_hosts.sh populate_hosts.sh
```

## Requirements

- **Ansible** installed on control machine
- **SSH access** to target hosts (root user)
- **jq** for JSON parsing (QE config server mode)
- **Target hosts**: Debian/Ubuntu systems
- **Network access** to build server (http://172.23.126.166)

## Features

✅ **Flexible Input** - QE config server or manual IPs  
✅ **No Hardcoded Passwords** - Secure credential handling  
✅ **Dynamic Hosts** - No static configuration files  
✅ **Smart Tagging** - Automatic detection of master node and SGW hosts  
✅ **Debian/Ubuntu** - Optimized for .deb packages  
✅ **Version Control** - Specify any CB/SGW version + custom URLs  
✅ **Dry Run Mode** - Test before deploying  
✅ **CI/CD Ready** - Jenkins/GitLab integration  
✅ **Provider File** - Auto-generated `provider.yaml` for downstream jobs  
✅ **Custom Groups** - Configurable Ansible group names  

## Support

- Couchbase Server: 6.5+ (all modern versions)
- Sync Gateway: 3.3.0+
- OS: Debian/Ubuntu (Debian-based systems)

## License

Internal use - Couchbase Labs
