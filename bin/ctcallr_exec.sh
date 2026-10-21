#!/usr/bin/env bash
# ctcallr_exec.sh - run any command inside the CTCallR image with the bundle's bin/ mounted at /ctcallr_bin.
#   ctcallr_exec.sh [--sif FILE] [--bind HOST[:CONT[:ro]]]... -- <command...>
# Example (convert PURPLE output; paths must be visible: add --bind for their directories or run from inside them):
#   ctcallr_exec.sh --bind /path/purple:/purple:ro --bind $PWD:/work -- Rscript /ctcallr_bin/purple_to_ctcallr.R \
#       --sample S1 --purple-cnv /purple/S1.purple.cnv.somatic.tsv --purple-sv /purple/S1.purple.sv.vcf.gz \
#       --out-cna /work/allCNAs.txt --out-sv /work/allSVs.txt [--append]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; INSTALL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SIF="${CTCALLR_SIF:-}"; BINDS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sif) SIF="$2"; shift 2 ;; --bind) BINDS+=("$2"); shift 2 ;; --) shift; break ;;
    -h|--help) awk 'NR>1 { if (/^#/) { sub(/^# ?/,""); print } else exit }' "$0"; exit 0 ;;
    *) break ;;
  esac
done
[[ -n "$SIF" ]] || SIF="$(ls -1 "$INSTALL_ROOT"/sif/*.sif 2>/dev/null | head -1 || true)"
[[ -f "$SIF" ]] || { echo "ERROR: image not found; use --sif" >&2; exit 1; }
[[ $# -gt 0 ]] || { echo "ERROR: no command given after --" >&2; exit 1; }
cmd=(singularity exec --no-home --cleanenv --bind "$SCRIPT_DIR:/ctcallr_bin:ro")
work_bound=0; for b in "${BINDS[@]}"; do [[ "$b" == *":/work"* ]] && work_bound=1; cmd+=(--bind "$b"); done
[[ $work_bound -eq 1 ]] || cmd+=(--bind "$PWD:/work")     # default: current directory at /work unless the caller bound /work
cmd+=(--pwd /work "$SIF" "$@")
exec "${cmd[@]}"
