#!/usr/bin/env bash
# download_and_restore.sh - restore the offline CTCallR bundle (Singularity image + scripts + R sources) from GitHub
# raw-branch files. Needs only bash, wget (or curl), sha256sum, tar, awk. No git, no python, no release assets.
#   wget https://github.com/Tim-Yu/ctcallr-offline/raw/refs/heads/main/restore/download_and_restore.sh
#   bash download_and_restore.sh --dest /re_gecip/cancer_sarcoma/<project>/ctcallr
# Result under --dest: sif/ctcallr_*.sif  bin/  hpc/  docs/  example_input/  r-src/  upstream/  LICENSES/  env_controlled.sh
set -euo pipefail
OWNER="Tim-Yu"; REPO="ctcallr-offline-parts"; BRANCH="payload-v1.0"; PACKAGE_PATH="packages/ctcallr/v1.0"
DEST_DIR="./ctcallr"; WORK_DIR=""; KEEP_PARTS=0; SKIP_SIF_CHECK=0; RETRIES=5; BASE_URL=""; CALLER_PWD="$(pwd)"
usage() { cat <<USAGE
Usage: bash download_and_restore.sh [--dest DIR] [--owner NAME] [--repo NAME] [--branch NAME] [--package-path PATH]
                                   [--work-dir DIR] [--keep-parts] [--skip-sif-check] [--retries N] [--base-url URL]
USAGE
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest) DEST_DIR="$2"; shift 2 ;; --owner) OWNER="$2"; shift 2 ;; --repo) REPO="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;; --package-path) PACKAGE_PATH="$2"; shift 2 ;; --work-dir) WORK_DIR="$2"; shift 2 ;;
    --keep-parts) KEEP_PARTS=1; shift ;; --skip-sif-check) SKIP_SIF_CHECK=1; shift ;; --retries) RETRIES="$2"; shift 2 ;;
    --base-url) BASE_URL="${2%/}"; shift 2 ;; -h|--help) usage; exit 0 ;; *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done
