# Hostinger SSH toolkit

Everything you need to connect to a **Hostinger** server over SSH — for both
**VPS** and **shared/cloud hosting** plans — without re-learning the quirks
(like the `65002` port) every time.

## Contents

| Path                          | What it is                                                      |
| ----------------------------- | -------------------------------------------------------------- |
| [`docs/hostinger-ssh.md`](docs/hostinger-ssh.md) | Full step-by-step guide: keys, connecting, `~/.ssh/config`, scp/rsync, troubleshooting. |
| [`scripts/hostinger-ssh.sh`](scripts/hostinger-ssh.sh) | Helper that connects (or runs a remote command) using flags, env vars, or a config file. |
| [`.hostinger.env.example`](.hostinger.env.example) | Template for your connection settings. Copy to `.hostinger.env` (git-ignored). |

## Quick start

1. **Enable SSH** in hPanel and grab your details
   (see [the guide](docs/hostinger-ssh.md#2-find-your-ssh-details-in-hpanel)).

2. **Generate and install a key:**
   ```bash
   ssh-keygen -t ed25519 -C "hostinger" -f ~/.ssh/hostinger
   # then import ~/.ssh/hostinger.pub in hPanel → SSH Access → Manage SSH keys
   ```

3. **Save your settings:**
   ```bash
   cp .hostinger.env.example .hostinger.env
   # edit .hostinger.env with your HOST / USER / PORT
   ```

4. **Connect:**
   ```bash
   ./scripts/hostinger-ssh.sh                 # interactive shell
   ./scripts/hostinger-ssh.sh -- uptime       # run a remote command
   ./scripts/hostinger-ssh.sh --vps           # VPS defaults (root@host:22)
   ./scripts/hostinger-ssh.sh --print         # print the ssh command without running it
   ```

The script needs no config file if you prefer flags or env vars:
```bash
HOSTINGER_HOST=1.2.3.4 HOSTINGER_USER=u123456789 ./scripts/hostinger-ssh.sh
```

## Key facts most people trip on

- **Shared/cloud hosting uses port `65002`**, not `22`.
- The shared-hosting **username is `uXXXXXXXXX`**, not your login email.
- SSH must be **toggled on** in hPanel for shared/cloud plans before it works.

## Security

Private keys and your real `.hostinger.env` are git-ignored. Never commit
credentials — run `git status` before every commit to be sure.
