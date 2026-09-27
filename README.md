# Founder Edition — Hermes + Paperclip on Railway

This is the founder version, not a generic Hermes deployment.

## Architecture

Paperclip = company/governance layer.

Hermes = Founder/CEO execution runtime.

Founder operating system:
- company charter
- founder mandate
- delegation map
- specialist roles
- operating rules
- persistent workspace/memory
- curated skill discovery

The intended operating model is:

Founder/CEO
 -> Research
 -> Product
 -> Engineering
 -> Growth
 -> Sales
 -> Finance/Ops
 -> Security

Paperclip should remain the orchestration/governance layer. Hermes is the
execution runtime.

## Railway

Create two Railway services from this repository:

1. `paperclip`
   - official Paperclip image
   - persistent volume mounted at `/paperclip`
   - public HTTPS domain
   - port `3100`

2. `founder-hermes`
   - deploy from this Dockerfile
   - persistent volume mounted at `/opt/data`
   - public/private Railway domain as appropriate
   - port `8642`

Do not expose the Hermes API without `API_SERVER_KEY`.

Set these secrets:

```text
API_SERVER_KEY=<long-random-secret>
OPENROUTER_API_KEY=<provider-key>

BETTER_AUTH_SECRET=<long-random-secret>
PAPERCLIP_TOOL_ACTION_SIGNING_SECRET=<long-random-secret>
```

## Founder state

On first boot, these files are copied to the persistent volume:

```text
/opt/data/company/SOUL.md
/opt/data/company/COMPANY.md
/opt/data/company/DELEGATION.md
/opt/data/company/FOUNDER_ROLES.md
/opt/data/company/OPERATING_RULES.md
```

This means the founder operating system survives container replacement.

## Skills

Set:

```text
INSTALL_FOUNDER_SKILLS=true
FOUNDER_SKILLS=github docker linux research browser playwright product strategy marketing sales finance
```

The bootstrap intentionally discovers skills rather than blindly installing
untrusted code.

## Local

```bash
cp .env.example .env
docker compose up --build
```

Paperclip:
http://localhost:3100

Hermes health:
http://localhost:8642/health

## Important

The exact Paperclip agent adapter configuration should be created in the
Paperclip UI/API for the installed Paperclip version. Use its Hermes gateway
adapter and point it at the Founder Hermes Railway service with the matching
API key. Do not hard-code version-sensitive Paperclip database/API internals
into this image.
