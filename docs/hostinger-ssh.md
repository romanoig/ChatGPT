# Connecting to Hostinger over SSH

A practical, end-to-end guide to enabling and using SSH access on Hostinger,
covering both **VPS** plans and **Web / Shared Hosting** plans. It walks through
finding your credentials, generating and installing an SSH key, connecting, and
troubleshooting the errors people actually hit.

> Nothing in this repository contains real credentials. Replace every
> placeholder (`USER`, `HOST`, `PORT`, paths) with the values from your own
> hPanel before running anything.

---

## 1. Which plan do you have?

Hostinger exposes SSH differently depending on the product:

| Plan type            | SSH enabled by default | Where you get details          | Typical user           | Typical port |
| -------------------- | ---------------------- | ------------------------------ | ---------------------- | ------------ |
| **VPS**              | Yes (root)             | hPanel → VPS → *your server*   | `root`                 | `22`         |
| **Cloud / Business** | Must be turned on      | hPanel → Hosting → SSH Access  | `uXXXXXXXXX`           | `65002`      |
| **Shared / Premium** | Must be turned on      | hPanel → Hosting → SSH Access  | `uXXXXXXXXX`           | `65002`      |

Two things surprise people the most:

1. On **shared/cloud hosting**, the SSH port is **`65002`**, *not* `22`.
2. On **shared/cloud hosting**, the username is not your email — it is the
   account handle that looks like `u123456789`.

---

## 2. Find your SSH details in hPanel

### VPS
1. Log in to <https://hpanel.hostinger.com>.
2. Open **VPS** and select your server.
3. The **Overview** tab shows the **SSH IP address**, **username** (`root`), and
   port (`22`). You set the root password when the VPS was created; you can
   reset it under **Settings → Root password**.

### Shared / Cloud Hosting
1. Log in to <https://hpanel.hostinger.com>.
2. Open **Websites → (your site) → Dashboard**, or **Hosting**.
3. In the sidebar go to **Advanced → SSH Access**.
4. Toggle **SSH access** on if it is disabled.
5. Note the four values shown:
   - **SSH IP** (the host)
   - **SSH port** — usually `65002`
   - **SSH username** — `uXXXXXXXXX`
   - Password = your hosting account password.

---

## 3. Generate an SSH key (recommended over passwords)

Key-based auth is more secure and lets you skip typing a password every time.

```bash
# ed25519 is preferred; use rsa -b 4096 only if the server is very old.
ssh-keygen -t ed25519 -C "hostinger" -f ~/.ssh/hostinger
```

This creates:
- `~/.ssh/hostinger`      → **private** key (never share, never commit)
- `~/.ssh/hostinger.pub`  → **public** key (safe to upload)

### Install the public key

**VPS** — easiest with `ssh-copy-id`:
```bash
ssh-copy-id -i ~/.ssh/hostinger.pub -p 22 root@YOUR_VPS_IP
```

Or paste the key in hPanel: **VPS → Settings → SSH Keys → Add SSH Key**, then
paste the contents of `~/.ssh/hostinger.pub`.

**Shared / Cloud** — use hPanel:
1. **Advanced → SSH Access → Manage SSH keys → Import SSH Key**.
2. Paste the contents of `~/.ssh/hostinger.pub`.

Or from the terminal (note the port):
```bash
ssh-copy-id -i ~/.ssh/hostinger.pub -p 65002 uXXXXXXXXX@YOUR_SSH_IP
```

---

## 4. Connect

### VPS
```bash
ssh -i ~/.ssh/hostinger root@YOUR_VPS_IP
```

### Shared / Cloud (note the port!)
```bash
ssh -i ~/.ssh/hostinger -p 65002 uXXXXXXXXX@YOUR_SSH_IP
```

---

## 5. Save yourself the typing: `~/.ssh/config`

Add a host entry so you can connect with a short alias and never remember the
port again.

