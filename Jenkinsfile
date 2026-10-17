pipeline {
    agent any

    environment {
        // Settings: adjust them to your setup.
        NEXTCLOUD_URL         = 'https://cloud.example.com'  // base URL of the Nextcloud server
        NEXTCLOUD_FOLDER      = 'BACKUP-LOGS'                // folder where the logs are stored
        // IDs of the Jenkins credentials (Manage Jenkins > Credentials).
        NEXTCLOUD_CREDENTIALS = 'nextcloud-backup-logs'      // "Username with password" (use an app password)
        DISCORD_CREDENTIALS   = 'discord-webhook'            // "Secret text" containing the webhook URL
    }

    parameters {
        string(name: 'X_STATE', defaultValue: '', description: 'Backup state')
        string(name: 'X_LOG_CONTENT', defaultValue: 'If you are reading this outside of Jenkins, something went wrong', description: 'Log content received from Proxmox')
        string(name: 'X_TYPE', defaultValue: '', description: 'Type of action')
        string(name: 'X_HOST', defaultValue: '', description: 'Hostname of the Proxmox server')
        string(name: 'X_FORMATTED_TIMESTAMP', defaultValue: '', description: 'Backup timestamp')
    }

    stages {
        stage('Initialization') {
            steps {
                script {
                    echo "Initialization"

                    // This timestamp will be used for the name of the log file.
                    def timestamp = new Date().format("yyyy-MM-dd_HH-mm-ss", TimeZone.getTimeZone('UTC'))
                    env.X_BACKUP_TIMESTAMP = timestamp

                    // Here I format the time for my needs, it's the one displayed in the Discord message.
                    def formattedTimestamp = new Date().format("dd/MM/yyyy", TimeZone.getTimeZone('UTC'))
                    env.X_FORMATTED_TIMESTAMP = formattedTimestamp

                    echo "Generated timestamp: ${env.X_BACKUP_TIMESTAMP}"
                    echo "State: ${params.X_STATE}, type: ${params.X_TYPE}, host: ${params.X_HOST}"
                }
            }
        }
        stage('Save logs locally') {
            steps {
                script {
                    echo "Saving logs locally"
                    if (!params.X_LOG_CONTENT || params.X_LOG_CONTENT.trim().isEmpty()) {
                        error "Logs are empty or have not been received."
                    }

                    // The type comes from the webhook body: only keep safe characters.
                    def safeType = (params.X_TYPE ?: '').replaceAll('[^A-Za-z0-9_-]', '') ?: 'action'
                    def logFileName = "${safeType}-log-${env.X_BACKUP_TIMESTAMP}.log"
                    writeFile file: logFileName, text: params.X_LOG_CONTENT
                    env.LOG_FILE = logFileName
                    echo "File saved locally: ${logFileName}"
                }
            }
        }
        stage('Upload to Nextcloud') {
            steps {
                script {
                    echo "Uploading logs to Nextcloud"
                    withCredentials([usernamePassword(credentialsId: env.NEXTCLOUD_CREDENTIALS,
                                                      usernameVariable: 'NC_USER', passwordVariable: 'NC_PASS')]) {
                        def base = env.NEXTCLOUD_URL.replaceAll('/+$', '')
                        if (!base.startsWith('https://')) {
                            error "NEXTCLOUD_URL must start with https://"
                        }
                        def davRoot = "${base}/remote.php/dav/files/${urlEncode(env.NC_USER)}"
                        def folder = davPath(env.NEXTCLOUD_FOLDER)

                        // Values go through the environment and are never interpolated into the script.
                        // The credentials are given to curl on stdin, so they do not show in the process list.
                        withEnv(["NC_DAV_ROOT=${davRoot}", "NC_FOLDER=${folder}"]) {
                            sh '''
                                set -euf
                                esc() { printf '%s' "$1" | sed 's/[\\\\"]/\\\\&/g'; }
                                auth=$(printf 'user = "%s:%s"' "$(esc "$NC_USER")" "$(esc "$NC_PASS")")
                                nc() {
                                    printf '%s\\n' "$auth" | curl --config - --silent --show-error \\
                                        --proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 300 \\
                                        --retry 5 --retry-delay 10 --retry-connrefused "$@"
                                }

                                # Create the folder tree if needed (201: created, 405: already exists).
                                url=$NC_DAV_ROOT
                                IFS=/
                                for part in $NC_FOLDER; do
                                    url="$url/$part"
                                    code=$(nc --output /dev/null --write-out '%{http_code}' --request MKCOL "$url/")
                                    case $code in
                                        201|405) ;;
                                        *) echo "Cannot create the Nextcloud folder (HTTP $code)" >&2; exit 1 ;;
                                    esac
                                done
                                unset IFS

                                nc --fail --output /dev/null --upload-file "$LOG_FILE" "$url/$LOG_FILE"
                            '''
                        }
                        env.PROTECTED_URL = "${davRoot}/${folder}/${env.LOG_FILE}"
                    }
                    echo "File uploaded successfully: ${env.LOG_FILE}"
                }
            }
        }
        stage('Send link to Discord') {
            steps {
                script {
                    echo "Sending link to Discord"

                    // Not sure about the usage of the two next switch/case.
                    // The first part of the stateMessage variable, it depends on the value of <fields.type> sent by the PVE or PBS.
                    def actionType = ""
                    def stateMessage = ""
                    switch(params.X_TYPE) {
                        case "package-updates":
                            actionType = "Package updates"
                            break
                        case "prune":
                            actionType = "Pruning"
                            break
                        case "gc":
                            actionType = "Garbage collection"
                            break
                        case "verification":
                            actionType = "Verification"
                            break
                        case "vzdump":
                            actionType = "Backup"
                            break
                        default:
                            actionType = "Action"
                        break
                    }

                    // Creating the first part of the Discord message, which content's different by reading the <severity> variable sent by the PVE or PBS.
                    switch(params.X_STATE) {
                        case "info":
                            stateMessage = "${actionType} for ${params.X_HOST} on ${env.X_FORMATTED_TIMESTAMP} was successfully completed."
                            break
                        case "error":
                            stateMessage = "${actionType} for ${params.X_HOST} on ${env.X_FORMATTED_TIMESTAMP} failed."
                            break
                        case "notice":
                            stateMessage = "${actionType} for ${params.X_HOST} on ${env.X_FORMATTED_TIMESTAMP} completed with errors."
                            break
                        case "warning":
                            stateMessage = "${actionType} for ${params.X_HOST} on ${env.X_FORMATTED_TIMESTAMP} completed with warnings."
                            break
                        case "unknown":
                            stateMessage = "${actionType} for ${params.X_HOST} on ${env.X_FORMATTED_TIMESTAMP} has an unknown state: ${params.X_STATE}"
                            break
                        default:
                            stateMessage = "${actionType} for ${params.X_HOST} on ${env.X_FORMATTED_TIMESTAMP} has an unrecognized state (default message): ${params.X_STATE}"
                            break
                    }

                    // Second part of the Discord message, it contains the URL to download the log file (protected by the basic authentication module of Nextcloud).
                    def logMessage = "The log file is available here: ${env.PROTECTED_URL}"

                    // Assembly of the Discord message.
                    def discordMessage = groovy.json.JsonOutput.toJson([
                        content: "${stateMessage} ${logMessage}"
                    ])

                    writeFile file: 'discord-payload.json', text: discordMessage
                    withCredentials([string(credentialsId: env.DISCORD_CREDENTIALS, variable: 'DISCORD_WEBHOOK')]) {
                        sh '''
                            set -eu
                            esc() { printf '%s' "$1" | sed 's/[\\\\"]/\\\\&/g'; }
                            printf 'url = "%s"\\n' "$(esc "$DISCORD_WEBHOOK")" |
                                curl --config - --silent --show-error --fail --output /dev/null \\
                                    --proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 60 \\
                                    --retry 5 --retry-delay 5 --retry-connrefused \\
                                    --header 'Content-Type: application/json' --data-binary @discord-payload.json
                        '''
                    }
                    echo "Message successfully sent to Discord."
                }
            }
        }
    }
    post {
        always {
            echo "Pipeline completed"
            cleanWs()
        }
    }
}

// Encodes one segment of a URL path.
@NonCPS
String urlEncode(String value) {
    return URLEncoder.encode(value, 'UTF-8').replace('+', '%20')
}

// Encodes a folder path ("a/b c" -> "a/b%20c"), ignoring empty segments.
@NonCPS
String davPath(String folder) {
    return folder.split('/').findAll { it }.collect { urlEncode(it) }.join('/')
}
