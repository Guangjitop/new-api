<div align="center">

![new-api](/web/public/logo.png)

# New API - Private Commercial Edition

Enterprise-grade LLM Gateway and AI Asset Management Platform for private deployment.

<p align="center">
  <strong>Private / Commercial / Self-Hosted</strong>
</p>

<p align="center">
  <a href="#-project-positioning">Project Positioning</a> •
  <a href="#-quick-start">Quick Start</a> •
  <a href="#-core-capabilities">Core Capabilities</a> •
  <a href="#-deployment-and-operations">Deployment & Ops</a> •
  <a href="#-license-and-commercial-terms">License</a>
</p>

</div>

## Project Positioning

This repository is maintained as a **private commercial project** for enterprise scenarios.

- Internal delivery: supports private cloud / on-prem deployment
- Commercial operation: supports account systems, billing, channels, and cost governance
- Security baseline: token management, permission isolation, operation audit, and access control
- Availability baseline: high-availability deployment through external DB + Redis + horizontal scaling

> Important
> - This project is not a public community distribution.
> - Any external distribution, sublicensing, or secondary resale must be explicitly authorized in writing.
> - If your delivery includes third-party open-source components, you must comply with their licenses and attribution requirements.

---

## Quick Start

### Option A: Deploy from private image (recommended)

```bash
docker run --name new-api -d --restart always \
  -p 3000:3000 \
  -e TZ=Asia/Shanghai \
  -e SESSION_SECRET="replace-with-a-strong-random-value" \
  -e CRYPTO_SECRET="replace-with-a-strong-random-value" \
  -e SQL_DSN="postgres://user:password@db-host:5432/newapi?sslmode=disable" \
  -e REDIS_CONN_STRING="redis://redis-host:6379/0" \
  -v /opt/new-api/data:/data \
  registry.example.com/ai/new-api:latest
```

### Option B: Deploy from private source repository

```bash
git clone git@your-git-host:your-org/new-api.git
cd new-api
cp docker-compose.example.yml docker-compose.yml
# Edit docker-compose.yml and env files
docker compose up -d
```

After startup, open `http://<your-host>:3000`.

---

## Core Capabilities

- Unified API gateway for multiple model providers
- Channel routing, weighted traffic, retries, and graceful fallback
- Token grouping, model-level quotas, and per-user limits
- Multi-tenant account system and role-based permissions
- Real-time cost accounting, reconciliation-friendly billing records
- Dashboard for traffic, token usage, and financial metrics

---

## Deployment And Operations

### Recommended production architecture

- Stateless app nodes: scale horizontally behind load balancer
- Persistent stores: PostgreSQL or MySQL for metadata and bills
- Redis: cache, locks, and distributed runtime coordination
- Observability: enable metrics, error logs, and audit trails

### Minimum production env checklist

- `SESSION_SECRET`: required for stable sessions in multi-node deployments
- `CRYPTO_SECRET`: required when Redis/shared encrypted data is enabled
- `SQL_DSN`: database DSN (PostgreSQL/MySQL)
- `REDIS_CONN_STRING`: Redis connection string
- `ERROR_LOG_ENABLED=true`: enable error diagnostics
- Reverse proxy TLS enabled (Nginx/Caddy/ALB)

### Security baseline

- Rotate API keys and admin credentials regularly
- Restrict admin panel by IP, VPN, or SSO
- Enable least-privilege database accounts
- Configure request body limits and streaming timeouts
- Run regular backup and restore drills

---

## Commercialization Checklist

Before external customer delivery, confirm:

1. Brand assets are replaced with your company identity.
2. Public community links are removed or redirected to your support portal.
3. Billing rules match your contract and local tax/compliance requirements.
4. SLA, incident response, and on-call process are documented.
5. Privacy policy, data retention policy, and customer terms are published.

---

## Support And Maintenance

- Recommended release strategy: staging verification, then phased production rollout
- Recommended update cadence: security patches first, feature releases on schedule
- Suggested support model: L1 operations, L2 engineering, L3 architecture escalation

Contact points (replace with your own):

- Business: `biz@your-company.com`
- Technical support: `support@your-company.com`
- Security issues: `security@your-company.com`

---

## License And Commercial Terms

This repository is distributed under a **private commercial license**.

- Copyright: Your Company / Authorized Maintainer
- Allowed: internal deployment, contracted delivery within license scope
- Not allowed without written authorization: public redistribution, resale, source relicensing

If you rely on third-party open-source components, keep their license notices and fulfill corresponding obligations.

---

## Changelog Policy

For commercial delivery, maintain at least:

- Version number and release date
- Changed features/fixes
- Upgrade impact and rollback notes
- Security-related updates
