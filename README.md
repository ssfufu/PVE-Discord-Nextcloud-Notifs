## Proxmox notifications sender via webhook, Jenkins and Nextcloud.

#### DISCLAIMER: I am NOT an expert Jenkins user, algorithmic or wrong usage of Groovy might be present in the Jenkinsfile. Also, I am doing this on my spare time and my doc writing skills may not be so good.

#### Why does this project exist ?
I have multiple backup jobs that include multiple VMs. I wanted to use the new Webhook feature in the Proxmox notifications released in v8.3. The issue is that Discord only allows up to 2000 characters in the body of the request, and my logs are actually more than 40K.
<br/><br/>

#### What does it do ?
This project allows you to send a webhook from Proxmox (PVE/PBS) when a backup/update/prune/verification/garbage-collection job is finished to a Jenkins instance, configured to run a pipeline at reception.
<br/>
The pipeline will format data, upload it as a file in a Nextcloud instance, and use a Discord webhook to send basic informations related to the Proxmox job (state, time, etc.) and the link to the file stored in Nextcloud.

---

#### Requirements:

- A Jenkins server (for installation instructions, see the sub-chapters at https://www.jenkins.io/doc/book/installing/)
- The Generic Webhook Trigger plugin in Jenkins.
- Creating the same variables in the "Generic Webhook Trigger" as in the Jenkinsfile's parameters section, in the Jenkins pipeline UI.
- Creating a token in the "Generic Webhook Trigger"
- A valid TLS certificate for the Jenkins instance if accessible via HTTPS (Proxmox won't want to use a self-signed certificate to communicate), or just a HTTP access.
- A Nextcloud instance, with a user that has no 2FA/MFA enabled. Use a strong password instead.

#### Proxmox configuration (UI Only):
- Create a new Notification target in Datacenter -> Notifications -> Notification Targets.
  - Name it (there is no nomenclature rules, it's for you).
  - Set the HTTP method to POST, and paste your URL like this :
    <br/>
    - `https://jenkins.domain.tld/generic-webhook-trigger/invoke?token={{ secrets.jkToken }}` /!\ Valid Certificate required /!\
    - `http://jenkins.domain.tld/generic-webhook-trigger/invoke?token={{ secrets.jkToken }}`
    - `https://<JenkinsIP>/generic-webhook-trigger/invoke?token={{ secrets.jkToken }}`
  - Set two headers:
    - `Content-Type : application/json`
    - `Authorization : {{ secrets.jkToken }}`
  - Paste this content in the body. Note : The content of the X_HOST variable is up to you.
    ```json
    {
      "X_STATE": "{{ severity }}",
      "X_LOG_CONTENT": "{{ escape message }}",
      "X_FQDN": "your.nextcloud.tld",
      "X_USER": "nextcloudUser",
      "X_PASSWORD": "{{ secrets.nxtPasswd }}",
      "X_DISCORD_WEBHOOK": "{{ secrets.discordURL }}",
      "X_TYPE": {{ fields.type }},
      "X_HOST": "PVE"
    }
    ```
  - Now, create those secrets in the Secrets section.
  
    What it looks like on my PVE :
    <br/>
    ![image](https://github.com/user-attachments/assets/672db57e-7ace-47fa-9608-7fc5c13b8d4f)

- In Datacenter -> Notifications -> Notification Matchers, make sure you either have one that is set to All, or create one, and SELECT the new Notification Target you just created.
  ![image](https://github.com/user-attachments/assets/34ebd620-b31c-4b0f-8110-31b849dca741)

- Finally, you just have to go to your backup jobs or whatever jobs in Proxmox, and set the Notification Mode to "Notification System".
- Now, test all of this at once, by running a backup job from Datacenter -> Backup. Select your job and click "Run now". For testing purposes, just create a job that makes a snapshot of a LXC container so it's quick. 
