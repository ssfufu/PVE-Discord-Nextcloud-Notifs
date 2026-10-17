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
        // Filled by the webhook, or by hand to test the job.
        string(name: 'X_STATE', defaultValue: '', description: 'Severity: info, notice, warning, error or unknown')
        string(name: 'X_TYPE', defaultValue: '', description: 'Notification type: vzdump, package-updates, gc, prune, verify...')
        string(name: 'X_HOST', defaultValue: '', description: 'Name of the Proxmox server')
        string(name: 'X_TITLE', defaultValue: '', description: 'Notification title (optional)')
        string(name: 'X_TIMESTAMP', defaultValue: '', description: 'Notification time as a Unix timestamp (optional)')
        text(name: 'X_LOG_CONTENT', defaultValue: '', description: 'Notification body (full log)')
    }

    // Generic Webhook Trigger: Proxmox calls /generic-webhook-trigger/invoke with the token
    // stored in the "proxmox-webhook-token" credential ("Secret text").
    // The body is never printed: it contains the full log.
    triggers {
        GenericTrigger(
            genericVariables: [
                [key: 'X_STATE', value: '$.X_STATE', regexpFilter: '[^a-z]'],
                [key: 'X_TYPE', value: '$.X_TYPE', regexpFilter: '[^a-z0-9-]'],
                [key: 'X_HOST', value: '$.X_HOST', regexpFilter: '[^A-Za-z0-9._-]'],
                [key: 'X_TITLE', value: '$.X_TITLE'],
                [key: 'X_TIMESTAMP', value: '$.X_TIMESTAMP', regexpFilter: '[^0-9]'],
                [key: 'X_LOG_CONTENT', value: '$.X_LOG_CONTENT'],
            ],
            tokenCredentialId: 'proxmox-webhook-token',
            causeString: 'Proxmox notification: $X_TYPE ($X_STATE) from $X_HOST',
            printContributedVariables: false,
            printPostContent: false
        )
    }

    stages {
        stage('Prepare') {
            steps {
                script {
                    if (!params.X_LOG_CONTENT?.trim()) {
                        error "The notification body is empty."
                    }

                    // Values come from the webhook body: only keep safe characters,
                    // even when the job is started by hand.
                    env.NOTIF_STATE = clean(params.X_STATE, '[^a-z]') ?: 'unknown'
                    env.NOTIF_TYPE = clean(params.X_TYPE, '[^a-z0-9-]') ?: 'action'
                    env.NOTIF_HOST = clean(params.X_HOST, '[^A-Za-z0-9._-]') ?: 'proxmox'
                    env.NOTIF_TITLE = truncate((params.X_TITLE ?: '').trim(), 200)

                    // Time of the notification sent by Proxmox, or now.
                    def ts = clean(params.X_TIMESTAMP, '[^0-9]')
                    def date = ts ? new Date(Long.parseLong(truncate(ts, 12)) * 1000L) : new Date()
                    def utc = TimeZone.getTimeZone('UTC')
                    env.NOTIF_DATE = date.format('dd/MM/yyyy HH:mm', utc) + ' UTC'
                    env.NOTIF_ISO_DATE = date.format("yyyy-MM-dd'T'HH:mm:ss'Z'", utc)

                    env.LOG_FILE = "${env.NOTIF_HOST}_${env.NOTIF_TYPE}_${date.format('yyyy-MM-dd_HH-mm-ss', utc)}.log"
                    writeFile file: env.LOG_FILE, text: params.X_LOG_CONTENT

                    echo "Notification: ${env.NOTIF_TYPE} (${env.NOTIF_STATE}) from ${env.NOTIF_HOST}, log file ${env.LOG_FILE}"
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
                    switch(env.NOTIF_TYPE) {
                        case "package-updates":
                            actionType = "Package updates"
                            break
                        case "prune":
                            actionType = "Pruning"
                            break
                        case "gc":
                            actionType = "Garbage collection"
                            break
                        case "verify":
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
                    switch(env.NOTIF_STATE) {
                        case "info":
                            stateMessage = "${actionType} for ${env.NOTIF_HOST} on ${env.NOTIF_DATE} was successfully completed."
                            break
                        case "error":
                            stateMessage = "${actionType} for ${env.NOTIF_HOST} on ${env.NOTIF_DATE} failed."
                            break
                        case "notice":
                            stateMessage = "${actionType} for ${env.NOTIF_HOST} on ${env.NOTIF_DATE} completed with errors."
                            break
                        case "warning":
                            stateMessage = "${actionType} for ${env.NOTIF_HOST} on ${env.NOTIF_DATE} completed with warnings."
                            break
                        case "unknown":
                            stateMessage = "${actionType} for ${env.NOTIF_HOST} on ${env.NOTIF_DATE} has an unknown state: ${env.NOTIF_STATE}"
                            break
                        default:
                            stateMessage = "${actionType} for ${env.NOTIF_HOST} on ${env.NOTIF_DATE} has an unrecognized state (default message): ${env.NOTIF_STATE}"
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

// Removes the characters matching the pattern.
@NonCPS
String clean(String value, String pattern) {
    return (value ?: '').replaceAll(pattern, '')
}

@NonCPS
String truncate(String value, int max) {
    return value.length() > max ? value.substring(0, max) : value
}
