# Cheeblr Development Environment

Haskell/PureScript POS system with a Nix flake development environment, TLS, sops-managed secrets, and a PostgreSQL backend.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Secrets and TLS](#secrets-and-tls)
- [Commands Reference](#commands-reference)
  - [Secrets / Sops](#secrets--sops)
  - [TLS Certificates](#tls-certificates)
  - [Database](#database)
  - [Individual Services](#individual-services)
  - [Deployment](#deployment)
  - [Frontend Utilities](#frontend-utilities)
  - [Testing](#testing)
  - [Code Artifacts](#code-artifacts)
  - [Workspace](#workspace)
- [Common Workflows](#common-workflows)
- [Troubleshooting](#troubleshooting)
- [Project Structure](#project-structure)
- [NixOS Integration](#nixos-integration)

## Prerequisites

- [Nix](https://nixos.org/download.html) with flakes enabled
- Supported systems: `x86_64-linux`, `x86_64-darwin`, `aarch64-darwin`

## Getting Started

```bash
git clone <repository-url>
cd cheeblr
nix develop

# First-time secrets bootstrap
sops-init-key       # derive age key from ~/.ssh/id_ed25519
sops-bootstrap      # create secrets/cheeblr.yaml with a random DB password

# Generate and encrypt TLS certs
tls-setup           # generate mkcert dev certs
tls-sops-update     # encrypt certs into secrets/cheeblr.yaml

# Verify everything
sops-status

# Start services
pg-start
deploy              # tmux session with all services
```

## Secrets and TLS

The project uses [sops](https://github.com/getsops/sops) with age keys derived from your SSH key for secret management. Secrets live in `secrets/cheeblr.yaml` and contain the database password and TLS certificate/key. TLS is provided by [mkcert](https://github.com/FiloSottile/mkcert) for local development.

The sops workflow is:

1. `sops-init-key` — one time per machine, derives an age key from `~/.ssh/id_ed25519`
2. `sops-bootstrap` — one time per project, creates the encrypted secrets file
3. `tls-setup && tls-sops-update` — generate certs and store them in sops
4. `sops-status` — verify end-to-end at any time

**Never commit `~/.config/sops/age/keys.txt`.** Do commit `.sops.yaml` and `secrets/cheeblr.yaml`.

## Commands Reference

### Secrets / Sops

| Command | Description |
|---------|-------------|
| `sops-init-key` | Derive age key from `~/.ssh/id_ed25519` |
| `sops-pubkey` | Print this machine's age public key |
| `sops-bootstrap` | Create `secrets/cheeblr.yaml` (first-time setup) |
| `sops-get <key>` | Decrypt a single secret value to stdout |
| `sops-exec <cmd>` | Run a command with all secrets injected as env vars |
| `sops-status` | Verify sops setup end-to-end |
| `sops secrets/cheeblr.yaml` | Edit secrets directly |

### TLS Certificates

| Command | Description |
|---------|-------------|
| `tls-setup` | Generate or refresh mkcert dev certs (skips if fresh) |
| `tls-info` | Show certificate subject, SAN, and expiry |
| `tls-clean` | Remove local cert directory |
| `tls-sops-update` | Encrypt local certs into sops secrets |
| `tls-sops-extract` | Extract sops certs back to local cert path |

Certs are written to `$HOME/.local/share/cheeblr/certs/` and cover `localhost`, `127.0.0.1`, `::1`, and `192.168.8.248`.

### Database

| Command | Description |
|---------|-------------|
| `pg-start` | Initialise and start PostgreSQL |
| `pg-connect` | Open an interactive psql session |
| `pg-stop` | Stop PostgreSQL |
| `pg-cleanup` | Kill any orphaned process and wipe PGDATA |
| `pg-backup` | Dump database to `$HOME/.local/share/cheeblr/backups/` |
| `pg-restore <file>` | Restore from a backup file |
| `pg-rotate-credentials` | Generate a new random password and update the DB |
| `pg-create-schema <name>` | Create a schema and grant access |
| `pg-stats` | Show size, connections, and schema stats |

Default connection parameters (overridden at runtime by sops via `PGPASSWORD`):

- Socket: `$PGDATA` (unix socket)
- Port: `5432`
- User: your system username
- Database: `cheeblr`

### Individual Services

These start each service in the foreground in the current terminal, useful for isolated debugging.

| Command | Description |
|---------|-------------|
| `db-start` | Start PostgreSQL and tail stats with `watch` |
| `db-stop` | Backup and stop PostgreSQL |
| `backend-start` | Build and run the Haskell backend (with TLS env) |
| `backend-stop` | Kill the running backend process |
| `frontend-start` | Build and run the Vite dev server |
| `frontend-stop` | Kill the Vite process and free the port |

### Deployment

#### Source-based (cabal / spago)

| Command | Description |
|---------|-------------|
| `deploy` | Build from source and start all services in a tmux session |
| `stop` | Backup DB, kill all services, and destroy the tmux session |
| `launch-dev` | Start each service in a separate Alacritty window |

#### Nix artifact-based

| Command | Description |
|---------|-------------|
| `build-all` | `nix build .` — produces `./result/bin/cheeblr-backend` |
| `deploy-nix` | Headless deployment using Nix-built artifacts |
| `deploy-nix-interactive` | tmux deployment using Nix-built artifacts |
| `stop-nix` | Stop the Nix deployment |
| `status-nix` | Show service status and configuration |
| `cheeblr-tui` | Interactive TUI menu for all of the above |

The `deploy` tmux session layout:

```
┌─────────────────────┬─────────────────────┐
│   Backend (HTTPS)   │   Frontend (Vite)   │
├─────────────────────┼─────────────────────┤
│   pg-stats (watch)  │   Info / shell      │
└─────────────────────┴─────────────────────┘
```

Useful tmux keys: `Ctrl-b d` detach, `Ctrl-b o` next pane, `Ctrl-b z` zoom, `Ctrl-b [` scroll mode.

### Frontend Utilities

| Command | Description |
|---------|-------------|
| `vite` | Start the Vite dev server (cleans port first) |
| `vite-cleanup` | Kill any process on port 5173 |
| `spago-watch` | Watch `src/` and `test/` and recompile on change |
| `concurrent` | Run multiple commands concurrently with labels |
| `codegen` | Run PureScript codegen (`Codegen.Run`) |
| `dev` | Run codegen, then `spago-watch build` + `vite` concurrently |
| `get-ip` | Show non-loopback network addresses |
| `network-dev` | Start backend + frontend bound to LAN IP in tmux |
| `open-firewall` | Open ports 8080 and 5173 in iptables (until reboot) |

### Testing

| Command | Description |
|---------|-------------|
| `test-unit` | Haskell unit tests (`cabal test`) + PureScript unit tests (`spago test`) |
| `test-integration` | Spin up ephemeral DB + backend on port 18080, run integration suites over plain HTTP |
| `test-integration-tls` | Same as above but with TLS; also validates cert SAN and plain-HTTP rejection |
| `test-suite` | Run all three phases in sequence (unit → HTTP integration → TLS integration) |
| `test-smoke` | Hit the live backend at `https://localhost:8080` and check endpoint/JSON contract health |

`test-integration` and `test-integration-tls` manage their own ephemeral PostgreSQL instance (tmpdir, cleaned up on exit) so they can run without a live `pg-start`.

### Code Artifacts

| Command | Description |
|---------|-------------|
| `generate-manifest` | Scan source trees and write `script/manifest.json` |
| `compile-manifest` | Concatenate files listed in the manifest into timestamped output files under `script/concat_archive/output/`; skips unchanged sections |
| `compile-archive` | Full project archive ignoring the manifest — concatenates every `.hs`, `.purs`, and `.nix` file |

### Workspace

| Command | Description |
|---------|-------------|
| `code-workspace` | Open the project in VSCodium with PureScript and Haskell extensions |
| `backup-project` | rsync project files to NAS and database backups to NAS |

## Common Workflows

### First-time setup on a new machine

```bash
nix develop
sops-init-key
sops-bootstrap        # or pull existing secrets/cheeblr.yaml from the repo
tls-setup
tls-sops-update
sops-status           # should show all ✓
pg-start
deploy
```

### Daily development

```bash
nix develop
pg-start
deploy                # or: backend-start / frontend-start in separate terminals
```

### Running tests

```bash
test-unit             # fast, no services required beyond cabal/spago
test-integration      # spins up its own DB; backend must be buildable
test-suite            # all phases
test-smoke            # requires a live backend on port 8080
```

### Rotating secrets

```bash
pg-rotate-credentials         # generates new password, updates DB
sops secrets/cheeblr.yaml     # update db_password entry manually
tls-setup && tls-sops-update  # refresh certs if near expiry (30-day threshold)
```

### Backup and shutdown

```bash
stop        # backs up DB, kills services, destroys tmux session
# or individually:
pg-backup
pg-stop
backend-stop
frontend-stop
```

## Troubleshooting

### PostgreSQL won't start

```bash
pg-stop     # attempt graceful stop
pg-cleanup  # kill orphaned process and wipe PGDATA
pg-start    # reinitialise from scratch
```

### Backend won't start (TLS errors)

```bash
sops-status           # check secrets are decryptable
tls-info              # verify cert exists and covers localhost
tls-setup             # regenerate if missing or expired
```

### Port already in use

```bash
vite-cleanup          # frees port 5173
backend-stop          # kills port 8080
open-firewall         # re-opens iptables rules if connections are being dropped
```

### Stale tmux session

```bash
tmux list-sessions
tmux kill-session -t cheeblr
```

## Project Structure

```
cheeblr/
├── backend/          # Haskell/Servant backend (cabal project)
├── frontend/         # PureScript/Deku frontend (spago project)
├── nix/
│   ├── config.nix    # Single source of truth: name, ports, paths, TLS config
│   ├── build.nix     # Per-system flake outputs
│   ├── devshell.nix  # Dev shell assembly
│   ├── deploy.nix    # All deployment and service scripts
│   ├── frontend.nix  # Vite, spago-watch, codegen scripts
│   ├── postgres-utils.nix  # pg-* scripts
│   ├── test-suite.nix      # test-* scripts
│   ├── tls.nix             # TLS cert scripts and paths
│   ├── sops-dev.nix        # sops-* scripts and shell hook
│   ├── secrets.nix         # NixOS sops module
│   ├── purs-nix.nix        # PureScript dependency list
│   └── scripts/            # manifest and file-tool scripts
├── secrets/
│   └── cheeblr.yaml  # sops-encrypted secrets (safe to commit)
└── .sops.yaml        # age key configuration (safe to commit)
```

To rename the project, change `name` in `nix/config.nix` — all scripts, paths, service names, and secret file references derive from it.

## NixOS Integration

```nix
# configuration.nix
{
  imports = [
    (builtins.getFlake "github:your-username/cheeblr").nixosModules.default
  ];
}
```

This imports the PostgreSQL service NixOS module. The backend's sops secrets (`tls_cert`, `tls_key`, `db_password`) are declared in `nix/secrets.nix` and are provisioned automatically at `/run/secrets/cheeblr/` when deployed with sops-nix.