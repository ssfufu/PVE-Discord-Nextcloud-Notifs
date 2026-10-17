pipeline {
    agent any
    parameters {
        string(name: 'X_STATE', defaultValue: '', description: 'Backup state')
        string(name: 'X_LOG_CONTENT', defaultValue: 'If you are reading this outside of Jenkins, something went wrong', description: 'Log content received from Proxmox')
        string(name: 'X_FQDN', defaultValue: '', description: 'FQDN of the Nextcloud server')
        string(name: 'X_USER', defaultValue: '', description: 'Nextcloud username')
        string(name: 'X_PASSWORD', defaultValue: '', description: 'Nextcloud user password')
        string(name: 'X_DISCORD_WEBHOOK', defaultValue: '', description: 'Discord webhook')
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

                    // Creating the log file in the local workspace. (It will be removed at the end of the job).
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
                    if (!params.X_FQDN || !params.X_USER || !params.X_PASSWORD) {
                        error "Nextcloud parameters (FQDN, username, password) are not defined."
                    }

                    def nextcloudURL = "https://${params.X_FQDN}/remote.php/dav/files/${params.X_USER}/BACKUP-LOGS/${env.LOG_FILE}"

                    // Values go through the environment and are never interpolated into the script.
                    withEnv(["NC_USER=${params.X_USER}", "NC_PASS=${params.X_PASSWORD}", "NC_URL=${nextcloudURL}"]) {
                        sh 'curl -u "$NC_USER:$NC_PASS" -T "./$LOG_FILE" "$NC_URL"'
                    }

                    env.PROTECTED_URL = nextcloudURL
                    echo "File uploaded successfully: ${env.PROTECTED_URL}"
                }
            }
        }
        stage('Send link to Discord') {
            steps {
                script {
                    echo "Sending link to Discord"
                    if (!params.X_DISCORD_WEBHOOK) {
                        error "Discord webhook is not defined."
                    }

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

                    echo "Message for Discord: ${discordMessage}"
                    writeFile file: 'discord-payload.json', text: discordMessage
                    withEnv(["DISCORD_WEBHOOK=${params.X_DISCORD_WEBHOOK}"]) {
                        sh 'curl -H "Content-Type: application/json" -X POST --data-binary @discord-payload.json "$DISCORD_WEBHOOK"'
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
