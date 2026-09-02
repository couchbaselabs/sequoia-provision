pipeline {
    agent none

    parameters {
        choice(name: 'COMPONENT',
               choices: [
                   'component3',
                   'component6',
                   'component7',
                   'mid_scale_component1',
                   'longevity_cluster_1',
                   'longevity_cluster_2'
               ],
               description: 'Select which component or longevity cluster to deploy and run tests for')

        booleanParam(name: 'SKIP_INSTALL', defaultValue: false, description: 'Skip deploy/install step')
        string(name: 'CB_VERSION', defaultValue: '8.5.0', description: 'Couchbase version')
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
        booleanParam(name: 'NFS_LONGEVITY_TEST', defaultValue: false, description: 'Fetch NFS server from pool for longevity tests (poolId=nfs_server)')
        booleanParam(name: 'NFS_COMPONENT_TEST', defaultValue: false, description: 'Fetch NFS server from pool for component tests (poolId=nfs_server)')


        string(name: 'SCALE', defaultValue: '1', description: 'Scale parameter for sequoia')
        string(name: 'REPEAT', defaultValue: '1', description: 'Repeat parameter for sequoia')
        string(name: 'DURATION', defaultValue: '604800', description: 'Test duration in seconds')

        booleanParam(name: 'SHOW_TOPOLOGY', defaultValue: true, description: 'Show test topology')
        booleanParam(name: 'COLLECT_ON_ERROR', defaultValue: false, description: 'Collect data on error')
        booleanParam(name: 'STOP_ON_ERROR', defaultValue: false, description: 'Stop test on error')
        booleanParam(name: 'SKIP_CLEANUP', defaultValue: false, description: 'Skip cleanup phase')
        booleanParam(name: 'SKIP_TEARDOWN', defaultValue: true, description: 'Skip teardown phase')
        booleanParam(name: 'SKIP_TEST', defaultValue: false, description: 'Skip test execution')
        booleanParam(name: 'SKIP_SETUP', defaultValue: false,
                     description: 'Skip scope setup (cluster/bucket provisioning). Sequoia also treats this as a resumed run and skips one-time test setup: initial data load, collection creation, xdcr-setup, n2n encryption.')

        string(name: 'LOG_LEVEL', defaultValue: '0', description: 'Logging level (0–5)')

        string(name: 'DOCKER_CREDS_ID', defaultValue: 'sys_test_docker_cred',
               description: 'Jenkins usernamePassword credentials ID for Docker Hub. Set it to refresh the docker login before each test run; leave empty to reuse the existing login on the slave.')

        booleanParam(name: 'START_EAGLE_EYE', defaultValue: false,
                     description: 'After install, stop any running eagle eye (system_test_log_parser) build for this cluster master and start a fresh one')
        string(name: 'EMAIL_RECIPIENTS', defaultValue: '',
               description: 'Comma-separated recipients for the eagle eye run. Leave empty to keep the log parser job default.')

        // Git customization parameters
    }

    stages {
        stage('Select Target VM') {
            steps {
                script {
                    def config = [
                        component3: [vm: 'component-systest-client-3', ip: '172.23.216.124'],
                        component6: [vm: 'component-systest-client-6', ip: '172.23.216.126'],
                        component7: [vm: 'component-systest-client-7', ip: '172.23.216.125'],
                        mid_scale_component1: [vm: 'mid_scale_component-client-1', ip: '172.23.106.226'],
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
                    currentBuild.description = "Build: ${params.CB_VERSION} - ${params.CB_BUILD} | Component: ${params.COMPONENT} | VM: ${env.VM_NAME} | IP: ${env.SLAVE_IP}"

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
                            git cherry-pick --abort || true
                            git reset --hard HEAD
                            git fetch origin
                            git checkout -B ${params.SEQ_PROVISION_BRANCH} origin/${params.SEQ_PROVISION_BRANCH}
                        """
                    }

                    dir('/opt/godev/src/github.com/couchbaselabs/sequoia') {
                        sh """
                            if [ ! -d .git ]; then
                                git clone https://github.com/couchbaselabs/sequoia.git .
                            fi
                            git cherry-pick --abort || true
                            git reset --hard HEAD
                            git fetch origin
                            git checkout -B ${params.SEQ_REPO_BRANCH} origin/${params.SEQ_REPO_BRANCH}
                        """

                        if (params.SEQ_CHERRYPICK?.trim()) {
                            sh """
                                ${params.SEQ_CHERRYPICK} || echo "Cherry-pick failed or conflicts found"
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
                        usernamePassword(credentialsId: 'qe_db_cluster', usernameVariable: 'CONFIG_USERNAME', passwordVariable: 'CONFIG_PASSWORD'),
                        [$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'BACKUP_RESTORE_SYSTEMTEST_S3_ACCESS_KEYS', accessKeyVariable: 'AWS_ACCESS_KEY_ID', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'],
                        usernamePassword(credentialsId: 'BACKUP_RESTORE_SYSTEMTEST_AZURE_ACCESS_KEYS', usernameVariable: 'AZURE_STORAGE_ACCOUNT', passwordVariable: 'AZURE_STORAGE_KEY'),
                        string(credentialsId: 'BACKUP_RESTORE_SYSTEMTEST_AZURE_ENDPOINT', variable: 'AZURE_STORAGE_ENDPOINT'),
                        file(credentialsId: 'BACKUP_RESTORE_SYSTEMTEST_GCP_JSON', variable: 'GCP_SERVICE_ACCOUNT_FILE')
                    ]) {
                        if (!params.SKIP_INSTALL) {
                            echo ">>> Starting Couchbase deployment..."
                            dir('/root/sequoia-provision') {
                                sh """
                                    export CONFIG_PASSWORD='${CONFIG_PASSWORD}'
                                    export SSH_PASSWORD='${SSH_PASSWORD}'
                                    export ANSIBLE_SSH_PASSWORD="$SSH_PASSWORD"
                                    export AWS_ACCESS_KEY_ID='${AWS_ACCESS_KEY_ID}'
                                    export AWS_SECRET_ACCESS_KEY='${AWS_SECRET_ACCESS_KEY}'
                                    export AZURE_STORAGE_ACCOUNT='${AZURE_STORAGE_ACCOUNT}'
                                    export AZURE_STORAGE_KEY='${AZURE_STORAGE_KEY}'
                                    export AZURE_STORAGE_ENDPOINT='${AZURE_STORAGE_ENDPOINT}'
                                    export GCP_SERVICE_ACCOUNT_FILE='${GCP_SERVICE_ACCOUNT_FILE}'
                                    ./deploy.sh \
                                        --cb-pool-id ${params.COMPONENT} \
                                        --cb-version ${params.CB_VERSION} \
                                        --cb-build ${params.CB_BUILD} \
                                        --sgw-version ${params.SGW_VERSION} \
                                        --sgw-build ${params.SGW_BUILD} \
                                        --cb-install-url '${params.CB_INSTALL_URL}' \
                                        --sgw-install-url '${params.SGW_INSTALL_URL}' \
                                        --with-sgw ${params.WITH_SGW} \
                                        --nfs-longevity-test ${params.NFS_LONGEVITY_TEST} \
                                        --nfs-component-test ${params.NFS_COMPONENT_TEST}
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

                    // sequoia's image pull reads Docker Hub creds only from
                    // $DOCKER_CONFIG/config.json (falling back to $HOME/.docker/config.json) and
                    // never calls a credential helper. The Jenkins agent's $HOME is not /root, so
                    // DOCKER_CONFIG is pinned below. When DOCKER_CREDS_ID is set we refresh the
                    // login into a dedicated dir that starts empty, so no credsStore/credHelpers
                    // entry can divert the creds into a helper sequoia cannot read.
                    def dockerCfgDir = '/root/.docker'
                    if (params.DOCKER_CREDS_ID?.trim()) {
                        echo ">>> Refreshing Docker Hub login..."
                        try {
                            withCredentials([usernamePassword(credentialsId: params.DOCKER_CREDS_ID,
                                                              usernameVariable: 'DOCKER_USER',
                                                              passwordVariable: 'DOCKER_PASS')]) {
                                withEnv(['DOCKER_CONFIG=/root/.docker-sequoia']) {
                                    sh '''
                                        set +x
                                        mkdir -p "$DOCKER_CONFIG"
                                        printf '{}' > "$DOCKER_CONFIG/config.json"
                                        echo "$DOCKER_PASS" | docker --config "$DOCKER_CONFIG" login --username "$DOCKER_USER" --password-stdin
                                        if ! grep -q 'index.docker.io/v1/' "$DOCKER_CONFIG/config.json"; then
                                            echo "ERROR: docker login stored no usable auth entry in $DOCKER_CONFIG/config.json"
                                            exit 1
                                        fi
                                    '''
                                }
                            }
                            dockerCfgDir = '/root/.docker-sequoia'
                            echo ">>> Docker Hub login refreshed into ${dockerCfgDir}"
                        } catch (err) {
                            echo ">>> WARNING: docker login failed (${err.getMessage()}); falling back to ${dockerCfgDir}"
                        }
                    } else {
                        echo ">>> DOCKER_CREDS_ID not set - reusing existing login at ${dockerCfgDir}"
                    }

                    def runSequoia = {
                        echo ">>> Starting sequoia tests..."
                        dir('/opt/godev/src/github.com/couchbaselabs/sequoia') {
                            withEnv(["DOCKER_CONFIG=${dockerCfgDir}"]) {
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
                                        -collect_on_error=${params.COLLECT_ON_ERROR} \
                                        -stop_on_error=${params.STOP_ON_ERROR} \
                                        -duration=${params.DURATION} \
                                        -show_topology=${params.SHOW_TOPOLOGY}
                                """
                            }
                        }
                    }

                    // The log parser job tracks one cluster, keyed by its master_node param.
                    // deploy.sh writes the pool's master_node=true host first into provider.yaml, and
                    // sequoia treats the first entry as its orchestrator (lib/template.go Orchestrator),
                    // so that IP is the cluster identity both jobs agree on.
                    if (params.START_EAGLE_EYE) {
                        // Deliberately not a build parameter: the same requests carry the
                        // jenkins_qe_infra_user credentials, and curl applies them to whatever host
                        // the URL names, so a caller-supplied value could redirect them anywhere.
                        def logParserUrl = 'http://172.23.121.80/job/system_test_log_parser'

                        def masterNode = sh(
                            script: "grep -m1 -E '^[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+' /opt/godev/src/github.com/couchbaselabs/sequoia/providers/file/provider.yml | tr -d '[:space:]'",
                            returnStdout: true).trim()
                        echo ">>> Cluster master node: ${masterNode}"

                        def syncLogParser = {
                            sh '''
                                set +x
                                if [ -z "$MASTER_NODE" ]; then
                                    echo "ERROR: no master node found in provider.yml"
                                    exit 1
                                fi
                                if ! command -v jq >/dev/null 2>&1; then
                                    echo "ERROR: jq is required to read the log parser build list"
                                    exit 1
                                fi

                                LP_ROOT=$(echo "$LP_URL" | sed 's#/job/.*##')

                                # Keep the password out of argv (visible in ps) by passing it through
                                # curl config files instead of command flags.
                                CFG=$(mktemp)
                                CFG_TRIG=$(mktemp)
                                JAR=$(mktemp)
                                HDRS=$(mktemp)
                                MAIL=$(mktemp)
                                trap 'rm -f "$CFG" "$CFG_TRIG" "$JAR" "$HDRS" "$MAIL"' EXIT
                                chmod 600 "$CFG" "$CFG_TRIG" "$JAR" "$HDRS" "$MAIL"
                                : > "$CFG"
                                printf 'user = "%s:%s"\\n' "$LP_USER" "$LP_PASSWORD" >> "$CFG"
                                # Bound every request. An endpoint that accepts the connection and then
                                # stalls would otherwise hold this branch until the pipeline is aborted.
                                printf 'connect-timeout = 15\\nmax-time = 60\\n' >> "$CFG"
                                # No build token: the jenkins_qe_infra_user login in $CFG authorizes
                                # the POST, so $CFG_TRIG only adds the trigger's own parameters.
                                cat "$CFG" > "$CFG_TRIG"
                                # Recipients come from a build parameter, so the value never reaches
                                # curl-config syntax: it goes into its own file and the config points at
                                # the file, leaving nothing to quote, escape, or inject through.
                                if [ -n "$EMAIL_RECIPIENTS" ]; then
                                    printf '%s' "$EMAIL_RECIPIENTS" > "$MAIL"
                                    printf 'data-urlencode = "email_recipients@%s"\\n' "$MAIL" >> "$CFG_TRIG"
                                    echo ">>> Eagle eye recipients: $EMAIL_RECIPIENTS"
                                else
                                    echo ">>> Eagle eye recipients: job default"
                                fi

                                # This Jenkins has CSRF protection on, and password/basic-auth POSTs are
                                # not exempt the way API-token POSTs are. A crumb alone still 403s: it is
                                # only accepted alongside the session it was issued to, so every call
                                # below shares one cookie jar.
                                CRUMB_JSON=$(curl -sS -K "$CFG" -c "$JAR" -b "$JAR" "$LP_ROOT/crumbIssuer/api/json" || true)
                                CRUMB_FIELD=$(echo "$CRUMB_JSON" | jq -r '.crumbRequestField // empty')
                                CRUMB=$(echo "$CRUMB_JSON" | jq -r '.crumb // empty')
                                if [ -n "$CRUMB" ]; then
                                    CRUMB_HDR="$CRUMB_FIELD: $CRUMB"
                                    echo ">>> CSRF crumb acquired"
                                else
                                    # Harmless placeholder keeps one code path; POSTs may then be refused.
                                    CRUMB_HDR="X-No-Crumb: 1"
                                    echo ">>> WARNING: could not read a CSRF crumb from $LP_ROOT"
                                fi

                                RC=0

                                echo ">>> Looking for running builds with master_node=$MASTER_NODE"
                                RUNNING=$(curl -sS -K "$CFG" -b "$JAR" -c "$JAR" -G "$LP_URL/api/json" --data-urlencode 'tree=builds[number,building,actions[parameters[name,value]]]{0,300}' | jq -r --arg m "$MASTER_NODE" '.builds[] | select(.building) | select(any(.actions[]?.parameters[]?; .name == "master_node" and .value == $m)) | .number')

                                if [ -z "$RUNNING" ]; then
                                    echo ">>> No running build for this master node"
                                else
                                    for b in $RUNNING; do
                                        CODE=$(curl -sS -o /dev/null -w '%{http_code}' -K "$CFG" -b "$JAR" -c "$JAR" -H "$CRUMB_HDR" -X POST "$LP_URL/$b/stop")
                                        echo ">>> stop build #$b -> HTTP $CODE ($LP_URL/$b/)"
                                        case "$CODE" in
                                            2*|3*) ;;
                                            # Warn rather than exit, so a failed stop still lets the
                                            # trigger below run; RC surfaces it as UNSTABLE afterwards.
                                            *) echo ">>> WARNING: could not stop build #$b"; RC=1 ;;
                                        esac
                                    done
                                fi

                                echo ">>> Starting eagle eye for $MASTER_NODE"
                                CODE=$(curl -sS -o /dev/null -D "$HDRS" -w '%{http_code}' -K "$CFG_TRIG" -b "$JAR" -c "$JAR" -H "$CRUMB_HDR" -X POST "$LP_URL/buildWithParameters" --data-urlencode "master_node=$MASTER_NODE")
                                echo ">>> trigger -> HTTP $CODE"
                                case "$CODE" in
                                    2*|3*) echo ">>> Eagle eye started" ;;
                                    *) echo ">>> ERROR: trigger failed"; RC=1; exit $RC ;;
                                esac

                                # buildWithParameters answers with the queue item, not the build. The
                                # build number only exists once the queue item is scheduled, so poll it
                                # briefly to turn the queue link into the real job link.
                                QUEUE_URL=$(awk 'tolower($1) == "location:" { gsub(/\\r/, "", $2); print $2 }' "$HDRS" | tail -1)
                                if [ -z "$QUEUE_URL" ]; then
                                    echo ">>> Eagle eye job: $LP_URL (no queue location returned)"
                                    exit $RC
                                fi

                                BUILD_URL=""
                                i=0
                                while [ $i -lt 20 ]; do
                                    BUILD_URL=$(curl -sS -K "$CFG" -b "$JAR" -c "$JAR" "${QUEUE_URL}api/json" | jq -r '.executable.url // empty')
                                    if [ -n "$BUILD_URL" ]; then
                                        break
                                    fi
                                    i=$((i + 1))
                                    sleep 3
                                done

                                if [ -n "$BUILD_URL" ]; then
                                    echo ">>> Eagle eye job link: $BUILD_URL"
                                    echo ">>> Eagle eye console:  ${BUILD_URL}console"
                                else
                                    echo ">>> Eagle eye still queued, link: $QUEUE_URL"
                                fi

                                exit $RC
                            '''
                        }

                        def startEagleEye = {
                            // ./sequoia holds this stage for the whole DURATION, so eagle eye cannot
                            // simply follow it. Both run as parallel branches on this node, and this
                            // one waits so parsing starts once the cluster is genuinely under load.
                            // 0 starts eagle eye immediately, for short runs that would
                            // otherwise finish before the delay is over.
                            def delayMins = 5
                            if (delayMins > 0) {
                                echo ">>> Eagle eye starts ${delayMins} minute(s) after the test"
                                sleep(time: delayMins, unit: 'MINUTES')
                            }
                            try {
                                // Every call authenticates as jenkins_qe_infra_user; no build token
                                // is used, so the job needs Build permission for that user rather than
                                // "Trigger builds remotely".
                                withEnv(["LP_URL=${logParserUrl}",
                                         "EMAIL_RECIPIENTS=${params.EMAIL_RECIPIENTS}",
                                         "MASTER_NODE=${masterNode}"]) {
                                    withCredentials([usernamePassword(credentialsId: 'jenkins_qe_infra_user',
                                                                      usernameVariable: 'LP_USER',
                                                                      passwordVariable: 'LP_PASSWORD')]) {
                                        syncLogParser()
                                    }
                                }
                            } catch (err) {
                                // A longevity run must not die because log parsing could not be started.
                                echo ">>> WARNING: eagle eye sync failed (${err.getMessage()})"
                                currentBuild.result = 'UNSTABLE'
                            }
                        }

                        def branches = [:]
                        branches['sequoia'] = runSequoia
                        branches['eagle-eye'] = startEagleEye
                        // failFast aborts the eagle eye branch if the test dies during the delay,
                        // so nothing is pointed at a cluster that is no longer running a test. It
                        // cannot fire the other way: startEagleEye swallows its own failures.
                        branches['failFast'] = true
                        parallel(branches)
                    } else {
                        runSequoia()
                    }
                }
            }
        }
    }
}
