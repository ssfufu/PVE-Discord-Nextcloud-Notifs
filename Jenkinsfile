pipeline {
    agent any

    environment {
        // Settings: adjust them to your setup.
        NEXTCLOUD_URL         = 'https://cloud.example.com'  // base URL of the Nextcloud server
        NEXTCLOUD_FOLDER      = 'BACKUP-LOGS'                // folder where the logs are stored
        NOTIFY_LANG           = 'en'                         // language of the Discord messages: 'en' or 'fr'
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
                // A Nextcloud failure must not prevent the Discord notification.
                catchError(buildResult: 'FAILURE', stageResult: 'FAILURE') {
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
                                    dav() {
                                        printf '%s\\n' "$auth" | curl --config - --silent --show-error \\
                                            --proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 300 \\
                                            --retry 5 --retry-delay 10 --retry-connrefused "$@"
                                    }

                                    # Create the folder tree if needed (201: created, 405: already exists).
                                    url=$NC_DAV_ROOT
                                    IFS=/
                                    for part in $NC_FOLDER; do
                                        url="$url/$part"
                                        code=$(dav --output /dev/null --write-out '%{http_code}' --request MKCOL "$url/")
                                        case $code in
                                            201|405) ;;
                                            *) echo "Cannot create the Nextcloud folder (HTTP $code)" >&2; exit 1 ;;
                                        esac
                                    done
                                    unset IFS

                                    dav --fail --output /dev/null --upload-file "$LOG_FILE" "$url/$LOG_FILE"
                                '''
                            }
                            env.LOG_URL = folder ? "${davRoot}/${folder}/${env.LOG_FILE}" : "${davRoot}/${env.LOG_FILE}"
                        }
                        echo "Log uploaded to Nextcloud: ${env.LOG_FILE}"
                    }
                }
            }
        }
        stage('Notify Discord') {
            steps {
                script {
                    def payload = discordPayload(lang: env.NOTIFY_LANG, state: env.NOTIF_STATE, type: env.NOTIF_TYPE, host: env.NOTIF_HOST,
                                                 title: env.NOTIF_TITLE, date: env.NOTIF_ISO_DATE,
                                                 logFile: env.LOG_FILE, logUrl: env.LOG_URL, build: env.BUILD_NUMBER)
                    writeFile file: 'discord-payload.json', text: payload
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
                    echo "Message sent to Discord."
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

// Labels used in the Discord message, per language.
@NonCPS
Map texts(String lang) {
    def all = [:]
    all.en = [
        types: [
            'vzdump': 'Backup',
            'package-updates': 'Package updates',
            'replication': 'Replication',
            'fencing': 'Fencing',
            'system-mail': 'System mail',
            'gc': 'Garbage collection',
            'prune': 'Prune',
            'sync': 'Sync',
            'verify': 'Verification',
            'verification': 'Verification',
            'tape-backup': 'Tape backup',
            'tape-load': 'Tape load',
            'acme': 'Certificate renewal',
        ],
        states: [
            info: 'Success',
            notice: 'Completed with notices',
            warning: 'Completed with warnings',
            error: 'Failure',
            unknown: 'Unknown',
        ],
        status: 'Status',
        log: 'Log file',
        logMissing: 'Not available: the upload to Nextcloud failed (Jenkins build #%s)',
    ]
    all.fr = [
        types: [
            'vzdump': 'Sauvegarde',
            'package-updates': 'Mise à jour des paquets',
            'replication': 'Réplication',
            'fencing': 'Fencing',
            'system-mail': 'Mail système',
            'gc': 'Garbage collection',
            'prune': 'Nettoyage',
            'sync': 'Synchronisation',
            'verify': 'Vérification',
            'verification': 'Vérification',
            'tape-backup': 'Sauvegarde sur bande',
            'tape-load': 'Chargement de bande',
            'acme': 'Renouvellement de certificat',
        ],
        states: [
            info: 'Succès',
            notice: 'Terminé avec des remarques',
            warning: 'Terminé avec des avertissements',
            error: 'Échec',
            unknown: 'Inconnu',
        ],
        status: 'Statut',
        log: 'Fichier de log',
        logMissing: "Indisponible : l'envoi vers Nextcloud a échoué (build Jenkins #%s)",
    ]
    return all[lang] ?: all.en
}

// Builds the Discord message: one embed, colored by severity.
// Mentions are disabled, so a value such as "@everyone" cannot ping anybody.
@NonCPS
String discordPayload(Map n) {
    def t = texts(n.lang)
    def styles = [
        info: ['\u2705', 0x2ECC71],
        notice: ['\u2139\uFE0F', 0x3498DB],
        warning: ['\u26A0\uFE0F', 0xE67E22],
        error: ['\u274C', 0xE74C3C],
    ]
    def style = styles[n.state] ?: ['\u2754', 0x95A5A6]
    def action = t.types[n.type] ?: n.type
    def status = t.states[n.state] ?: "${t.states.unknown} (${n.state})"
    def logLink = n.logUrl ? "[${n.logFile}](${n.logUrl})".toString() : String.format(t.logMissing, n.build)

    def embed = [
        title: truncate("${style[0]} ${n.host} \u2014 ${action}", 256),
        color: style[1],
        timestamp: n.date,
        fields: [
            [name: t.status, value: status.toString(), inline: true],
            [name: t.log, value: logLink, inline: true],
        ],
    ]
    if (n.title) {
        embed.description = n.title
    }
    return groovy.json.JsonOutput.toJson([allowed_mentions: [parse: []], embeds: [embed]])
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
