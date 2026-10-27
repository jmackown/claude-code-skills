---
name: vuln-scan
description: Scan the current repo for known vulnerabilities in its Python dependencies (uv.lock, via pip-audit and OSV, cross-checked against open GitHub Dependabot alerts) and its Docker image (Trivy, locally, no Docker Hub or Docker Scout needed), compare with the last scan, and report a triaged table of packages, CVEs, severities, fixes and real exposure. Use when the user says "vuln scan", "/vuln-scan", "security scan", "any vulnerabilities", "CVEs we should patch", "scan the docker image", or asks what dependencies need upgrading for security.
---

# vuln-scan

Find known vulnerabilities in the repo, judge which ones matter for how the service actually runs, and report a decision-ready list. Investigation only.

## Rules

- Read-only on the repo: no lockfile changes, no `pyproject.toml` edits, no branches, no commits. Recommend the fix; the user decides.
- Never install tools without asking. The script runs Trivy through Docker when the `trivy` binary is missing.
- Don't print secrets. The `--image` build reads a GCP token into an env var only.

## Steps

### 1. Run the scan

From inside the repo:

```bash
~/.claude/skills/vuln-scan/scan.sh            # deps + final-stage base image (about 1 minute)
~/.claude/skills/vuln-scan/scan.sh --image    # also build and scan the real final image (slow: 10+ minutes)
```

Use plain mode by default. Use the image mode when the user asks to scan the deployed or built image, or when the base image scan can't explain a finding. Run it in the background.

If the repo has `docs/security/vulnerability-log.md`, read its latest entry before triage. Mark findings already recorded there as "already recorded", and flag any "Revisit when" condition that is now met.

The script stays personal. Don't propose adding it to a repo or to CI unless the user raises it.

### 1b. Cross-check against Dependabot

GitHub Dependabot reads every manifest in the repo, not only `uv.lock`, so it can report findings this scan doesn't. If your alerting runs off Dependabot, those findings still page you. Pull its open alerts:

```bash
gh api "repos/{owner}/{repo}/dependabot/alerts?state=open&per_page=100" \
  --jq '.[] | [.number, .security_advisory.severity, .dependency.package.name, .dependency.manifest_path, .security_vulnerability.first_patched_version.identifier, .security_advisory.cve_id] | @tsv'
```

Also list manifests other than `uv.lock`: `rg --files -g 'requirements*.txt' -g 'poetry.lock' -g 'Pipfile*' -g 'setup.py' -g 'package*.json' | head`.

For each Dependabot alert the scan didn't report, give the reason:

- **Stale manifest:** the alert's `manifest_path` is a file nothing installs from (check with `git grep -n <file> -- . ':!uv.lock'`). Recommend deleting the file.
- **Newer advisory:** published after the advisory database the scan used. Treat it as a normal finding.
- **Accepted risk:** already recorded as not fixed in the vulnerability log. The bot keeps counting it until the alert is dismissed in GitHub, so recommend dismissing it as "tolerable risk" with a link to the log entry. Dismissing writes to GitHub, so only do it when the user says so.

Add a **Dependabot only** table to the report for these.

Without `trivy` it runs Trivy in Docker. Without either, it skips the image scan and still reports the Python results. It writes to `~/.claude/vuln-scans/<repo>/<YYYY-MM-DD>/`:

| File | Contents |
|---|---|
| `python.tsv` | severity, package, installed, fixed, GHSA id, CVE, prod or dev, summary |
| `python-parents.txt` | which packages pull in each vulnerable one |
| `container-base.tsv` | Trivy findings for the final-stage `FROM` image |
| `container-image.tsv` | Trivy findings for the built image (only with `--image`) |
| `base-digest.txt`, `dockerfile-images.txt` | which images the Dockerfile uses |

The script prints counts and, when an earlier scan exists, what is new and what is resolved since then. Read the TSVs with `cut`/`column`/`awk`, not by loading the JSON.

### 2. Check exposure for each fixable Python finding

For each package with a fix, decide whether the vulnerable code path is reachable. Look at:

- **How it arrives:** `python-parents.txt`. Direct dependency, or transitive under which library?
- **Prod or dev:** the `scope` column. Dev-only findings never ship.
- **Client or server:** many advisories (aiohttp, graphql-core, h11, starlette) only bite when that library serves untrusted input. Check whether the service uses it as a server or only as a client.
- **Feature in use:** for advisories in one feature (for example pydantic-ai `web_fetch`), search the source: `rg -n "<feature>" src --max-count 3`.
- **Platform:** Windows-only advisories don't apply to Linux containers.
- **Trust bundle and TLS:** `certifi`, `urllib3`, `requests`, `httpx` findings affect every outbound call, so treat them as real.

Keep this to a handful of targeted searches. Don't read whole files.

A package can have several advisories with different fixed versions. Use the highest fixed version across all of a package's advisories as its target, or a later scan finds the rest.

