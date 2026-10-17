# 🔔 PVE Discord Nextcloud Notifs

> Send Proxmox VE and Proxmox Backup Server notifications to Discord, with the
> full log stored in Nextcloud, through a Jenkins pipeline.
>
> Supported: **Proxmox VE 8.3+** and **Proxmox Backup Server 3.3+** (webhook
> notification targets). 🇫🇷 [Version française](README.fr.md)

## 📖 Table of contents

- [Why](#-why)
- [How it works](#️-how-it-works)
- [Requirements](#-requirements)
- [Setup](#-setup)
- [Testing](#-testing)
- [Settings](#️-settings)
- [Security model](#-security-model)
- [Troubleshooting](#-troubleshooting)
- [Upgrading from 1.x](#️-upgrading-from-1x)
- [Disclaimer](#️-disclaimer)

## 💡 Why

Proxmox can send notifications to a webhook since VE 8.3, but a Discord message
is limited to 2000 characters, while the log of a backup job with several VMs
easily exceeds 40,000. This pipeline stores the full log in Nextcloud and posts
a short summary with a link to it on Discord.

## ⚙️ How it works

```
Proxmox VE / PBS ──webhook──▶ Jenkins ──WebDAV──▶ Nextcloud  (full log)
                                 │
                                 └──webhook──▶ Discord  (summary + link)
```

1. A backup, update, prune, garbage collection, verification or sync job ends.
2. Proxmox posts the notification to the Generic Webhook Trigger of Jenkins.
3. The pipeline uploads the log to Nextcloud as
   `<folder>/<host>_<type>_<date>.log`.
4. It posts an embed on Discord: icon and color by severity, host, action,
   status, Proxmox title and a link to the log.

| Severity | Message |
|----------|---------|
| `info` | ✅ Success |
| `notice` | ℹ️ Completed with notices |
| `warning` | ⚠️ Completed with warnings |
| `error` | ❌ Failure |
| other | ❔ Unknown |

If Nextcloud cannot be reached, the Discord message is still sent, without the
link, and the Jenkins build is marked as failed.

## 📋 Requirements

- Jenkins (current LTS) with these plugins:
  - [Pipeline](https://plugins.jenkins.io/workflow-aggregator/)
  - [Credentials Binding](https://plugins.jenkins.io/credentials-binding/)
  - [Generic Webhook Trigger](https://plugins.jenkins.io/generic-webhook-trigger/)
- A Linux agent with `sh`, `sed` and `curl` (the built-in node is fine).
- Jenkins reachable by Proxmox over **HTTPS with a certificate Proxmox trusts**
  (Let's Encrypt or your own CA added to the Proxmox host). Plain HTTP works but
  sends the token in clear text.
- A Nextcloud account with an **app password**.
- A Discord channel where you can create a webhook.

## 🚀 Setup

### 1. Nextcloud

Log in with the account that will store the logs, then open
**Settings > Security > Devices & sessions** and create an app password.
App passwords work with two-factor authentication and can be revoked on their
own: do not use the account password.

The folder (`BACKUP-LOGS` by default) is created by the pipeline if needed.

### 2. Discord

**Server settings > Integrations > Webhooks > New webhook**, choose the
channel, then **Copy webhook URL**.

### 3. Jenkins credentials

In **Manage Jenkins > Credentials**, add:

| ID | Kind | Content |
|----|------|---------|
| `proxmox-webhook-token` | Secret text | A random token, e.g. `openssl rand -hex 32` |
| `nextcloud-backup-logs` | Username with password | Nextcloud user + app password |
| `discord-webhook` | Secret text | The Discord webhook URL |

### 4. Jenkins job

1. **New Item > Pipeline**.
2. Either choose **Pipeline script from SCM** and point it to your fork of this
   repository, or paste the [`Jenkinsfile`](Jenkinsfile) in **Pipeline script**.
3. Edit the `environment` block at the top of the Jenkinsfile:
   `NEXTCLOUD_URL`, and optionally `NEXTCLOUD_FOLDER` and `NOTIFY_LANG`
   (see [Settings](#️-settings)).
4. Run the job **once by hand**: this registers the webhook trigger and the
   parameters. This first build fails with *"The notification body is empty"*,
   which is expected.

The trigger and its variables are declared in the Jenkinsfile: nothing has to
be configured in the job's *Generic Webhook Trigger* section.

### 5. Proxmox

In **Datacenter > Notifications** (PVE) or **Configuration > Notifications**
(PBS):

1. **Add > Webhook**:
   - Method: `POST`
   - URL: `https://jenkins.example.com/generic-webhook-trigger/invoke`
   - Headers:
     - `Content-Type`: `application/json`
     - `Authorization`: `Bearer {{ secrets.token }}`
   - Secret: `token` = the value of `proxmox-webhook-token`
   - Body:
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
     `X_HOST` can also be a fixed name, such as `"PVE"`.

   Keep the token in the header: a token in the URL ends up in the access logs
   of Jenkins and of any reverse proxy.

2. In **Notification Matchers**, select the new target in an existing matcher
   (or create one matching everything):

   ![Notification matcher](https://github.com/user-attachments/assets/34ebd620-b31c-4b0f-8110-31b849dca741)

3. In your backup jobs (and other jobs), set **Notification mode** to
   **Notification system**.

## 🧪 Testing

From the target settings in Proxmox, **Test** sends a notification right away.

You can also send a fake notification from any machine:

```bash
JENKINS_URL=https://jenkins.example.com ./tools/send-test-notification.sh warning vzdump pve1
```

The token is read from `JENKINS_TOKEN` or asked for. Any file can be sent as
the log with a fourth argument. `./tools/send-test-notification.sh --help`
lists the options.

Or, in Jenkins, **Build with Parameters** and fill in `X_STATE`, `X_TYPE`,
`X_HOST` and `X_LOG_CONTENT`.

For a full run, start a backup of a small container from
**Datacenter > Backup > Run now**.

## 🛠️ Settings

In the `environment` block of the Jenkinsfile:

| Setting | Default | Description |
|---------|---------|-------------|
| `NEXTCLOUD_URL` | `https://cloud.example.com` | Base URL of Nextcloud, HTTPS only |
| `NEXTCLOUD_FOLDER` | `BACKUP-LOGS` | Folder of the logs, sub-folders allowed (`Proxmox/Logs`) |
| `NOTIFY_LANG` | `en` | Language of the Discord messages: `en` or `fr` |
| `NEXTCLOUD_CREDENTIALS` | `nextcloud-backup-logs` | ID of the Nextcloud credential |
| `DISCORD_CREDENTIALS` | `discord-webhook` | ID of the Discord credential |

The ID of the token credential (`proxmox-webhook-token`) is set in the
`triggers` block.

## 🔒 Security model

- **Secrets** (Nextcloud password, Discord webhook, trigger token) live in the
  Jenkins credentials store. They are never sent by Proxmox, never stored in
  build parameters, masked in the console and given to `curl` on stdin rather
  than on its command line.
- **Webhook**: the trigger only accepts requests with the token, and neither
  the request body nor the resolved variables are printed in the build log.
- **Inputs** from the webhook are filtered (state, type and host keep only safe
  characters, the timestamp only digits) and are never interpolated into shell
  scripts: they are passed as environment variables or written to files.
- **HTTP**: HTTPS only, TLS 1.2 or newer, timeouts, retries on transient errors
  and failure on HTTP errors.
- **Discord**: mentions are disabled, so text coming from Proxmox cannot ping
  `@everyone` or anybody else.
- **Retention**: builds (whose parameters contain the logs) are kept 30 days
  at most, and the workspace is deleted after each build.
- The log link uses the WebDAV URL of the file: opening it requires a login to
  Nextcloud.

## 🩺 Troubleshooting

| Symptom | Cause |
|---------|-------|
| Proxmox: `certificate verify failed` | The Jenkins certificate is not trusted by Proxmox |
| `404` / `"triggered": false` from the webhook | Wrong token, or the job has not run once yet |
| `401` from Nextcloud | Wrong user or app password in `nextcloud-backup-logs` |
| `HTTP 404` when creating the folder | Wrong `NEXTCLOUD_URL`, or user ID different from the login name (LDAP): use the user ID |
| `Scripts not permitted to use ...` | Approve the signature in **Manage Jenkins > In-process Script Approval** |

## ⬆️ Upgrading from 1.x

Version 2 changes the Proxmox body and moves the secrets to Jenkins:

1. Create the three credentials (see [Jenkins credentials](#3-jenkins-credentials))
   and set `NEXTCLOUD_URL` in the Jenkinsfile.
2. In Proxmox, replace the body with the new one, remove `X_FQDN`, `X_USER`,
   `X_PASSWORD` and `X_DISCORD_WEBHOOK`, delete the `nxtPasswd` and
   `discordURL` secrets, and send the token in `Authorization: Bearer ...`
   instead of the URL.
3. In the job, the variables previously created by hand in *Generic Webhook
   Trigger* are no longer needed: the Jenkinsfile declares them.
4. The `french` branch is replaced by `NOTIFY_LANG = 'fr'`.

Log files are now named `<host>_<type>_<date>.log`, and the Workspace Cleanup
plugin is no longer needed. See [CHANGELOG.md](CHANGELOG.md).

## ⚠️ Disclaimer

This is a personal project, made on my spare time. Read the Jenkinsfile before
using it, and test it with a small job first.
