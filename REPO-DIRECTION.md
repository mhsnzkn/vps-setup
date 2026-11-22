# Architecture and MVP: A Terraform-like VPS management tool

I'd build this as a declarative, SSH-based VPS management platform.

The core philosophy should be:

> You own your servers. Your tool connects to them, understands their current state, and makes them match the configuration you define locally.

No cloud provider dependency, no mandatory control panel, no permanent agent, and no requirement to manually SSH into servers.

I'd design the project around three principles:

1. SSH-first: All remote operations happen over SSH.
2. Declarative: Describe what you want, not every command needed to achieve it.
3. Idempotent: Running the same command twice should not unnecessarily change anything.

Let's design this as a real software product rather than just a collection of deployment scripts.

# 1. Product definition

Working name: `VPSKit` (placeholder).

VPSKit

Proposed MVP

# Infrastructure management without the cloud complexity.

Manage multiple VPS servers from your local machine through a simple declarative configuration and CLI.

# 0

Mandatory remote agents

# 1

CLI to manage everything

# SSH

Communication protocol

# YAML

Configuration format

Target user: Developers and small teams who rent VPS servers and want the convenience of cloud infrastructure tooling without migrating to Kubernetes or using a complicated deployment platform.

# 2. Architecture

I recommend a modular monolith initially. Don't introduce microservices, a central backend, or a database server in the first version.

Developer's computer

CLI + YAML configuration + local state

SSH / SFTP

VPSKit engine

Config parser

State engine

Execution engine

Server manager

Docker manager

Security manager

Remote VPS

Ubuntu / Debian + SSH + Docker + Compose

## Recommended technology stack

| Component            | Technology                     |
| -------------------- | ------------------------------ |
| Programming language | Go                             |
| CLI framework        | Cobra                          |
| Configuration        | YAML                           |
| SSH                  | `golang.org/x/crypto/ssh`      |
| File transfer        | SFTP                           |
| Remote containers    | Docker Engine / Compose        |
| Local state          | JSON initially                 |
| Logging              | Go `slog`                      |
| Testing              | Go testing + integration tests |
| Distribution         | Single Go binary               |

Why Go?

- One executable, no runtime dependencies.
- Excellent SSH and networking ecosystem.
- Cross-platform builds for Linux, macOS and Windows.
- Good concurrency support for managing multiple VPS instances.
- Easy installation through Homebrew or downloadable binaries.

# 3. Project structure

I'd organize the Go code so each responsibility is independent from the beginning.

```
vpskit/
├── cmd/
│   └── vpskit/
│       └── main.go
│
├── internal/
│   ├── cli/
│   │   ├── root.go
│   │   ├── server.go
│   │   ├── deploy.go
│   │   ├── plan.go
│   │   ├── apply.go
│   │   └── logs.go
│   │
│   ├── config/
│   │   ├── loader.go
│   │   ├── schema.go
│   │   └── validation.go
│   │
│   ├── ssh/
│   │   ├── client.go
│   │   ├── executor.go
│   │   └── transfer.go
│   │
│   ├── provisioner/
│   │   ├── docker.go
│   │   ├── packages.go
│   │   └── users.go
│   │
│   ├── docker/
│   │   ├── compose.go
│   │   ├── images.go
│   │   └── containers.go
│   │
│   ├── state/
│   │   ├── state.go
│   │   ├── local.go
│   │   └── diff.go
│   │
│   └── deploy/
│       ├── planner.go
│       ├── executor.go
│       └── health.go
│
├── examples/
├── tests/
├── go.mod
└── README.md
```

One important architectural decision: keep SSH execution separate from the operations themselves.

For example, the Docker manager shouldn't care whether commands are executed over SSH or locally. It should use an execution interface.

```
type Executor interface {
    Run(ctx context.Context, command string) error
    Upload(ctx context.Context, src, dst string) error
    Download(ctx context.Context, src, dst string) error
}
```

That will make testing significantly easier.

# 4. Configuration design

I would avoid making the configuration overly complicated.

Start with two separate concepts:

- `vpskit.yaml`: infrastructure and server configuration.
- `docker-compose.yml`: application configuration.

This is important because you don't want to reinvent Docker Compose.

Here's a more complete example:

vpskit.yaml

```
version: "1"

project: my-api

servers:
  production:
    host: 192.168.1.100
    port: 22
    user: deploy
    identity_file: ~/.ssh/id_ed25519

    provision:
      docker: true
      firewall:
        enabled: true
        allow:
          - 22/tcp
          - 80/tcp
          - 443/tcp

applications:
  api:
    server: production

    compose:
      file: ./docker-compose.yml
      project_name: my-api

    directory: /opt/my-api

    env_file: ./.env

    healthcheck:
      url: https://example.com/health
      timeout: 60s
```

