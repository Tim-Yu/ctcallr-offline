#!/usr/bin/env bash
# Export the exact R package sources installed in the image as a local CRAN-style repository (r-src/), so CTCallR
# and all its dependencies can be installed into a native R (>= 4.4) without internet:
#   Rscript -e 'install.packages("CTCallR", repos = "file:///path/r-src", type = "source")'
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIF="${SIF:-$(ls -1 "$ROOT"/sif/*.sif | head -1)}"
OUT="$ROOT/r-src"; mkdir -p "$OUT/src/contrib"
echo "[$(date -u +%FT%TZ)] exporting sources with $SIF -> $OUT"
# 1) CRAN + Bioconductor sources at the versions installed in the image (download runs inside the image: same repos/snapshot)
singularity exec --cleanenv --no-home --bind "$OUT:/out" "$SIF" Rscript -e '
  ip <- installed.packages()
  base <- rownames(ip)[ip[, "Priority"] %in% c("base", "recommended")]
  want <- setdiff(rownames(ip), c(base, "CTCallR", "copynumber"))
  repos <- c(getOption("repos"), BiocManager::repositories())
  repos <- repos[!duplicated(repos)]
  av <- available.packages(repos = repos, type = "source")
  missing <- want[!want %in% rownames(av)]
  if (length(missing)) cat("not in repos (will be skipped):", paste(missing, collapse = ", "), "\n")
  diff <- want[want %in% rownames(av) & av[intersect(want, rownames(av)), "Version"] != ip[intersect(want, rownames(av)), "Version"]]
  if (length(diff)) cat("version differs from installed (repo version will be downloaded):", paste(diff, collapse = ", "), "\n")
  res <- download.packages(intersect(want, rownames(av)), destdir = "/out/src/contrib", repos = repos, type = "source", quiet = TRUE)
  cat("downloaded", nrow(res), "source packages\n")
  # recommended packages that CTCallR needs but a minimal R may lack (MASS is recommended; ship it too)
  download.packages(c("MASS"), destdir = "/out/src/contrib", repos = repos, type = "source", quiet = TRUE)
'
# 2) copynumber (removed from Bioconductor) and CTCallR itself, as proper source tarballs
cp -f "$ROOT/downloads/copynumber_1.40.0_bioc-RELEASE_3_17.tar.gz" "$OUT/src/contrib/copynumber_1.40.0.tar.gz"
# CTCallR with the bundle patches applied (same code as in the image)
PT="$(mktemp -d)"; cp -r "$ROOT/docker/context/CTCallR" "$PT/CTCallR"
for pf in "$ROOT"/docker/context/patches/*.patch; do patch -p1 -d "$PT/CTCallR" < "$pf" >/dev/null; done
( cd "$PT" && tar -czf "$OUT/src/contrib/CTCallR_1.0.tar.gz" CTCallR ); rm -rf "$PT"
# 3) make it a CRAN-like repo (PACKAGES index) so install.packages() resolves dependencies offline
singularity exec --cleanenv --no-home --bind "$OUT:/out" "$SIF" Rscript -e 'tools::write_PACKAGES("/out/src/contrib", type = "source", verbose = FALSE); p <- read.dcf("/out/src/contrib/PACKAGES"); cat(nrow(p), "packages indexed\n")'
cat > "$OUT/INSTALL_OFFLINE.md" <<'MD'
# Installing CTCallR into a native R without internet

This directory is a CRAN-style source repository holding CTCallR, copynumber 1.40.0 (last Bioconductor release) and
every CRAN/Bioconductor dependency at the versions used in the Singularity image (R 4.4.3, Bioconductor 3.20).
Needs R >= 4.4 with a C/C++/Fortran toolchain, zlib/bzip2/xz/curl/ssl/xml2 dev headers, and (for plots) the Circos
program (`apt install circos` on Debian/Ubuntu). Then:

```r
repo <- "file:///ABSOLUTE/PATH/TO/r-src"
lib  <- "/path/to/R_libs"; dir.create(lib, showWarnings = FALSE)
install.packages("CTCallR", lib = lib, repos = repo, type = "source", dependencies = c("Depends","Imports","LinkingTo"))
# CTCallR's DESCRIPTION declares no dependencies, so install them explicitly:
install.packages(c("vcd","EMT","RColorBrewer","GenomicRanges","IRanges","copynumber"), lib = lib, repos = repo, type = "source")
```
The container route (`run_ctcallr.sh`) is the tested path; this is the fallback.
MD
ls -la "$OUT/src/contrib" | head -60; du -sh "$OUT"
echo "[$(date -u +%FT%TZ)] r-src ready"
