# 🔔 PVE Discord Nextcloud Notifs

> Envoie les notifications de Proxmox VE et Proxmox Backup Server sur Discord,
> avec le log complet stocké dans Nextcloud, via un pipeline Jenkins.
>
> Compatible : **Proxmox VE 8.3+** et **Proxmox Backup Server 3.3+** (cibles de
> notification webhook). 🇬🇧 [English version](README.md)

## 📖 Sommaire

- [Pourquoi](#-pourquoi)
- [Fonctionnement](#️-fonctionnement)
- [Prérequis](#-prérequis)
- [Installation](#-installation)
- [Tester](#-tester)
- [Réglages](#️-réglages)
- [Sécurité](#-sécurité)
- [Dépannage](#-dépannage)
- [Mise à jour depuis la 1.x](#️-mise-à-jour-depuis-la-1x)
- [Avertissement](#️-avertissement)

## 💡 Pourquoi

Proxmox sait envoyer ses notifications vers un webhook depuis la VE 8.3, mais
un message Discord est limité à 2000 caractères, alors que le log d'une
sauvegarde de plusieurs VM dépasse facilement 40 000. Ce pipeline stocke le log
complet dans Nextcloud et poste sur Discord un résumé avec un lien vers ce log.

## ⚙️ Fonctionnement

```
Proxmox VE / PBS ──webhook──▶ Jenkins ──WebDAV──▶ Nextcloud  (log complet)
                                 │
                                 └──webhook──▶ Discord  (résumé + lien)
```

1. Une tâche de sauvegarde, mise à jour, nettoyage (prune), garbage
   collection, vérification ou synchronisation se termine.
2. Proxmox envoie la notification au Generic Webhook Trigger de Jenkins.
3. Le pipeline envoie le log dans Nextcloud sous
   `<dossier>/<hôte>_<type>_<date>.log`.
4. Il poste un embed sur Discord : icône et couleur selon la sévérité, hôte,
   action, statut, titre Proxmox et lien vers le log.

| Sévérité | Message |
|----------|---------|
| `info` | ✅ Succès |
| `notice` | ℹ️ Terminé avec des remarques |
| `warning` | ⚠️ Terminé avec des avertissements |
| `error` | ❌ Échec |
| autre | ❔ Inconnu |

Si Nextcloud est injoignable, le message Discord est quand même envoyé, sans
lien, et le build Jenkins est marqué en échec.

## 📋 Prérequis

- Jenkins (LTS actuelle) avec les plugins :
  - [Pipeline](https://plugins.jenkins.io/workflow-aggregator/)
  - [Credentials Binding](https://plugins.jenkins.io/credentials-binding/)
  - [Generic Webhook Trigger](https://plugins.jenkins.io/generic-webhook-trigger/)
- Un agent Linux avec `sh`, `sed` et `curl` (le nœud intégré suffit).
- Jenkins joignable par Proxmox en **HTTPS avec un certificat reconnu par
  Proxmox** (Let's Encrypt, ou votre propre CA ajoutée sur l'hôte Proxmox).
  Le HTTP simple fonctionne mais envoie le token en clair.
- Un compte Nextcloud avec un **mot de passe d'application**.
- Un salon Discord où vous pouvez créer un webhook.

## 🚀 Installation

### 1. Nextcloud

Connectez-vous avec le compte qui stockera les logs, puis allez dans
**Paramètres > Sécurité > Appareils et sessions** et créez un mot de passe
d'application. Il fonctionne avec la double authentification et se révoque
indépendamment : n'utilisez pas le mot de passe du compte.

Le dossier (`BACKUP-LOGS` par défaut) est créé par le pipeline si besoin.

### 2. Discord

**Paramètres du serveur > Intégrations > Webhooks > Nouveau webhook**,
choisissez le salon, puis **Copier l'URL du webhook**.

### 3. Identifiants Jenkins

Dans **Administrer Jenkins > Credentials**, ajoutez :

| ID | Type | Contenu |
|----|------|---------|
| `proxmox-webhook-token` | Secret text | Un token aléatoire, par ex. `openssl rand -hex 32` |
| `nextcloud-backup-logs` | Username with password | Utilisateur Nextcloud + mot de passe d'application |
| `discord-webhook` | Secret text | L'URL du webhook Discord |

### 4. Job Jenkins

1. **Nouveau Item > Pipeline**.
2. Choisissez **Pipeline script from SCM** et pointez vers votre fork de ce
   dépôt, ou collez le [`Jenkinsfile`](Jenkinsfile) dans **Pipeline script**.
3. Modifiez le bloc `environment` en haut du Jenkinsfile : `NEXTCLOUD_URL`,
   et si besoin `NEXTCLOUD_FOLDER`, et `NOTIFY_LANG = 'fr'` pour avoir les
   messages Discord en français (voir [Réglages](#️-réglages)).
4. Lancez le job **une fois à la main** : cela enregistre le déclencheur
   webhook et les paramètres. Ce premier build échoue avec *"The notification
   body is empty"*, c'est normal.

Le déclencheur et ses variables sont déclarés dans le Jenkinsfile : rien à
configurer dans la section *Generic Webhook Trigger* du job.

### 5. Proxmox

Dans **Datacenter > Notifications** (PVE) ou **Configuration > Notifications**
(PBS) :

1. **Ajouter > Webhook** :
   - Méthode : `POST`
   - URL : `https://jenkins.example.com/generic-webhook-trigger/invoke`
   - En-têtes :
     - `Content-Type` : `application/json`
     - `Authorization` : `Bearer {{ secrets.token }}`
   - Secret : `token` = la valeur de `proxmox-webhook-token`
   - Corps :
     ```
     {
       "X_STATE": "{{ severity }}",
       "X_TYPE": "{{ fields.type }}",
       "X_HOST": "{{ fields.hostname }}",
       "X_TITLE": "{{ escape title }}",
       "X_TIMESTAMP": {{ timestamp }},
       "X_LOG_CONTENT": "{{ escape message }}"
     }
     ```
     `X_HOST` peut aussi être un nom fixe, comme `"PVE"`.

   Gardez le token dans l'en-tête : un token dans l'URL finit dans les logs
   d'accès de Jenkins et de tout reverse proxy.

2. Dans **Notification Matchers**, sélectionnez la nouvelle cible dans un
   matcher existant (ou créez-en un qui accepte tout) :

   ![Notification matcher](https://github.com/user-attachments/assets/34ebd620-b31c-4b0f-8110-31b849dca741)

3. Dans vos tâches de sauvegarde (et les autres), réglez **Mode de
   notification** sur **Système de notification**.

## 🧪 Tester

Dans les réglages de la cible Proxmox, **Test** envoie une notification
immédiatement.

Vous pouvez aussi envoyer une fausse notification depuis n'importe quelle
machine :

```bash
JENKINS_URL=https://jenkins.example.com ./tools/send-test-notification.sh warning vzdump pve1
```

Le token est lu dans `JENKINS_TOKEN`, ou demandé. Un quatrième argument permet
d'envoyer un fichier comme log. `./tools/send-test-notification.sh --help`
liste les options.

Ou bien, dans Jenkins, **Lancer un build avec des paramètres** en remplissant
`X_STATE`, `X_TYPE`, `X_HOST` et `X_LOG_CONTENT`.

Pour un test complet, lancez la sauvegarde d'un petit conteneur depuis
**Datacenter > Sauvegarde > Exécuter maintenant**.

## 🛠️ Réglages

Dans le bloc `environment` du Jenkinsfile :

| Réglage | Défaut | Description |
|---------|--------|-------------|
| `NEXTCLOUD_URL` | `https://cloud.example.com` | URL de base de Nextcloud, HTTPS uniquement |
| `NEXTCLOUD_FOLDER` | `BACKUP-LOGS` | Dossier des logs, sous-dossiers possibles (`Proxmox/Logs`) |
| `NOTIFY_LANG` | `en` | Langue des messages Discord : `en` ou `fr` |
| `NEXTCLOUD_CREDENTIALS` | `nextcloud-backup-logs` | ID de l'identifiant Nextcloud |
| `DISCORD_CREDENTIALS` | `discord-webhook` | ID de l'identifiant Discord |

L'ID de l'identifiant du token (`proxmox-webhook-token`) se règle dans le bloc
`triggers`.

## 🔒 Sécurité

- **Secrets** (mot de passe Nextcloud, webhook Discord, token du déclencheur) :
  stockés dans les identifiants Jenkins. Ils ne sont jamais envoyés par
  Proxmox, jamais stockés dans les paramètres de build, masqués dans la
  console, et transmis à `curl` sur son entrée standard plutôt que sur sa
  ligne de commande.
- **Webhook** : le déclencheur n'accepte que les requêtes avec le token, et ni
  le corps de la requête ni les variables ne sont affichés dans le log du build.
- **Entrées** : les valeurs du webhook sont filtrées (l'état, le type et l'hôte
  ne gardent que des caractères sûrs, l'horodatage que des chiffres) et ne sont
  jamais insérées dans les scripts shell : elles passent par des variables
  d'environnement ou des fichiers.
- **HTTP** : HTTPS uniquement, TLS 1.2 minimum, timeouts, nouvelles tentatives
  sur les erreurs temporaires et échec sur les erreurs HTTP.
- **Discord** : les mentions sont désactivées, un texte venant de Proxmox ne
  peut donc pas notifier `@everyone` ni personne d'autre.
- **Rétention** : les builds (dont les paramètres contiennent les logs) sont
  gardés 30 jours maximum, et le workspace est supprimé après chaque build.
- Le lien vers le log est l'URL WebDAV du fichier : l'ouvrir demande une
  connexion à Nextcloud.

## 🩺 Dépannage

| Symptôme | Cause |
|----------|-------|
| Proxmox : `certificate verify failed` | Le certificat de Jenkins n'est pas reconnu par Proxmox |
| `404` / `"triggered": false` en réponse au webhook | Mauvais token, ou le job n'a pas encore été lancé une fois |
| `401` de Nextcloud | Mauvais utilisateur ou mot de passe d'application dans `nextcloud-backup-logs` |
| `HTTP 404` à la création du dossier | Mauvaise `NEXTCLOUD_URL`, ou identifiant utilisateur différent du nom de connexion (LDAP) : utilisez l'identifiant |
| `Scripts not permitted to use ...` | Approuvez la signature dans **Administrer Jenkins > In-process Script Approval** |

## ⬆️ Mise à jour depuis la 1.x

La version 2 change le corps envoyé par Proxmox et déplace les secrets dans
Jenkins :

1. Créez les trois identifiants (voir [Identifiants Jenkins](#3-identifiants-jenkins))
   et renseignez `NEXTCLOUD_URL` dans le Jenkinsfile.
2. Dans Proxmox, remplacez le corps par le nouveau, retirez `X_FQDN`, `X_USER`,
   `X_PASSWORD` et `X_DISCORD_WEBHOOK`, supprimez les secrets `nxtPasswd` et
   `discordURL`, et envoyez le token dans `Authorization: Bearer ...` au lieu
   de l'URL.
3. Dans le job, les variables créées à la main dans *Generic Webhook Trigger*
   ne servent plus : le Jenkinsfile les déclare.
4. La branche `french` est remplacée par `NOTIFY_LANG = 'fr'`.

Les fichiers de log s'appellent maintenant `<hôte>_<type>_<date>.log`, et le
plugin Workspace Cleanup n'est plus nécessaire. Voir [CHANGELOG.md](CHANGELOG.md).

## ⚠️ Avertissement

C'est un projet personnel, fait sur mon temps libre. Lisez le Jenkinsfile
avant de l'utiliser, et testez-le d'abord avec une petite tâche.