A few design rules:

- Server definitions should be reusable across projects.
- Application deployments should be independently configurable.
- Secrets should not be committed to Git.
- Configuration should be validated before making SSH connections.
- Support multiple environments without duplicating entire configurations.

I'd also eventually support separate server inventory files, but not in the first MVP.

# 5. How deployment should work internally

This is probably the most important part of the entire project.

When someone executes:

```
vpskit deploy production
```

I'd implement the following pipeline.

1. Load configuration

   Read YAML, resolve paths, validate configuration and identify the target server.
2. Connect to server

   Establish SSH connection, verify host identity and check permissions.
3. Inspect server

   Check operating system, Docker installation, Compose version, disk space and running containers.
4. Calculate deployment plan

   Determine which operations are required. Don't make changes yet.
5. Prepare deployment

   Create the remote directory, transfer Compose files and securely transfer required environment configuration.
6. Apply changes

   Execute Docker Compose operations, pull images and start or update services.
7. Verify deployment

   Check container health, service availability and configured health endpoints.
8. Save deployment state

   Record the deployment version, image digests, configuration hash and timestamp.

The CLI could display something like:

```
$ vpskit deploy production

VPSKit v0.1.0

Connecting to production ........ OK
Checking server ................. OK
Checking Docker .................. OK

Deployment plan:
  [~] api       Update image
  [=] postgres  No changes
  [+] redis     Create container

Apply changes? Yes

Pulling images .................. OK
Updating api ................... OK
Creating redis ................. OK
Checking health ................ OK

Deployment successful!

API:       https://example.com
Server:    production
Duration:  18.4s
```

I'd make `plan` and `apply` separate commands eventually, but an interactive deployment command is fine for the first version.

# 6. State management: the Terraform-inspired part

This deserves special attention.

Terraform needs state because it manages infrastructure resources. Your tool also needs state, but I wouldn't copy Terraform's entire state model.

I'd use two levels of state:

Local state

```
.vpskit/
└── state/
    └── production.json
```

Example:

```
{
  "server": "production",
  "project": "my-api",
  "last_deployment": "2026-11-07T00:00:00Z",
  "applications": {
    "api": {
      "compose_hash": "abc123",
      "image": "my-api:v1.2.0",
      "status": "running"
    }
  }
}
```

Remote state

Store a small metadata file on the VPS:

```
/var/lib/vpskit/
└── projects/
    └── my-api/
        └── state.json
```

Why both?

- Local state lets the developer inspect deployment history.
- Remote state allows the tool to understand what it manages.
- If the developer changes computers, remote metadata still exists.
- If the local state gets lost, it can be reconstructed partially from the server.

Eventually, support a remote state backend or Git-based state storage for teams.

One important distinction: state is not truth. Your tool must inspect the real server rather than blindly trusting its last recorded deployment.

# 7. The MVP scope

I'd be quite strict here. You can easily spend months building a full infrastructure platform.

Here's what I'd ship first:

| Feature                    | MVP          |
| -------------------------- | ------------ |
| Register existing VPS      | Yes          |
| SSH connection             | Yes          |
| Ubuntu/Debian support      | Yes          |
| Docker installation        | Yes          |
| Docker Compose deployment  | Yes          |
| Upload project files       | Yes          |
| Environment variables      | Yes          |
| Container status           | Yes          |
| Remote logs                | Yes          |
| Deployment history         | Yes          |
| Basic desired-state diff   | Yes          |
| Automatic HTTPS            | Later        |
| Reverse proxy management   | Later        |
| Firewall management        | Later        |
| Backups                    | Later        |
| Multi-server orchestration | Later        |
| Web dashboard              | Much later   |
| Cloud provisioning         | Out of scope |

The MVP should be able to deploy, update and inspect a Docker Compose application on an existing VPS.

That's already a useful product.

# 8. CLI design

I'd keep the CLI predictable and resource-oriented.

Here's the command structure I'd aim for:

| Command                 | Purpose                              |
| ----------------------- | ------------------------------------ |
| `vpskit init`           | Initialize a project                 |
| `vpskit server add`     | Register an existing VPS             |
| `vpskit server list`    | List registered servers              |
| `vpskit server inspect` | Inspect server configuration         |
| `vpskit setup`          | Prepare a VPS                        |
| `vpskit plan`           | Preview changes                      |
| `vpskit apply`          | Apply configuration                  |
| `vpskit deploy`         | Deploy an application                |
| `vpskit status`         | Inspect running services             |
| `vpskit logs`           | Stream remote logs                   |
| `vpskit restart`        | Restart an application               |
| `vpskit destroy`        | Remove managed application resources |

Example workflow:

