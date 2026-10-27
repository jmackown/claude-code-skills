#!/usr/bin/env bash
# Vulnerability scan for a uv + Dockerfile repo. Read-only on the repo.
# pip-audit over uv.lock, Trivy over the Dockerfile's final-stage base image,
# and (with --image) Trivy over a locally built image.
# Results go to ~/.claude/vuln-scans/<repo>/<date>/.
#
# Usage: scan.sh [--image]   (run from inside the repo)
set -euo pipefail

BUILD_IMAGE=0
[[ "${1:-}" == "--image" ]] && BUILD_IMAGE=1

TRIVY_VERSION=0.69.1
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
REPO=$(basename "$REPO_ROOT")
OUT_ROOT="$HOME/.claude/vuln-scans/$REPO"
TODAY=$(date +%F)
OUT="$OUT_ROOT/$TODAY"
cd "$REPO_ROOT"

command -v uv >/dev/null || { echo "uv not found: install it first (https://docs.astral.sh/uv/)"; exit 1; }
command -v jq >/dev/null || { echo "jq not found: brew install jq"; exit 1; }

PREV=""
for d in "$OUT_ROOT"/20*/; do
  [[ -d "$d" && "$(basename "$d")" != "$TODAY" ]] && PREV="${d%/}"
done
mkdir -p "$OUT"
# A same-day rerun replaces that day's results.
rm -f "$OUT"/*

DOCKER_OK=0
docker info >/dev/null 2>&1 && DOCKER_OK=1

# Prints the Trivy runner in use, or nothing if neither trivy nor Docker is available.
trivy_runner() {
  if command -v trivy >/dev/null; then echo "trivy (local)"
  elif [[ $DOCKER_OK == 1 ]]; then echo "aquasec/trivy:$TRIVY_VERSION (docker)"
  fi
}

trivy_cmd() {
  if command -v trivy >/dev/null; then
    trivy "$@"
  else
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
      -v "$HOME/.cache/trivy:/root/.cache/trivy" "aquasec/trivy:$TRIVY_VERSION" "$@"
  fi
}

echo "== Output: $OUT"
[[ -n "$PREV" ]] && echo "== Previous scan: $PREV"

# --- Python dependencies -------------------------------------------------
if [[ -f uv.lock ]]; then
echo "== Python: pip-audit over uv.lock"
uv export --frozen --no-hashes --no-emit-project --all-groups > "$OUT/req-all.txt"
uv export --frozen --no-hashes --no-emit-project --no-dev > "$OUT/req-prod.txt"
# Packages from the private index are not on PyPI; pip-audit skips them with a warning.
uvx pip-audit -r "$OUT/req-all.txt" --no-deps --disable-pip -f json -o "$OUT/pip-audit.json" \
  2> "$OUT/pip-audit.err" || true

printf 'severity\tpackage\tinstalled\tfixed\tid\tcve\tscope\tsummary\n' > "$OUT/python.tsv"
jq -r '.dependencies[] | select(.vulns|length>0) | .name as $n | .version as $v
       | .vulns[] | [$n, $v, (.fix_versions|join("/")),
         ((.aliases|map(select(startswith("GHSA")))|.[0]) // .id),
         ((.aliases + [.id])|map(select(startswith("CVE")))|.[0] // "")] | @tsv' \
  "$OUT/pip-audit.json" |
while IFS=$'\t' read -r name ver fix id cve; do
  osv=$(curl -fsS "https://api.osv.dev/v1/vulns/$id" 2>/dev/null || echo '{}')
  sev=$(jq -r '.database_specific.severity // "UNKNOWN"' <<<"$osv")
  summ=$(jq -r '(.summary // "") | gsub("\t";" ") | .[0:110]' <<<"$osv")
  if grep -qi "^${name}==" "$OUT/req-prod.txt"; then scope=prod; else scope=dev; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$sev" "$name" "$ver" "$fix" "$id" "$cve" "$scope" "$summ"
done | sort -t$'\t' -k1,1 -k2,2 >> "$OUT/python.tsv"

: > "$OUT/python-parents.txt"
for p in $(tail -n +2 "$OUT/python.tsv" | cut -f2 | sort -u); do
  echo "$p <- $(uv tree --frozen --invert --package "$p" --depth 2 2>/dev/null \
    | tail -n +2 | sed 's/^[│├└─ ]*//' | grep -v '^(\*)' | tr '\n' ',' | cut -c1-200)" \
    >> "$OUT/python-parents.txt"
done
else
  echo "== Python: no uv.lock, skipped"
fi

# --- Container -----------------------------------------------------------
if [[ ! -f Dockerfile ]]; then
  echo "== Container: no Dockerfile, skipped"
