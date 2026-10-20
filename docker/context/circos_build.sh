#!/usr/bin/env bash
# circos wrapper: CTCallR's mycircosDJ.conf hard-codes karyotype.human.hg19.txt while CTCallR copies
# karyotype.human.<genome.build>.txt next to it. For hg38 runs, rewrite that line in the per-sample conf copy, then run circos.
set -euo pipefail
REAL="${CTCALLR_REAL_CIRCOS:-/usr/bin/circos}"
if [[ "${CTCALLR_GENOME:-hg19}" != "hg19" ]]; then
  prev=""
  for a in "$@"; do
    if [[ "$prev" == "-conf" && -f "$a" ]]; then sed -i "s/karyotype\.human\.hg19\.txt/karyotype.human.${CTCALLR_GENOME}.txt/" "$a"; fi
    prev="$a"
  done
fi
exec "$REAL" "$@"
