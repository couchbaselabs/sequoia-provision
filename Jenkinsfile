pipeline {
    agent none

    parameters {
        choice(name: 'COMPONENT',
               choices: [
                   'component1',
                   'component2',
                   'component3',
                   'component6',
                   'component7',
                   'longevity_cluster_1',
                   'longevity_cluster_2'
               ],
               description: 'Select which component or longevity cluster to deploy and run tests for')

        booleanParam(name: 'SKIP_INSTALL', defaultValue: false, description: 'Skip deploy/install step')
        string(name: 'CB_VERSION', defaultValue: '8.1.0', description: 'Couchbase version')
        string(name: 'CB_BUILD', defaultValue: '1130', description: 'Couchbase build number')
        string(name: 'TEST_FILE', defaultValue: 'tests/2i/7.6/test_7_6_gsi_system_test.yml -scope tests/2i/neo/scope_neo_plasma_idx_dgm.yml', description: 'Test file path')
        string(name: 'SGW_VERSION', defaultValue: '3.2.0', description: 'Sync Gateway version')
        string(name: 'SGW_BUILD', defaultValue: '1234', description: 'Sync Gateway build number')
        string(name: 'CB_INSTALL_URL', defaultValue: '', description: 'Couchbase Server install URL')
        string(name: 'SEQ_PROVISION_BRANCH', defaultValue: 'master', description: 'Branch to checkout for sequoia-provision repo')
        string(name: 'SEQ_REPO_BRANCH', defaultValue: 'master', description: 'Branch to checkout for sequoia repo')
        string(name: 'SEQ_CHERRYPICK', defaultValue: '', description: 'Optional commit hash to cherry-pick in sequoia repo')

        string(name: 'SGW_INSTALL_URL', defaultValue: '', description: 'Sync Gateway install URL')
        booleanParam(name: 'WITH_SGW', defaultValue: false, description: 'Include Sync Gateway')
        
        
        string(name: 'SCALE', defaultValue: '1', description: 'Scale parameter for sequoia')
        string(name: 'REPEAT', defaultValue: '1', description: 'Repeat parameter for sequoia')
        string(name: 'DURATION', defaultValue: '604800', description: 'Test duration in seconds')

        booleanParam(name: 'SHOW_TOPOLOGY', defaultValue: true, description: 'Show test topology')
        booleanParam(name: 'COLLECT_ON_ERROR', defaultValue: false, description: 'Collect data on error')
        booleanParam(name: 'STOP_ON_ERROR', defaultValue: false, description: 'Stop test on error')
        booleanParam(name: 'CONTINUE', defaultValue: false, description: 'Continue after error')
        booleanParam(name: 'SKIP_CLEANUP', defaultValue: false, description: 'Skip cleanup phase')
        booleanParam(name: 'SKIP_TEARDOWN', defaultValue: true, description: 'Skip teardown phase')
        booleanParam(name: 'SKIP_TEST', defaultValue: false, description: 'Skip test execution')
        booleanParam(name: 'SKIP_SETUP', defaultValue: false, description: 'Skip setup phase')

        string(name: 'LOG_LEVEL', defaultValue: '0', description: 'Logging level (0–5)')

        // Git customization parameters
    }

    stages {
        stage('Select Target VM') {
            steps {
                script {
                    def config = [
                        component1: [vm: 'component-systest-client-1', ip: '172.23.106.226'],
                        component2: [vm: 'component-systest-client-2', ip: '172.23.104.168'],
                        component3: [vm: 'component-systest-client-3', ip: '172.23.216.124'],
                        component6: [vm: 'component-systest-client-6', ip: '172.23.216.126'],
                        component7: [vm: 'component-systest-client-7', ip: '172.23.216.125'],
                        longevity_cluster_1: [vm: 'longevity-systest-client-1', ip: '172.23.105.35'],
                        longevity_cluster_2: [vm: 'longevity-systest-client-2', ip: '172.23.216.117']
                    ]

                    env.VM_NAME = config[params.COMPONENT]?.vm
                    env.SLAVE_IP = config[params.COMPONENT]?.ip

                    if (!env.VM_NAME || !env.SLAVE_IP) {
                        error "Unknown component: ${params.COMPONENT}"
                    }

                    echo ">>> Selected component: ${params.COMPONENT}"
                    echo ">>> Target VM: ${env.VM_NAME}"
                    echo ">>> Slave IP: ${env.SLAVE_IP}"
                    currentBuild.description = "Component: ${params.COMPONENT} | VM: ${env.VM_NAME} | IP: ${env.SLAVE_IP}"

                }
            }
        }

        stage('Checkout Repositories') {
            agent { label "${env.VM_NAME}" }
            steps {
                script {
                    dir('/root/sequoia-provision') {
                        sh """
                            if [ ! -d .git ]; then
                                git clone https://github.com/couchbaselabs/sequoia-provision.git .
                            fi
                            git fetch origin
                            git checkout -B ${params.SEQ_PROVISION_BRANCH} origin/${params.SEQ_PROVISION_BRANCH}
                        """
                    }

                    dir('/opt/godev/src/github.com/couchbaselabs/sequoia') {
                        sh """
                            if [ ! -d .git ]; then
                                git clone https://github.com/couchbaselabs/sequoia.git .
                            fi
                            git fetch origin
                            git checkout -B ${params.SEQ_REPO_BRANCH} origin/${params.SEQ_REPO_BRANCH}
                        """

                        if (params.SEQ_CHERRYPICK?.trim()) {
                            sh """
                                git fetch origin
                                git cherry-pick ${params.SEQ_CHERRYPICK} || echo "Cherry-pick failed or conflicts found"
                            """
                        }

                        sh '''
                            export GOROOT=/usr/local/go
                            export GOPATH=/opt/godev
                            export PATH=$PATH:/usr/local/go/bin
                            export PROJECT=couchbaselabs
                            export GO111MODULE=on
                            cd /opt/godev/src/github.com/couchbaselabs/sequoia
                            go version
                            
                            # Verify go.mod exists (should be in repository)
                            if [ ! -f go.mod ]; then
                                echo "ERROR: go.mod not found in repository. Please ensure the branch has go.mod checked in."
                                exit 1
                            fi
                            
                            # Downgrade to compatible versions that work with Go 1.21
                            go get github.com/fsouza/go-dockerclient@v1.9.0
                            go get github.com/docker/docker@v20.10.24+incompatible
                            
                            go mod tidy
                            go build -o sequoia
                        '''
                    }
                }
            }
        }

        stage('Deploy and Run Tests') {
            agent { label "${env.VM_NAME}" }
            steps {
                script {
                    echo ">>> SKIP_INSTALL parameter value: ${params.SKIP_INSTALL}"
                    
                    withCredentials([
                        usernamePassword(credentialsId: 'root', usernameVariable: 'SSH_USERNAME', passwordVariable: 'SSH_PASSWORD'),
                        usernamePassword(credentialsId: 'qe_db_cluster', usernameVariable: 'CONFIG_USERNAME', passwordVariable: 'CONFIG_PASSWORD')
                    ]) {
                        if (!params.SKIP_INSTALL) {
                            echo ">>> Starting Couchbase deployment..."
                            dir('/root/sequoia-provision') {
                                sh """
                                    export CONFIG_PASSWORD='${CONFIG_PASSWORD}'
                                    export SSH_PASSWORD='${SSH_PASSWORD}'
                                    export ANSIBLE_SSH_PASSWORD="$SSH_PASSWORD"
                                    ./deploy.sh \
                                        --cb-pool-id ${params.COMPONENT} \
                                        --cb-version ${params.CB_VERSION} \
                                        --cb-build ${params.CB_BUILD} \
                                        --sgw-version ${params.SGW_VERSION} \
                                        --sgw-build ${params.SGW_BUILD} \
                                        --cb-install-url '${params.CB_INSTALL_URL}' \
                                        --sgw-install-url '${params.SGW_INSTALL_URL}' \
                                        --with-sgw ${params.WITH_SGW}
                                """
                            }
                            echo ">>> Deployment completed successfully"
                        } else {
                            echo ">>> Skipping deploy/install step as SKIP_INSTALL is true"
                        }
                    }

                    echo ">>> Preparing provider file..."
                    sh """
                        cp /root/sequoia-provision/provider.yaml /opt/godev/src/github.com/couchbaselabs/sequoia/providers/file/provider.yml
                    """
                    echo ">>> Provider file ready"

                    echo ">>> Starting sequoia tests..."
                    dir('/opt/godev/src/github.com/couchbaselabs/sequoia') {
                        sh """
                            ./sequoia \
                                -client ${env.SLAVE_IP}:2375 \
                                -provider file:provider.yml \
                                -test ${params.TEST_FILE} \
                                -scale ${params.SCALE} \
                                -repeat ${params.REPEAT} \
                                -log_level ${params.LOG_LEVEL} \
                                -version ${params.CB_VERSION} \
                                -skip_setup=${params.SKIP_SETUP} \
                                -skip_test=${params.SKIP_TEST} \
                                -skip_teardown=${params.SKIP_TEARDOWN} \
                                -skip_cleanup=${params.SKIP_CLEANUP} \
                                -continue=${params.CONTINUE} \
                                -collect_on_error=${params.COLLECT_ON_ERROR} \
                                -stop_on_error=${params.STOP_ON_ERROR} \
                                -duration=${params.DURATION} \
                                -show_topology=${params.SHOW_TOPOLOGY}
                        """
                    }
                }
            }
        }
    }
}

