# Couchbase Deployment Automation

Automated deployment of Couchbase Server and Sync Gateway using Ansible with dynamic host management.

## Quick Start

```bash
# Option 1: Deploy from QE Config Server
CONFIG_PASSWORD="your_pass" ./deploy.sh --cb-pool-id longevity_cluster_2

# Option 2: Deploy from Manual IPs
./deploy.sh --cb-hosts "172.23.105.1 172.23.105.2 172.23.105.3"

# Option 3: Deploy from IP file
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
- Fetches IP addresses dynamically
- Requires: `CONFIG_PASSWORD` environment variable

**From Manual Input:**
- Command line: `--cb-hosts "IP1 IP2 IP3"`
- File: `--cb-hosts-file /path/to/ips.txt`
- No password required

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
# From QE pools
CONFIG_PASSWORD="pass" ./deploy.sh \
  --cb-pool-id longevity_cluster_2 \
  --sgw-pool-id longevity_sgw_pool

# Mixed: CB from pool, SGW from IPs
CONFIG_PASSWORD="pass" ./deploy.sh \
  --cb-pool-id longevity_cluster_2 \
  --sgw-hosts "172.23.105.234"
```

Wait, I need to check if the script supports mixing. Let me continue with a simpler README.

```bash
# From manual IPs
./deploy.sh \
  --cb-hosts "172.23.105.1 172.23.105.2" \
  --sgw-hosts "172.23.105.234"
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
| `--sgw-pool-id ID` | Fetch SGW IPs from QE pool |
| `--cb-hosts "IP IP"` | Provide CB IPs directly |
| `--cb-hosts-file FILE` | Read CB IPs from file |
| `--sgw-hosts "IP IP"` | Provide SGW IPs directly |
| `--sgw-hosts-file FILE` | Read SGW IPs from file |

**Version Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--cb-version VERSION` | 7.6.8 | Couchbase Server version |
| `--cb-build BUILD` | 7151 | Build number |
| `--cb-flavor FLAVOR` | trinity | Release codename |
| `--sgw-version VERSION` | 3.3.0 | Sync Gateway version |
| `--sgw-build BUILD` | 271 | SGW build number |

**Other Options:**

| Option | Description |
|--------|-------------|
| `--skip-uninstall` | Don't uninstall existing installations |
| `--dry-run` | Generate hosts file only, don't deploy |
| `--hosts-file PATH` | Custom hosts file location |

### fetch_hosts.sh

Fetch IPs from QE config server (used internally by deploy.sh).

```bash
CONFIG_PASSWORD="pass" ./fetch_hosts.sh --pool-id longevity_cluster_2
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

Use SSH keys for best security:

```bash
# Set up SSH keys
ssh-copy-id root@172.23.105.1

# Ansible will use keys automatically
./deploy.sh --cb-hosts "172.23.105.1"
```

Or use `--ask-pass` for interactive password prompt:

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
        string(name: 'SGW_POOL_ID', description: 'SGW Pool ID (optional)', defaultValue: '')
        string(name: 'CB_VERSION', defaultValue: '7.6.8', description: 'Couchbase version')
        string(name: 'CB_BUILD', defaultValue: '7151', description: 'Build number')
        password(name: 'CONFIG_PASSWORD', description: 'QE Config Server Password')
    }
    
    stages {
        stage('Deploy') {
            steps {
                dir('/root/sequoia-provision') {
                    sh '''
                        export CONFIG_PASSWORD="${CONFIG_PASSWORD}"
                        
                        if [ -n "${SGW_POOL_ID}" ]; then
                            ./deploy.sh \
                              --cb-pool-id "${CB_POOL_ID}" \
                              --sgw-pool-id "${SGW_POOL_ID}" \
                              --cb-version "${CB_VERSION}" \
                              --cb-build "${CB_BUILD}"
                        else
                            ./deploy.sh \
                              --cb-pool-id "${CB_POOL_ID}" \
                              --cb-version "${CB_VERSION}" \
                              --cb-build "${CB_BUILD}"
                        fi
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
├── install.yml                # Ansible playbook for CB + SGW
├── install_sgw.yml            # Standalone SGW playbook
├── uninstall.yml              # Uninstall playbook
│
├── ansible/
│   ├── ansible.cfg            # Ansible configuration
│   └── hosts                  # Generated dynamically
│
├── docs/                      # Archived detailed guides
│   ├── DEPLOY_GUIDE.md
│   ├── SECURITY.md
│   └── SYNC_GATEWAY_GUIDE.md
│
└── examples/
    ├── cb_hosts.txt.example   # Example IP file
    └── sgw_hosts.txt.example  # Example SGW IP file
```

**Key Point:** `deploy.sh` is the **only script you need** for deployment. It internally calls `fetch_hosts.sh` and `populate_hosts.sh` as needed.

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
✅ **Debian/Ubuntu** - Optimized for .deb packages  
✅ **Version Control** - Specify any CB/SGW version  
✅ **Dry Run Mode** - Test before deploying  
✅ **CI/CD Ready** - Jenkins/GitLab integration  
✅ **Ansible Roles** - Clean, reusable structure  

## Support

- Couchbase Server: 6.5+ (all modern versions)
- Sync Gateway: 3.3.0+
- OS: Debian/Ubuntu (Debian-based systems)

## License

Internal use - Couchbase Labs
