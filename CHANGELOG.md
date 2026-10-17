# Changelog

## 2.0.0

### Added
- Webhook trigger declared in the Jenkinsfile (no manual variables in the job),
  token stored in a Jenkins credential.
- Discord embeds: icon and color per severity, host, action, status, Proxmox
  title and link to the log.
- French messages (`NOTIFY_LANG = 'fr'`), replacing the `french` branch, and a
  French README.
- All PVE and PBS notification types (`vzdump`, `package-updates`,
  `replication`, `fencing`, `gc`, `prune`, `sync`, `verify`, `tape-backup`...).
- Optional notification title and Proxmox timestamp.
- Nextcloud folder created when missing, sub-folders supported.
- Discord notification still sent when the Nextcloud upload fails.
- `tools/send-test-notification.sh` to test the job without a backup.
- Lint workflow (npm-groovy-lint, ShellCheck), `.editorconfig`.

### Changed
- Secrets (Nextcloud password, Discord webhook) read from Jenkins credentials
  instead of the webhook body; Nextcloud app password recommended.
- Token sent in an `Authorization: Bearer` header instead of the URL.
- Nextcloud set with `NEXTCLOUD_URL` and `NEXTCLOUD_FOLDER` in the Jenkinsfile.
- Log files named `<host>_<type>_<date>.log`; message shows date and time.
- HTTPS only, TLS 1.2+, timeouts and retries on all HTTP calls.
- Builds kept 30 days at most, 15 minute timeout.
- `deleteDir()` instead of `cleanWs()`: Workspace Cleanup plugin no longer needed.

### Removed
- `X_FQDN`, `X_USER`, `X_PASSWORD`, `X_DISCORD_WEBHOOK` and
  `X_FORMATTED_TIMESTAMP` parameters.

### Fixed
- Nextcloud password and Discord webhook printed in the build log.
- Shell injection through webhook values interpolated into `sh` scripts.
- Invalid JSON in the documented Proxmox body (`X_TYPE` not quoted).
- Build reported as successful when Nextcloud or Discord returned an error.
- Empty logs not detected because of the default parameter value.
- `@everyone` and other mentions coming from Proxmox text pinged users.
