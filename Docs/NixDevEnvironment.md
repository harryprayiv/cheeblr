# Cheeblr Development Environment

This document describes the Nix-based development environment for the Cheeblr project.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Environment Components](#environment-components)
  - [Database](#database)
  - [Frontend](#frontend)
  - [Development Tools](#development-tools)
  - [Deployment](#deployment)
  - [Code Artifacts](#code-artifacts)
- [Common Workflows](#common-workflows)
- [Network Development](#network-development)
- [Troubleshooting](#troubleshooting)
- [Project Structure](#project-structure)
- [NixOS Integration](#nixos-integration)

## Overview

Cheeblr is a project built with a Haskell backend and PureScript frontend. The development environment is managed through Nix flakes, providing a reproducible and consistent setup across different machines and operating systems.

## Prerequisites

- [Nix package manager](https://nixos.org/download.html) with flakes enabled
- Supported operating systems:
  - Linux (x86_64)
  - macOS (Intel or Apple Silicon)

## Getting Started

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd cheeblr
   ```

2. Enter the development shell:
   ```bash
   nix develop
   ```

3. Start the PostgreSQL database:
   ```bash
   pg-start
   ```

4. Start the development environment:
   ```bash
   dev
   ```

## Environment Components

### Database

The project uses PostgreSQL for data storage. The following commands are available to manage the database:

| Command | Description |
|---------|-------------|
| `pg-start` | Start the PostgreSQL server |
| `pg-connect` | Connect to the PostgreSQL server with an interactive CLI |
| `pg-stop` | Stop the PostgreSQL server |
| `pg-cleanup` | Clean up PostgreSQL data directory |
| `pg-backup` | Create a backup of the database |
| `pg-restore <file>` | Restore a backup of the database |
| `pg-rotate-credentials` | Change database credentials |
| `pg-create-schema <name>` | Create database schema |
| `pg-stats` | Show database statistics |

The PostgreSQL data is stored in `$HOME/.local/share/cheeblr/postgres`. The default connection parameters are:

- Port: 5432
- User: Your system username
- Password: "postgres"
- Database: "cheeblr"

### Frontend

The frontend is built with PureScript. The following commands are available for frontend development:

| Command | Description |
|---------|-------------|
| `vite` | Start the Vite dev server |
| `vite-cleanup` | Clean up Vite build artifacts |
| `spago-watch` | Watch PureScript files and recompile on changes |
| `concurrent` | Run multiple commands concurrently |
| `dev` | Start the full development environment |
| `network-dev` | Start development server on network address for cross-device testing |
| `get-ip` | Display the machine's network IP addresses |

### Development Tools

The environment includes various development tools:

- **Haskell**: GHC, Cabal, HLS, Fourmolu, HLint
- **PureScript**: PureScript compiler, Spago, PureScript Language Server, PureScript ES backend, PureScript tidy
- **JavaScript/Node.js**: Node.js 20, esbuild
- **Database**: PostgreSQL, pgcli, pgadmin4
- **Editors**: VSCodium (via `code-workspace` command)
- **Other**: tmux, rsync, nixpkgs-fmt, toilet (for ASCII art)

### Deployment

The environment includes deployment tools:

| Command | Description |
|---------|-------------|
| `deploy` | Deploy the application and start services in tmux |
| `withdraw` | Back up data, stop services and clean up resources |

The `deploy` command sets up a tmux session with the following panes:
- Backend service
- Frontend Vite server
- Database statistics monitor
- Interactive shell

This allows for convenient management of all services during deployment.

### Code Artifacts

The environment includes tools for code management and archiving:

| Command | Description |
|---------|-------------|
| `backup-project` | Backup project files and database |
| `compile-archive` | Compile and concatenate project files into archive format |

## Common Workflows

### Start Development Session

```bash
nix develop  # Enter the dev environment
pg-start     # Start the database
dev          # Start the development servers
```

### Database Management

```bash
pg-connect    # Connect to database with CLI
pg-backup     # Create a backup
pg-restore <file>  # Restore from backup
```

### Backup Project

```bash
backup-project  # Backup project files and database
```

This will:
- Copy project files to `~/NAS/plutus/workspace/scdWs/cheeblr/`
- Copy database backups to `~/NAS/plutus/cheeblrDB/`

### Open in VSCodium

```bash
code-workspace  # Open the project in VSCodium
```

### Using deploy/withdraw

The deploy and withdraw commands manage the complete application lifecycle:

```bash
deploy    # Start all services in tmux
withdraw  # Create a backup and stop all services
```

## Network Development

For testing across multiple devices on the same network:

```bash
get-ip         # Find your network IP address
network-dev    # Start services with network address binding
```

The `network-dev` command automatically configures the frontend to be accessible from other devices on your network.

## Troubleshooting

### Database Issues

If you encounter issues with the PostgreSQL server:

1. Stop the server: `pg-stop`
2. Clean up: `pg-cleanup`
3. Start again: `pg-start`
4. Create schema: `pg-create-schema <name>`

### Frontend Issues

For frontend build issues:

1. Clean up Vite artifacts: `vite-cleanup`
2. Restart development: `dev`

### TMux Session Management

If tmux sessions from previous runs are still active:

```bash
tmux list-sessions    # List active sessions
tmux kill-session -t cheeblr  # Kill the cheeblr session
```

## Project Structure

The project is structured with:

- Haskell backend (using the Cardano ecosystem given dependencies like CHaP and iohkNix)
- PureScript frontend (with Vite for development)
- PostgreSQL database
- Nix-based configuration for reproducible development and deployment

The project uses several important inputs:
- iogx: Input-Output Global extensions for Nix
- nixpkgs: The Nix packages collection
- iohkNix: Input-Output Hong Kong Nix tools
- hackage and CHaP: Haskell package repositories
- purescript-overlay: PureScript tools for Nix
- flake-utils and flake-compat: Utility packages for Nix flakes

## NixOS Integration

This project includes NixOS modules that can be imported in your NixOS configuration:

```nix
# configuration.nix
{ pkgs, ... }:
{
  imports = [ 
    (builtins.getFlake "github:your-username/cheeblr").nixosModules.default
  ];
}
```

This will import the PostgreSQL service configuration for your system.

The PostgreSQL service is configured with:

- Authentication set to 'trust' for local connections
- Performance settings appropriate for development
- Logging enabled for debugging
- User creation and database initialization