When a fix is blocked by a cap in `pyproject.toml` (for example `fastapi<0.116.0` holding starlette back), find out why the cap exists: `git log -L<start>,<end>:pyproject.toml`. Caps often come over unchanged from a Poetry migration with no reason recorded. If none is recorded, treat the upgrade as a candidate, not a blocker.

### 3. Triage the container findings

- Debian packages with status `affected` or `fix_deferred` and no fixed version: nothing to do. The unpinned base tag picks fixes up on the next build. Group these by upstream source (for example all `util-linux` packages) instead of listing each binary package.
- Note which ones need a local attacker, a mount or `nsenter`, `systemd-homed`, or an unused tool. In a single-user non-root container, those are negligible.
- Anything with a fixed version is actionable. A common one is `pip` in the base image's system Python, fixed by `RUN python -m pip uninstall -y pip` in the final stage when the app runs from a uv venv.
- Note whether `FROM` and `COPY --from` images are pinned to a digest or use `latest`.

### 4. Check whether fixes resolve

Before you put any fixable package in "Not applicable" because it is a major bump, check that the bump actually fails to resolve:

```bash
uv lock --dry-run -P <pkg>==<fixed> [-P <pkg>==<fixed> ...]
```

A major bump that resolves cleanly and moves nothing else is cheap. Recommend it, and don't give "major bump" as the reason to skip it. Name the package that caps it when it doesn't resolve.

To try a framework upgrade (for example lifting a FastAPI cap), use a throwaway `git worktree` in the scratchpad: edit the pins, `uv lock`, `uv sync`, run the tests, and remove the worktree afterwards. Don't touch the user's branch until they decide.

To lock against a private index on Google Artifact Registry, set `UV_INDEX_<NAME>_USERNAME=oauth2accesstoken` and `UV_INDEX_<NAME>_PASSWORD=$(gcloud auth application-default print-access-token)`. Use the application-default token: the gcloud user login lapses more often and `gcloud auth print-access-token` then returns nothing.

A 401 from a private index means the registry token has expired. Tell the user to run `make install` (or the repo's equivalent) and stop there. Don't treat it as a dependency conflict.

### 5. Report

Lead with the headline: the total count, how many are critical, and the one or two that matter. Then use three tables, each with package, locked version → fixed version, severity and IDs, what the problem is, and exposure here:

1. **Patch now:** real exposure, or a critical, with a cheap bump.
2. **Low value, same lock refresh:** fixable but not reachable.
3. **Not applicable:** Windows-only, dev-only with no clean bump, or major bumps that don't resolve.
4. **Waiting on Debian (base image):** Debian items with no fix. Keep these apart from the Python findings, because the repo can't fix them.

Then give the changes since the last scan, if any, and a short **What I didn't cover** list (for example the image wasn't built, or a private package has no advisory data). End with one recommended action, such as "one PR with `uv lock --upgrade-package` for X, Y, Z".

Give the scan folder path in full so the user can open the raw files.

If the repo has `docs/security/vulnerability-log.md`, finish with a draft entry shown in chat. Copy the layout of the log's latest entry. Put Debian base-image findings with no fix in their own "Waiting on Debian (base image)" table, not in "Not fixed". "Not fixed" is only for what the repo controls. If the log has no such table yet, add it in this entry and update the log's header to describe it. Edit the file only when the user says so, and normally in the same PR as the bumps. Never write "this PR" in the "PR" column: once the PR is open, fill in its number (`#NNN`) as an extra commit on that PR.

### 6. Verify after the bumps

When the user asks for the fixes, after the bumps:

1. Run the tests and rescan. Bump again if a package still has an advisory.
2. If a framework, the server or a crypto library moved, or the Dockerfile changed, build the final image and smoke-test it: start it with dummy required settings, hit `/healthz`, an unknown path and one real endpoint with an invalid body, and check the expected status codes and error bodies.
3. Scan the built image with Trivy. It sometimes reports advisories that pip-audit misses (for example a second CVE for the same package). Add those to the log entry.
4. After the PR merges, rerun the Dependabot query from step 1b. Every alert should be closed, or dismissed with a reason recorded in the log.

## Tool notes

- `pip-audit` runs through `uvx`, so nothing gets installed. Packages from private indexes are skipped with a warning.
- Severities come from the OSV API (`api.osv.dev`), using GitHub advisory severity: LOW, MODERATE, HIGH or CRITICAL.
- Trivy uses the `trivy` binary if present (`brew install trivy`). Otherwise it runs the `aquasec/trivy` image pinned in the script, which caches its database in `~/.cache/trivy`.
- `--image` builds every stage up to the last one, from `git archive HEAD`: committed files only, as CI sees them. Uncommitted changes are not in the image. When the Dockerfile uses a `gcp_token` build secret, the script passes an application-default token (falling back to `gcloud auth print-access-token`) as that secret.
