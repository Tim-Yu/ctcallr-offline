#!/usr/bin/env bash
# run_ctcallr.sh - run CTCallR (chromothripsis caller) inside the Singularity image. Host needs only bash + singularity.
#
#   run_ctcallr.sh --cna allCNAs.txt --sv allSVs.txt --outdir /path/out [--genome hg19|hg38] [--cores 4] [--no-plot]
#                  [--sif FILE] [--bind HOST[:CONT[:ro]]] [--dry_run] [any other ctcallr_run.R option]
#
# Inputs (TSV, header line, columns in this order):
#   CNA: samplename chr startpos endpos nMaj1_A nMin1_A frac1_A      (Battenberg-like; chr without "chr" prefix, 1-22,X)
#   SV : samplename chr1 pos1 chr2 pos2 class                        (class codes: del td h2h t2t tra; see --svclasses)
# Output: <outdir>/chromothripsis_annotated_calls.txt, <outdir>/<sample>/<sample>_im.png (Circos), ctcallr_sessionInfo.txt
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; INSTALL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SIF="${CTCALLR_SIF:-}"; CNA=""; SV=""; OUTDIR=""; DRY=0; EXTRA=(); EXTRA_BINDS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cna) CNA="$2"; shift 2 ;; --sv) SV="$2"; shift 2 ;; --outdir) OUTDIR="$2"; shift 2 ;;
    --sif) SIF="$2"; shift 2 ;; --bind) EXTRA_BINDS+=("$2"); shift 2 ;; --dry_run|--dry-run) DRY=1; shift ;;
    -h|--help) awk 'NR>1 { if (/^#/) { sub(/^# ?/,""); print } else exit }' "$0"; echo; echo "ctcallr_run.R options:"; [[ -n "$SIF" || -n "$(ls -1 "$INSTALL_ROOT"/sif/*.sif 2>/dev/null | head -1)" ]] && singularity exec --cleanenv --no-home "${SIF:-$(ls -1 "$INSTALL_ROOT"/sif/*.sif | head -1)}" Rscript /opt/ctcallr/ctcallr_run.R --help 2>/dev/null | sed -n '3,20p'; exit 0 ;;
    *) EXTRA+=("$1"); shift ;;
  esac
done
die() { echo "ERROR: $*" >&2; exit 1; }
[[ -n "$SIF" ]] || SIF="$(ls -1 "$INSTALL_ROOT"/sif/*.sif 2>/dev/null | head -1 || true)"
[[ -n "$SIF" && -f "$SIF" ]] || die "Singularity image not found; use --sif FILE or set CTCALLR_SIF"
command -v singularity >/dev/null 2>&1 || die "singularity not on PATH (HPC: module load singularity)"
[[ -n "$CNA" && -n "$SV" && -n "$OUTDIR" ]] || die "--cna, --sv and --outdir are required"
[[ -f "$CNA" ]] || die "CNA file not found: $CNA"; [[ -f "$SV" ]] || die "SV file not found: $SV"
CNA="$(realpath "$CNA")"; SV="$(realpath "$SV")"; mkdir -p "$OUTDIR"; OUTDIR="$(realpath "$OUTDIR")"
[[ "$OUTDIR" != "/" ]] || die "outdir must not be /"
for p in "$CNA" "$SV" "$OUTDIR"; do [[ "$p" == *" "* ]] && die "paths must not contain spaces: $p"; done
BINDS=("$(dirname "$CNA"):/in_cna:ro" "$(dirname "$SV"):/in_sv:ro" "$OUTDIR:/out")
for b in "${EXTRA_BINDS[@]}"; do BINDS+=("$b"); done
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ctcallr.XXXXXX")"
SING=(singularity exec --no-home --cleanenv --env "TMPDIR=/tmp" --env "CTCALLR_CIRCOS=/usr/bin/circos" --bind "$TMP_DIR:/tmp")
for b in "${BINDS[@]}"; do SING+=(--bind "$b"); done
SING+=("$SIF" Rscript /opt/ctcallr/ctcallr_run.R --cna "/in_cna/$(basename "$CNA")" --sv "/in_sv/$(basename "$SV")" --outdir /out "${EXTRA[@]}")
echo "[run_ctcallr] image : $SIF"; echo "[run_ctcallr] inputs: $CNA | $SV"; echo "[run_ctcallr] outdir: $OUTDIR"
if [[ $DRY -eq 1 ]]; then printf '%q ' "${SING[@]}"; echo; rm -rf "$TMP_DIR"; exit 0; fi
set +e; "${SING[@]}" 2>&1 | tee -a "$OUTDIR/run_ctcallr.log"; rc=${PIPESTATUS[0]}; set -e
rm -rf "$TMP_DIR"
[[ $rc -eq 0 ]] || { echo "[run_ctcallr] FAILED (exit $rc); see $OUTDIR/run_ctcallr.log" >&2; exit $rc; }
echo "[run_ctcallr] finished OK: $OUTDIR"
