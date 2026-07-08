# Deploying to Hostinger

This repository deploys automatically to a Hostinger server via the GitHub Actions
workflow in `.github/workflows/deploy-hostinger.yml`. Every push to `main` syncs the
repository contents to the server with `rsync` over SSH. You can also trigger a deploy
manually from the **Actions** tab (the workflow has a `workflow_dispatch` trigger).

## One-time setup

### 1. Enable SSH on Hostinger

1. Log in to [hPanel](https://hpanel.hostinger.com).
2. Go to **Websites → Manage → Advanced → SSH Access** and enable SSH.
3. Note the connection details shown there:
   - **Host / IP** (e.g. `123.45.67.89`)
   - **Port** — usually `65002` on shared hosting, `22` on a VPS
   - **Username** — e.g. `u123456789`

### 2. Create a deploy SSH key

On your own machine, generate a dedicated key pair (no passphrase):

```bash
ssh-keygen -t ed25519 -f hostinger_deploy -C "github-actions-deploy" -N ""
```

Add the **public** key (`hostinger_deploy.pub`) to the server. In hPanel:
**Advanced → SSH Access → Manage SSH keys → Add SSH key**, or append it manually:

```bash
ssh -p 65002 u123456789@YOUR_HOST 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys' < hostinger_deploy.pub
```

Verify key-based login works before continuing:

```bash
ssh -p 65002 -i hostinger_deploy u123456789@YOUR_HOST
```

### 3. Add GitHub repository secrets

In the GitHub repo, go to **Settings → Secrets and variables → Actions → New repository
secret** and add:

| Secret | Value |
| --- | --- |
| `HOSTINGER_HOST` | Server IP or hostname from hPanel |
| `HOSTINGER_PORT` | `65002` (shared hosting) or `22` (VPS) |
| `HOSTINGER_USER` | Your SSH username, e.g. `u123456789` |
| `HOSTINGER_SSH_KEY` | The **private** key — full contents of the `hostinger_deploy` file |
| `HOSTINGER_TARGET_DIR` | Target path on the server, e.g. `domains/yourdomain.com/public_html` |

The private key never leaves GitHub's encrypted secret store; keep the local copy safe
or delete it after adding the secret.

## How the deploy behaves

- `rsync --delete` makes the target directory **mirror the repository**: files that
  exist on the server but not in the repo are removed. If your site has
  server-generated content (uploads, caches, `.htaccess` managed on the server), add
  `--exclude` rules for those paths in the workflow before pointing it at a live
  directory.
- `.git` and `.github` are excluded from upload.
- Concurrent deploys are serialized; a newer push cancels an in-progress deploy.

## Manual connection (from your machine)

```bash
ssh -p 65002 u123456789@YOUR_HOST
```