else
RUNNER=$(trivy_runner)
FINAL_FROM=$(grep -iE '^FROM ' Dockerfile | tail -1 | awk '{print $2}')
grep -inE '^FROM |^COPY --from=[^ ]*[:/]' Dockerfile > "$OUT/dockerfile-images.txt" || true

if [[ -z "$RUNNER" ]]; then
  echo "== Container: image scan skipped: install trivy (brew install trivy) or start Docker"
  [[ $BUILD_IMAGE == 1 ]] && { echo "--image needs Docker running"; exit 1; }
else
  echo "== Container: scanning final-stage base $FINAL_FROM with $RUNNER"
  # Remote source so a stale local copy of the tag is never scanned.
  trivy_cmd image -q --image-src remote --severity CRITICAL,HIGH,MEDIUM --format json \
    "$FINAL_FROM" > "$OUT/trivy-base.json"
  jq -r '"\(.ArtifactName) \(.Metadata.RepoDigests[0] // "") \(.Metadata.OS.Family) \(.Metadata.OS.Name)"' \
    "$OUT/trivy-base.json" > "$OUT/base-digest.txt"

  if [[ $BUILD_IMAGE == 1 ]]; then
    [[ $DOCKER_OK == 1 ]] || { echo "--image needs Docker running"; exit 1; }
    TAG="vuln-scan/$REPO:$TODAY"
    echo "== Container: building final stage as $TAG (slow)"
    SECRET_ARGS=()
    if grep -q 'id=gcp_token' Dockerfile; then
      # Application-default credentials outlive the gcloud user login, so try them first
      GCP_TOKEN=$(gcloud auth application-default print-access-token 2>/dev/null || gcloud auth print-access-token 2>/dev/null)
      [[ -n $GCP_TOKEN ]] || { echo "--image needs a GCP token: run gcloud auth application-default login"; exit 1; }
      export GCP_TOKEN
      SECRET_ARGS=(--secret "id=gcp_token,env=GCP_TOKEN")
    fi
    # Build from committed files only, as CI does, so local worktrees, venvs and scratch files stay out
    git archive --format=tar HEAD | docker build "${SECRET_ARGS[@]}" -t "$TAG" - > "$OUT/build.log" 2>&1 \
      || { echo "Build failed, see $OUT/build.log"; tail -20 "$OUT/build.log"; exit 1; }
    trivy_cmd image -q --severity CRITICAL,HIGH,MEDIUM --format json "$TAG" > "$OUT/trivy-image.json"
  fi

  for f in "$OUT"/trivy-*.json; do
    kind=$(basename "$f" .json | sed 's/^trivy-//')
    printf 'severity\tpackage\tinstalled\tfixed\tid\tstatus\ttarget\ttitle\n' > "$OUT/container-$kind.tsv"
    jq -r '.Results[] | .Target as $t | .Vulnerabilities[]?
           | [.Severity, .PkgName, .InstalledVersion, (.FixedVersion // "no fix"),
              .VulnerabilityID, .Status, $t, ((.Title // "") | gsub("\t";" ") | .[0:90])] | @tsv' \
      "$f" | sort -u | sort -t$'\t' -k1,1 >> "$OUT/container-$kind.tsv"
  done
fi
fi

# --- Summary and changes since the previous scan --------------------------
echo
echo "== Counts"
for t in "$OUT"/python.tsv "$OUT"/container-*.tsv; do
  [[ -f "$t" ]] || continue
  printf '%s: ' "$(basename "$t" .tsv)"
  tail -n +2 "$t" | awk -F'\t' '{c[$1]++; if ($4!="no fix" && $4!="") f++} END {
    for (s in c) printf "%s=%d ", s, c[s]; printf "fixable=%d\n", f+0}'
done

if [[ -n "$PREV" ]]; then
  echo
  echo "== Changes since $(basename "$PREV")"
  for t in "$OUT"/python.tsv "$OUT"/container-*.tsv; do
    name=$(basename "$t")
    [[ -f "$t" && -f "$PREV/$name" ]] || continue
    old=$(tail -n +2 "$PREV/$name" | cut -f2,5 | sort -u)
    cur=$(tail -n +2 "$t" | cut -f2,5 | sort -u)
    new=$(comm -13 <(echo "$old") <(echo "$cur"))
    gone=$(comm -23 <(echo "$old") <(echo "$cur"))
    echo "-- $name: new=$(grep -c . <<<"$new" || true) resolved=$(grep -c . <<<"$gone" || true)"
    [[ -n "$new" ]] && awk '{print "   NEW  " $0}' <<<"$new" | head -30
    [[ -n "$gone" ]] && awk '{print "   GONE " $0}' <<<"$gone" | head -30
  done
fi

echo
echo "== Done. Detail files in $OUT"
[[ -f docs/security/vulnerability-log.md ]] && echo "== Record decisions in docs/security/vulnerability-log.md"
