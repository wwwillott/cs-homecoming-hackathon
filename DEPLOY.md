# Deploy Spruce (`spruce.my`)

Frontend → GitHub Pages (free) · API → Render free + Neon free · Domain → Porkbun

**Cost target: $0/month** for a hackathon / demo workload.

## Recommended stack (lowest cost)

| Piece | Service | Cost | Notes |
|-------|---------|------|-------|
| Web UI | GitHub Pages | $0 | Custom domain `spruce.my` |
| API | [Render](https://render.com) free Web Service | $0 | Sleeps after ~15m idle; ~1m cold start |
| Postgres + pgvector | [Neon](https://neon.tech) free | $0 | Better than Render free DB (that expires in 30 days) |
| DNS | Porkbun | domain only | Already owned |

Avoid Azure / Fly / Railway for now — those need credits or a card. Render free needs **no credit card**.

---

## 1. Porkbun DNS (`spruce.my`)

In Porkbun → **spruce.my** → **DNS**:

### Frontend (GitHub Pages)

| Type  | Host | Answer                | TTL |
|-------|------|-----------------------|-----|
| A     | `@`  | `185.199.108.153`     | 600 |
| A     | `@`  | `185.199.109.153`     | 600 |
| A     | `@`  | `185.199.110.153`     | 600 |
| A     | `@`  | `185.199.111.153`     | 600 |
| CNAME | `www`| `wwwillott.github.io` | 600 |

### API (after Render exists)

| Type  | Host | Answer                         | TTL |
|-------|------|--------------------------------|-----|
| CNAME | `api`| `spruce-api.onrender.com`      | 600 |

(Use the exact `*.onrender.com` hostname from the Render dashboard.)

```bash
dig +short spruce.my
dig +short www.spruce.my
dig +short api.spruce.my
```

After Pages DNS works: GitHub → **Settings → Pages → Enforce HTTPS**.

---

## 2. Frontend (GitHub Pages)

Workflow: `.github/workflows/deploy-pages.yml`

- Builds Flutter web with `ORBIT_API_URL` (repo variable → `https://api.spruce.my`)
- Publishes to Pages with `CNAME=spruce.my`

Push to `main` (or run the workflow manually) deploys the site.

---

## 3. Database — Neon (free)

1. Create a project at [neon.tech](https://neon.tech) (GitHub login is fine).
2. Open SQL editor and run: `CREATE EXTENSION IF NOT EXISTS vector;`
3. Copy the connection string and rewrite the scheme for SQLAlchemy:

```
postgresql+psycopg://USER:PASSWORD@HOST/DB?sslmode=require
```

Optional local migrate:

```bash
cd transcription-poc/backend
DATABASE_URL='postgresql+psycopg://…' uv run alembic upgrade head
```

(The container also runs `alembic upgrade head` on boot.)

---

## 4. API — Render free (no card)

Repo includes [`render.yaml`](render.yaml).

1. Sign up at [render.com](https://render.com) (GitHub OAuth).
2. **New → Blueprint** → select `wwwillott/cs-homecoming-hackathon`.
3. Apply the blueprint (`spruce-api`, free plan).
4. In the service → **Environment**, set:
   - `DATABASE_URL` = Neon URL (`postgresql+psycopg://…`)
   - `OPENAI_API_KEY` = assistant key (if you use Ask Spruce)
   - `GOOGLE_CLOUD_PROJECT` = only if Vertex transcription is configured
5. Deploy. Note the URL, e.g. `https://spruce-api.onrender.com`.
6. **Settings → Custom Domains** → add `api.spruce.my`, then add the Porkbun CNAME above.
7. Smoke test:

```bash
curl https://spruce-api.onrender.com/api/health
# after DNS:
curl https://api.spruce.my/api/health
```

**Cold starts:** first request after idle can take ~30–60s. Fine for demos; hit `/api/health` once before showing the app.

---

## 5. Point Flutter at the API

Repo variable (already set): `ORBIT_API_URL=https://api.spruce.my`

Re-run **Deploy GitHub Pages** after the API domain works.

---

## If free tiers ever block you

Cheapest always-on fallback (~$2–5/mo): Fly.io shared VM **or** Render Starter, still with Neon free for Postgres.

Azure App Service path is documented historically but skipped here — credits exhausted.