```sshconfig
# ~/.ssh/config

Host hostinger
    HostName YOUR_SSH_IP
    User uXXXXXXXXX
    Port 65002
    IdentityFile ~/.ssh/hostinger
    IdentitiesOnly yes
    ServerAliveInterval 60

# For a VPS instead:
Host hostinger-vps
    HostName YOUR_VPS_IP
    User root
    Port 22
    IdentityFile ~/.ssh/hostinger
    IdentitiesOnly yes
    ServerAliveInterval 60
```

Then simply:
```bash
ssh hostinger        # shared/cloud
ssh hostinger-vps    # vps
```

`ServerAliveInterval 60` keeps the connection from dropping when idle.

---

## 6. Common tasks over SSH

```bash
# Copy a local file up to the server (shared hosting, port 65002):
scp -P 65002 ./build.zip uXXXXXXXXX@YOUR_SSH_IP:~/public_html/

# Copy a file down from the server:
scp -P 65002 uXXXXXXXXX@YOUR_SSH_IP:~/backup.sql ./

# Sync a directory up (fast, incremental). With a ~/.ssh/config alias:
rsync -avz --delete ./dist/ hostinger:~/public_html/

# rsync without an alias needs the port passed to ssh:
rsync -avz -e "ssh -p 65002" ./dist/ uXXXXXXXXX@YOUR_SSH_IP:~/public_html/

# Run a one-off remote command without an interactive shell:
ssh hostinger 'cd ~/public_html && php artisan migrate --force'
```

---

## 7. Troubleshooting

| Symptom                                             | Likely cause & fix                                                                                             |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `Connection refused` / `Connection timed out`       | Wrong port. Shared hosting uses **65002**, not 22. Also confirm SSH is toggled **on** in hPanel.              |
| `Permission denied (publickey)`                     | Public key not installed for this user, or wrong `IdentityFile`. Re-import the `.pub` in hPanel.              |
| `Permission denied (password)` on shared hosting    | Use the **hosting account** password (the `uXXXXXXXXX` one), not your Hostinger *login* email password.       |
| `Too many authentication failures`                  | Your agent is offering many keys. Add `IdentitiesOnly yes` and `-i ~/.ssh/hostinger` to force the right one.  |
| `REMOTE HOST IDENTIFICATION HAS CHANGED`            | Server was rebuilt/reinstalled. Remove the stale entry: `ssh-keygen -R "[YOUR_SSH_IP]:65002"`.                |
| `WARNING: UNPROTECTED PRIVATE KEY FILE`             | Fix permissions: `chmod 600 ~/.ssh/hostinger`.                                                                 |
| Works from one network, not another                 | Some ISPs/firewalls block outbound `65002`. Try from another network or contact Hostinger support.            |
| Key ignored, still asks for password                | `chmod 700 ~/.ssh && chmod 600 ~/.ssh/hostinger`; check `~/.ssh/config` points to the right `IdentityFile`.   |

Verbose output is your friend when a connection fails — it shows exactly which
key is offered and where auth breaks:
```bash
ssh -vvv -p 65002 uXXXXXXXXX@YOUR_SSH_IP
```

---

## 8. Security notes

- **Never commit private keys.** The `.gitignore` in this repo blocks the usual
  key filenames, but always double-check `git status` before committing.
- Prefer keys over passwords, and disable password auth on a VPS once keys work
  (`/etc/ssh/sshd_config`: `PasswordAuthentication no`, then
  `systemctl restart ssh`).
- On a VPS, consider changing the default SSH port and installing `fail2ban` to
  cut down on brute-force noise.
- Keep your private key passphrase-protected and load it with `ssh-agent`.

---

## 9. Quick reference

```
VPS            ssh root@HOST                          (port 22)
Shared/Cloud   ssh -p 65002 uXXXXXXXXX@HOST           (port 65002)
Copy up        scp -P 65002 file  user@HOST:~/path/
Copy down      scp -P 65002 user@HOST:~/file  ./
Sync           rsync -avz -e "ssh -p 65002" ./dir/ user@HOST:~/path/
Fix host key   ssh-keygen -R "[HOST]:65002"
Debug          ssh -vvv -p 65002 user@HOST
```
