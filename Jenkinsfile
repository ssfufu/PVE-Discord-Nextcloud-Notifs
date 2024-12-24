pipeline {
    agent any
    parameters {
        string(name: 'X_STATE', defaultValue: '', description: 'Etat de la backup')
        string(name: 'X_LOG_CONTENT', defaultValue: 'Si tu lis ca, alors ca a foire quelque part', description: 'Contenu des logs recu depuis Proxmox')
        string(name: 'X_FQDN', defaultValue: '', description: 'FQDN du serveur Nextcloud')
        string(name: 'X_USER', defaultValue: '', description: 'Nom d utilisateur Nextcloud')
        string(name: 'X_PASSWORD', defaultValue: '', description: 'Mot de passe de l utilisateur Nextcloud')
        string(name: 'X_DISCORD_WEBHOOK', defaultValue: '', description: 'Webhook Discord')
        string(name: 'X_TYPE', defaultValue: '', description: 'Type d action')
        string(name: 'X_HOST', defaultValue: '', description: 'Nom d hote du serveur Proxmox')
        string(name: 'X_FORMATTED_TIMESTAMP', defaultValue: '', description: 'Timestamp de la backup')
    }

    stages {
        stage ('Initialisation') {
            steps {
                script {
                    echo "Initialisation"
                    
                    def timestamp = new Date().format("yyyy-MM-dd_HH-mm-ss", TimeZone.getTimeZone('UTC'))
                    env.X_BACKUP_TIMESTAMP = timestamp
                    def formattedTimestamp = new Date().format("dd/MM/yyyy", TimeZone.getTimeZone('UTC'))
                    env.X_FORMATTED_TIMESTAMP = formattedTimestamp

                    echo "Timestamp genere : ${env.X_BACKUP_TIMESTAMP}"
                    echo "${params.X_STATE} ${params.X_TYPE} ${env.X_BACKUP_TIMESTAMP} ${params.X_HOST} ${params.X_FQDN} ${params.X_USER} ${params.X_PASSWORD} ${params.X_DISCORD_WEBHOOK}"
                }
            }
        }
        stage('Sauvegarder les logs localement') {
            steps {
                script {
                    echo "Sauvegarde locale des logs"
                    if (!params.X_LOG_CONTENT || params.X_LOG_CONTENT.trim().isEmpty()) {
                        error "Les logs sont vides ou n ont pas été recus."
                    }
                    
                    def logFileName = "backup-log-${env.X_BACKUP_TIMESTAMP}.log"
                    writeFile file: logFileName, text: params.X_LOG_CONTENT
                    env.LOG_FILE = logFileName
                    echo "Fichier sauvegarde localement : ${logFileName}"
                }
            }
        }
        stage('Uploader vers Nextcloud') {
            steps {
                script {
                    echo "Upload des logs vers Nextcloud"
                    if (!params.X_FQDN || !params.X_USER || !params.X_PASSWORD) {
                        error "Les parametres Nextcloud (FQDN, utilisateur, mot de passe) ne sont pas definis."
                    }
                    
                    def nextcloudURL = "https://${params.X_FQDN}/remote.php/dav/files/${params.X_USER}/BACKUP-LOGS/${env.LOG_FILE}"
                    sh """
                    curl -u ${params.X_USER}:${params.X_PASSWORD} -T ./${env.LOG_FILE} ${nextcloudURL}
                    """
                    
                    env.PROTECTED_URL = nextcloudURL
                    echo "Fichier uploade avec succès : ${env.PROTECTED_URL}"
                }
            }
        }
        stage('Envoyer le lien a Discord') {
            steps {
                script {
                    echo "Envoi du lien vers Discord"
                    if (!params.X_DISCORD_WEBHOOK) {
                        error "Le webhook Discord n est pas defini."
                    }
                    
                    def actionType = ""
                    switch(params.X_TYPE) {
                        case "package-updates":
                            actionType = "La mise a jour des paquets"
                            break
                        case "prune":
                            actionType = "Le nettoyage"
                            break
                        case "gc":
                            actionType = "Le garbage collection"
                            break
                        case "verification":
                            actionType = "La verification"
                            break
                        case "vzdump":
                            actionType = "La sauvegarde"
                            break
                        default:
                            actionType = "L action"
                        break
                    }

                    switch(params.X_STATE) {
                        case "info":
                            stateMessage = "${actionType} du ${params.X_HOST} en date du ${env.X_FORMATTED_TIMESTAMP} a été effectuée avec succès."
                            break
                        case "error":
                            stateMessage = "${actionType} du ${params.X_HOST} en date du ${env.X_FORMATTED_TIMESTAMP} a échoué."
                            break
                        case "notice":
                            stateMessage = "${actionType} du ${params.X_HOST} en date du ${env.X_FORMATTED_TIMESTAMP} a été effectuée avec des erreurs."
                            break
                        case "warning":
                            stateMessage = "${actionType} du ${params.X_HOST} en date du ${env.X_FORMATTED_TIMESTAMP} a été effectuée avec des avertissements."
                            break
                        case "unknown":
                            stateMessage = "${actionType} du ${params.X_HOST} en date du ${env.X_FORMATTED_TIMESTAMP} a un état inconnu : ${params.X_STATE}"
                            break
                        default:
                            stateMessage = "${actionType} du ${params.X_HOST} en date du ${env.X_FORMATTED_TIMESTAMP} a un état non reconnu (msg par défaut): ${params.X_STATE}"
                            break
                    }

                    def logMessage = "Le fichier de log est disponible ici : ${env.PROTECTED_URL}"

                    def discordMessage = groovy.json.JsonOutput.toJson([
                        content: "${stateMessage} ${logMessage}"
                    ])

                    echo "Message pour Discord : ${discordMessage}"
                    sh """
                    curl -H "Content-Type: application/json" -X POST \
                    -d '${discordMessage}' \
                    ${params.X_DISCORD_WEBHOOK}
                    """
                    echo "Message envoye a Discord avec succès."
                }
            }
        }
    }
    post {
        always {
            echo "Pipeline termine"
            cleanWs()
        }
    }
}