```
# Initialize project
vpskit init

# Register server
vpskit server add production

# Prepare server
vpskit setup production

# Preview changes
vpskit plan

# Deploy
vpskit apply

# Check deployment
vpskit status production

# Stream logs
vpskit logs production api -f
```

I'd make `deploy` a convenient shortcut for the application deployment workflow, while `plan` and `apply` eventually become the more general infrastructure operations.

# 9. Security and reliability

There are a few things I'd consider non-negotiable, even in the MVP.

SSH security

- Verify SSH host keys; don't blindly accept unknown hosts.
- Use SSH keys rather than passwords by default.
- Never expose private keys in logs.
- Support SSH agents.

Secrets

- Never upload `.env` files accidentally through generic project synchronization.
- Explicitly configure which environment files are deployed.
- Set restrictive permissions on remote secret files.
- Never include secret values in state files or deployment logs.

Deployment safety

- Never automatically delete Docker volumes.
- Protect databases and persistent storage from accidental destruction.
- Use deployment locks to prevent concurrent deployments.
- Keep the previous deployment metadata for recovery.
- Don't blindly run destructive commands such as `docker compose down -v`.

Failure handling

Imagine the API update fails halfway through. The tool should report which operations succeeded and which failed, rather than pretending the deployment was atomic.

For the MVP, I'd prioritize reliable retries and clear failure reporting before attempting sophisticated automatic rollback.

# 10. Development roadmap

I'd build it in five phases.

1. Phase 1 — SSH foundation

   First milestone
   - Go CLI.
   - YAML configuration.
   - SSH connections.
   - Remote command execution.
   - File transfers.
   - Server inspection.
   Deliverable: connect to and inspect any supported VPS.
2. Phase 2 — Server provisioning
   - Detect Ubuntu/Debian.
   - Install Docker.
   - Configure deployment user.
   - Check prerequisites.
   - Make operations idempotent.
   Deliverable: prepare a clean VPS with one command.
3. Phase 3 — Docker Compose deployment
   - Upload Compose projects.
   - Manage environment files.
   - Pull images.
   - Start and update services.
   - Health checks and logs.
   Deliverable: deploy an application remotely.
4. Phase 4 — Desired state and history
   - Local and remote state.
   - Configuration hashing.
   - Deployment plans.
   - Change detection.
   - Deployment history.
   Deliverable: Terraform-like workflows.
5. Phase 5 — Production features
   - Reverse proxy.
   - Automatic HTTPS.
   - Backups.
   - Multiple environments.
   - Multiple VPS orchestration.
   Deliverable: a practical VPS infrastructure management platform.

# 11. What I would deliberately avoid

There are some tempting architectural decisions that I'd postpone:

- No permanent VPS agent: SSH is sufficient for this use case.
- No central API: The CLI should work independently.
- No database initially: Local JSON and remote metadata are sufficient.
- No Kubernetes: Docker Compose is the primary deployment target.
- No custom container orchestration: Delegate container lifecycle management to Docker.
- No provider-specific integrations: Your tool should work with any Linux VPS provider.

This keeps the project relatively small and gives it a clear identity.

# 12. My biggest architectural recommendation

I would make one distinction that could become a major advantage of this project:

Separate server resources from application resources.

For example:

```
# infrastructure.yaml

servers:
  production:
    host: 1.2.3.4
    user: deploy

resources:
  docker:
    server: production

  reverse_proxy:
    server: production
    provider: traefik
```

And separately:

```
# app.yaml

application:
  name: my-api
  server: production

  compose:
    file: docker-compose.yml

  domain: api.example.com
```

This separation means a developer can manage the server once and deploy 10 different applications to it without duplicating infrastructure configuration.

It also creates a path towards managing shared resources such as:

- Reverse proxies.
- Databases.
- Networks.
- Persistent volumes.
- Backups.
- Monitoring services.

Eventually, your tool could manage an entire collection of VPS servers and applications from one local project.

## 13. The first implementation milestone

If I were starting development today, I'd build this exact workflow first:

First end-to-end goal

Deploy a Docker Compose application to an existing Ubuntu VPS.

Starting with a completely clean VPS:

```
vpskit server add production
vpskit setup production
vpskit deploy production
```

Expected result:

- Docker installed automatically.
- Application files transferred.
- Environment variables configured.
- Containers running.
- Application health verified.
- Deployment state saved.

Once this works reliably, you've already built the foundation of the product.

One final thought: I wouldn't position this as another Docker deployment tool. I'd position it as an infrastructure management CLI for developers who own their servers. That's a much more interesting long-term product.

The natural next step is turning this architecture into an implementation-ready Go project, with package interfaces, configuration structs, CLI command definitions and the first working SSH deployment.

Would you like me to prepare that as the next development milestone tomorrow?

🛠️Prepare Go implementation blueprint tomorrowTap to set up