[[ "$DEST_DIR" == /* ]] || DEST_DIR="$CALLER_PWD/$DEST_DIR"; mkdir -p "$DEST_DIR"; DEST_DIR="$(cd "$DEST_DIR" && pwd)"
[[ -n "$WORK_DIR" ]] || WORK_DIR="$DEST_DIR/restore_work"; [[ "$WORK_DIR" == /* ]] || WORK_DIR="$CALLER_PWD/$WORK_DIR"
mkdir -p "$WORK_DIR"; WORK_DIR="$(cd "$WORK_DIR" && pwd)"; LOG="$WORK_DIR/restore.log"
log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*" | tee -a "$LOG"; }; die() { log "ERROR: $*"; exit 1; }
for cmd in sha256sum tar awk sort cat; do command -v "$cmd" >/dev/null 2>&1 || die "missing command: $cmd"; done
if command -v wget >/dev/null 2>&1; then DL=wget; elif command -v curl >/dev/null 2>&1; then DL=curl; else die "need wget or curl"; fi
alt_url() { # github.com/raw  <->  raw.githubusercontent.com (the redirect target); the same file on the other host
  case "$1" in
    https://github.com/*/raw/refs/heads/*) printf '%s' "$1" | sed -E 's#^https://github.com/([^/]+)/([^/]+)/raw/refs/heads/#https://raw.githubusercontent.com/\1/\2/#' ;;
    https://raw.githubusercontent.com/*) printf '%s' "$1" | sed -E 's#^https://raw.githubusercontent.com/([^/]+)/([^/]+)/([^/]+)/#https://github.com/\1/\2/raw/refs/heads/\3/#' ;;
    *) printf '%s' "$1" ;;
  esac
}
fetch() { local url="$1" dest="$2" try=1 u; while (( try <= RETRIES )); do
    for u in "$url" "$(alt_url "$url")"; do
      if [[ $DL == wget ]]; then wget -q -c -O "$dest.part" "$u" && mv -f "$dest.part" "$dest" && return 0
      else curl -fsSL -C - -o "$dest.part" "$u" && mv -f "$dest.part" "$dest" && return 0; fi
    done
    (( try < RETRIES )) && { log "  retry $try/$RETRIES for $(basename "$dest") in $((10 * (1 << (try - 1)))) s (GitHub 403/429 = shared address throttled)"; sleep $((10 * (1 << (try - 1)))); }
    try=$((try+1)); done; return 1; }
sha_ok() { [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]]; }
BASE="${BASE_URL:-https://github.com/${OWNER}/${REPO}/raw/refs/heads/${BRANCH}}/${PACKAGE_PATH}"
PDIR="$WORK_DIR/$(basename "$PACKAGE_PATH")"; mkdir -p "$PDIR"; cd "$PDIR"
log "Restore CTCallR bundle: $BASE -> $DEST_DIR"
log "[1/4] metadata"
for m in MANIFEST.tsv ARCHIVES.tsv REQUIRED_FILES.txt VERSIONS.txt; do fetch "$BASE/$m" "$m" || { [[ $m == REQUIRED_FILES.txt || $m == VERSIONS.txt ]] && continue; die "cannot download $m"; }; done
log "[2/4] parts (resumable, sha256-verified)"
total="$(awk -F'\t' 'NR>1 && $1!=""' MANIFEST.tsv | wc -l)"; done_n=0; fetched=0
while IFS=$'\t' read -r fname ftype fbytes fsha; do
  [[ -z "$fname" || "$fname" == "file" ]] && continue
  if [[ -f "$fname" && "$(stat -c %s "$fname")" == "$fbytes" && ( -f ".ok.$fname" || $(sha_ok "$fname" "$fsha" && echo 1) == 1 ) ]]; then touch ".ok.$fname"; done_n=$((done_n+1)); continue; fi
  rm -f "$fname" ".ok.$fname"; ok=0
  for attempt in $(seq 1 "${MISMATCH_RETRIES:-6}"); do
    fetch "$BASE/$fname" "$fname" || die "download failed: $fname"
    sha_ok "$fname" "$fsha" && { ok=1; break; }
    rm -f "$fname"; log "  checksum mismatch for $fname (GitHub's CDN still serving an older copy?); retry $attempt in ${MISMATCH_WAIT:-60} s"; sleep "${MISMATCH_WAIT:-60}"
  done
  [[ $ok -eq 1 ]] || die "checksum mismatch persists for $fname: rerun later (the script resumes) or check MANIFEST.tsv vs the published file"
  touch ".ok.$fname"; fetched=$((fetched+1)); done_n=$((done_n+1)); printf '\r   %d/%d files' "$done_n" "$total"
done < MANIFEST.tsv
echo; log "   parts verified: $done_n ($fetched downloaded)"
log "[3/4] reassemble + extract"
while IFS=$'\t' read -r aname atype abytes asha anparts aprefix aextract; do
  [[ -z "$aname" || "$aname" == "archive" ]] && continue
  log "   $aname <- $anparts parts"
  cat $(ls -1 "${aprefix}"* | LC_ALL=C sort) > "$aname"
  [[ "$(stat -c %s "$aname")" == "$abytes" ]] || die "size mismatch after reassembly: $aname"
  sha_ok "$aname" "$asha" || die "checksum mismatch after reassembly: $aname"
  case "$atype" in
    sif)  mkdir -p "$DEST_DIR/sif"; cp -f "$aname" "$DEST_DIR/sif/$aname"; chmod a+rx "$DEST_DIR/sif/$aname"; log "   installed sif/$aname" ;;
    code) tar -xzf "$aname" -C "$DEST_DIR"; log "   extracted code payload into $DEST_DIR" ;;
    tar)  mkdir -p "$DEST_DIR/$aextract"; tar -xzf "$aname" -C "$DEST_DIR/$aextract"; log "   extracted $aname into $DEST_DIR/$aextract" ;;
    *) die "unknown archive type '$atype'" ;;
  esac
  [[ $KEEP_PARTS -eq 1 ]] || rm -f "$aname"
done < ARCHIVES.tsv
log "[4/4] required files"
if [[ -f REQUIRED_FILES.txt ]]; then miss=0; while read -r rel; do [[ -z "$rel" || "$rel" == \#* ]] && continue; [[ -e "$DEST_DIR/$rel" ]] || { log "   MISSING: $rel"; miss=1; }; done < REQUIRED_FILES.txt; [[ $miss -eq 0 ]] || die "restore incomplete"; fi
[[ -f VERSIONS.txt ]] && { mkdir -p "$DEST_DIR/docs"; cp -f VERSIONS.txt "$DEST_DIR/docs/VERSIONS.txt"; }
cd "$CALLER_PWD"
SIF_PATH="$(ls -1 "$DEST_DIR"/sif/*.sif 2>/dev/null | head -1 || true)"
cat > "$DEST_DIR/env_controlled.sh" <<ENV
#!/usr/bin/env bash
# source this before running CTCallR in the controlled environment
export CTCALLR_ROOT="$DEST_DIR"
export CTCALLR_SIF="$SIF_PATH"
export PATH="$DEST_DIR/bin:\$PATH"
ENV
chmod +x "$DEST_DIR"/bin/*.sh "$DEST_DIR/env_controlled.sh" 2>/dev/null || true
if [[ $SKIP_SIF_CHECK -eq 0 ]]; then
  if ! command -v singularity >/dev/null 2>&1; then [[ -f /etc/profile.d/modules.sh ]] && source /etc/profile.d/modules.sh || true; module load singularity/4.1.1 >/dev/null 2>&1 || module load singularity >/dev/null 2>&1 || true; fi
  if command -v singularity >/dev/null 2>&1 && [[ -n "$SIF_PATH" ]]; then
    log "validating image with $(singularity --version)"
    singularity exec --cleanenv --no-home "$SIF_PATH" bash -c 'Rscript -e "suppressPackageStartupMessages(library(CTCallR)); cat(\"  CTCallR\", as.character(packageVersion(\"CTCallR\")), \"| copynumber\", as.character(packageVersion(\"copynumber\")), \"| R\", R.version.string, \"\n\")"; echo "  circos: $(circos -v | head -1)"' | tee -a "$LOG" || die "image validation failed"
  else log "singularity not available in this shell; skipped image validation (compute node: module load singularity/4.1.1)"; fi
fi
[[ $KEEP_PARTS -eq 1 ]] || find "$WORK_DIR" -maxdepth 2 -type f \( -name '*.part-*' -o -name '.ok.*' \) -delete
log "Restore complete: $DEST_DIR"
cat <<NEXT

Next steps
  source $DEST_DIR/env_controlled.sh
  # smoke test on the bundled 3-sarcoma example (~1-2 min, writes table + Circos PNGs):
  run_ctcallr.sh --cna $DEST_DIR/example_input/allCNAs.txt --sv $DEST_DIR/example_input/allSVs.txt --outdir $DEST_DIR/smoke_test --cores 4
  # your data:   run_ctcallr.sh --cna CNAs.tsv --sv SVs.tsv --outdir out [--genome hg38] [--cores 8]
  # LSF: $DEST_DIR/hpc/
NEXT
