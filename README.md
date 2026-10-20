# ctcallr-offline

Bootstrap repository for running **CTCallR** (chromothripsis caller from WGS copy-number + SV calls;
[galder-max/CTCallR](https://github.com/galder-max/CTCallR), GPL-3) in a controlled environment whose only outbound
access is GitHub. The Singularity image and the R package sources live as < 50 MiB split parts in
[`ctcallr-offline-parts`](https://github.com/Tim-Yu/ctcallr-offline-parts) (branch `payload-v1.0`), fetched with plain `wget`.

```bash
wget https://github.com/Tim-Yu/ctcallr-offline/raw/refs/heads/main/restore/download_and_restore.sh
bash download_and_restore.sh --dest $PWD/ctcallr
source ctcallr/env_controlled.sh
run_ctcallr.sh --cna allCNAs.txt --sv allSVs.txt --outdir out --genome hg38 --cores 8
```
Full guide: [`docs/README_CONTROLLED_ENV.md`](docs/README_CONTROLLED_ENV.md).

| Path | Purpose |
| --- | --- |
| `restore/download_and_restore.sh` | bash-only downloader / verifier / extractor (resumable) |
| `bin/` | `run_ctcallr.sh`, `ctcallr_exec.sh`, `purple_to_ctcallr.R` |
| `hpc/` | LSF templates: `ctcallr_cohort.lsf` (self-submitting: whole cohort from the sample sheet + oncoanalyser output), `submit_ctcallr_hpc.lsf`, `restore_only.lsf` |
| `example_input/` | upstream 3-sarcoma example data |
| `docker/` | Dockerfile and scripts that built the image (`rocker/r-ver:4.4.3` + Ubuntu `circos` + Bioconductor 3.20 + copynumber 1.40.0 from Bioconductor git) |
| `manifests/v1.0/` | MANIFEST.tsv, CHECKSUMS.sha256, ARCHIVES.tsv, ARCHIVES.sha256, REQUIRED_FILES.txt, VERSIONS.txt |
| `upstream/CTCallR-bb428d2/` | pinned upstream source |
| `LICENSES/`, `docs/VERSIONS.txt` | licences; exact versions, digests and checksums |
