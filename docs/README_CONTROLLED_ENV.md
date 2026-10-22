# CTCallR offline bundle (chromothripsis calling from WGS copy-number + SV calls)

[CTCallR](https://github.com/galder-max/CTCallR) (Tarabichi; Korbel & Campbell 2013 tests) annotates high-density
breakpoint regions as **Chromothripsis** or **Cluster** from two cohort-level TSV tables (copy-number segments and SV
breakpoint pairs) and draws one Circos plot per sample. This bundle packs CTCallR (commit bb428d2, 2023-09-19), all its
R dependencies (including `copynumber` 1.40.0, which was removed from Bioconductor in 3.18) and Circos 0.69.9 into one
Singularity image, with a bash launcher, LSF templates, a converter from oncoanalyser/PURPLE output, and the R package
sources for a native install. The host needs only bash, wget, sha256sum, tar and Singularity/Apptainer.

## Layout after `download_and_restore.sh`
```
<dest>/
├── sif/ctcallr_1.0-bb428d2.sif      R 4.4.3 + Bioconductor 3.20 + copynumber 1.40.0 + Circos 0.69.9 + CTCallR
├── bin/run_ctcallr.sh               launcher (bash only)
├── bin/ctcallr_exec.sh              run any command inside the image (used for the converter)
├── bin/purple_to_ctcallr.R          PURPLE cnv.somatic.tsv + purple.sv.vcf.gz -> CTCallR input tables
├── example_input/                   the upstream 3-sarcoma example (allCNAs.txt, allSVs.txt; hg19)
├── r-src/                           CRAN-style source repo of every dependency (fallback native install, see r-src/INSTALL_OFFLINE.md)
├── hpc/                             LSF templates
├── upstream/CTCallR-bb428d2/        pinned upstream source
├── docker/                          Dockerfile + scripts used to build the image (rebuild recipe)
├── LICENSES/, docs/VERSIONS.txt, env_controlled.sh
```

## Install (controlled environment)
```bash
mkdir -p /re_gecip/cancer_sarcoma/<project> && cd /re_gecip/cancer_sarcoma/<project>
wget https://github.com/Tim-Yu/ctcallr-offline/raw/refs/heads/main/restore/download_and_restore.sh
bash download_and_restore.sh --dest $PWD/ctcallr        # ~0.5 GB of 49 MiB parts, sha256-verified, resumable
source ctcallr/env_controlled.sh
# smoke test (1-2 min): expect a calls table with Chromothripsis + Cluster rows and 3 Circos PNGs
run_ctcallr.sh --cna $CTCALLR_ROOT/example_input/allCNAs.txt --sv $CTCALLR_ROOT/example_input/allSVs.txt --outdir $CTCALLR_ROOT/smoke_test --cores 4
```

## Updating an existing restore (scripts and docs only)
```bash
wget https://github.com/Tim-Yu/ctcallr-offline/raw/refs/heads/main/restore/update_bundle.sh
bash update_bundle.sh --dest /path/to/restored/bundle          # add --dry-run to list what would change
```
Fetches the bootstrap file list (`FILES.txt`) and replaces only files whose checksum differs (bin/, hpc/, docs/,
restore/, example data, licences, upstream source). The image, reference data and your runs are not touched. A new
image or data version is announced by a new payload branch and needs a full `download_and_restore.sh`.

## Input format (TSV with header, columns in this order)
| Table | Columns |
| --- | --- |
| copy number | `samplename chr startpos endpos nMaj1_A nMin1_A frac1_A` (Battenberg-like; chr as `1`..`22`,`X`, no `chr` prefix; integer allele copy numbers; frac1_A = 1 if no subclonality) |
| SVs | `samplename chr1 pos1 chr2 pos2 class` with class in `del td h2h t2t tra` (deletion-type, tandem-duplication-type, head-to-head inversion, tail-to-tail inversion, translocation); other codes via `--svclasses a,b,c,d,e` |

Several samples go in the same two files; CTCallR processes the cohort in one run (flagging per sample, tests across).

### From oncoanalyser / PURPLE output
```bash
source ctcallr/env_controlled.sh
ctcallr_exec.sh --bind /path/purple:/purple:ro --bind $PWD:/work -- Rscript /ctcallr_bin/purple_to_ctcallr.R \
   --sample CCS_12GP-T --purple-cnv /purple/CCS_12GP-T.purple.cnv.somatic.tsv --purple-sv /purple/CCS_12GP-T.purple.sv.vcf.gz \
   --out-cna /work/allCNAs.txt --out-sv /work/allSVs.txt --append      # repeat per sample with --append
```
Conversion rules: major/minor allele copy numbers are rounded to integers, frac1_A = 1, chromosomes 1-22 and X kept
(`--keep-y` adds Y), SVs = PASS breakend pairs of the PURPLE SV VCF (`--filters PASS,INFERRED` to widen), class from
the VCF bracket notation of the lower breakend (`N[p[` del, `]p]N` td, `N]p]` h2h, `[p[N` t2t, inter-chromosomal tra).
### Whole cohort from the sample sheet (recommended)
With the project sample sheet (header `PatientID TumourID Tumour_BAM Normal_BAM`, tab or comma separated) and the
directory tree that holds the oncoanalyser output, one bsub script does everything:
```bash
cd /path/ctcallr                                                            # the restore destination
bash hpc/ctcallr_cohort.lsf /path/sample_sheet.tsv /path/to/oncoanalyser_output [cohort_name]
```
It looks for `<TumourID>.purple.cnv.somatic.tsv` and `<TumourID>.purple.sv.vcf.gz` anywhere under that tree, prints
which tumours have them, and submits itself as one job that converts all samples, runs CTCallR with `--genome hg38`
and writes `runs/ctcallr_<cohort>/chromothripsis_annotated_calls_with_patient.txt` (calls table with PatientID joined
in), the Circos PNGs, and `inputs/<cohort>_sample_map.tsv` (PURPLE files used; tumours without PURPLE output are
skipped). If the PURPLE sample name differs from TumourID, add a `PurpleID` column to the sheet. Optional env before
the command: `QUEUE=short WALLTIME=4:00` (defaults; a cohort run takes seconds to minutes), `GENOME=hg19`,
`EXTRA_ARGS="--min-cna-bp 10"`, `PURPLE_FILTERS=PASS,INFERRED`, `DRY_RUN=1` (print the bsub command only).

### Copy number from Battenberg instead of PURPLE
CTCallR's copy-number table is the Battenberg `*_subclones.txt` layout (`chr startpos endpos nMaj1_A nMin1_A frac1_A`),
so Battenberg output is the natural source (subclonal fractions are kept). SVs still come from a breakend VCF, normally
the PURPLE SV VCF of the same tumour:
```bash
cd /path/ctcallr
BATTENBERG_ROOT=/path/to/battenberg_results bash hpc/ctcallr_cohort.lsf /path/sample_sheet.tsv /path/to/oncoanalyser_output TERT_bb
```
The job looks for `<TumourID>_subclones.txt` under `BATTENBERG_ROOT` (and `<TumourID>.purple.sv.vcf.gz` under the
oncoanalyser output as before); `inputs/<cohort>_sample_map.tsv` records which files were used. One sample by hand:
```bash
ctcallr_exec.sh --bind /path/bb:/bb:ro --bind /path/purple:/purple:ro --bind $PWD:/work -- Rscript /ctcallr_bin/make_ctcallr_input.R \
   --sample S1 --battenberg-subclones /bb/S1_subclones.txt --sv-vcf /purple/S1.purple.sv.vcf.gz --out-cna /work/allCNAs.txt --out-sv /work/allSVs.txt --append
```
`make_ctcallr_input.R` takes `--battenberg-subclones` or `--purple-cnv` for copy number and `--sv-vcf` (any breakend
VCF with MATEID: PURPLE, ESVEE, GRIDSS) for SVs; `purple_to_ctcallr.R` is kept as an alias of the PURPLE mode.

### GEL project layout: consensus SV BEDPE + fixed Battenberg tables (recommended for the TERT cohort)
When each tumour already has consensus SV calls and a fixed Battenberg table in the project folders
```
<SV_ROOT>/<PatientID>/<TumourID>/<TumourID>.somatic.sv.bedpe              (default SV_ROOT=/re_gecip/cancer_sarcoma/19.ComplexSVs/19.5.SVs/19.5.7.ConsensusCalls/5_callers)
<CN_ROOT>/P_<PatientID>_T_<TumourID>_N_<NormalID>/<TumourID>_copynumber_1.txt   (default CN_ROOT=/re_gecip/cancer_sarcoma/33.CN_Sigs/33.4.BB_fix/BB_merged)
```
one script locates both from the sample sheet (NormalID = Normal_BAM file name without `_final_dedup.bam`):
```bash
cd /path/ctcallr
DRY_RUN=1 bash hpc/ctcallr_cohort_gel.lsf /path/sample_sheet.tsv TERT     # lists found/missing files, submits nothing
bash hpc/ctcallr_cohort_gel.lsf /path/sample_sheet.tsv TERT               # submits one job: convert all, run CTCallR (hg38)
```
Override roots or file suffixes with env before the command, e.g. `CN_SUFFIX=_copynumber_1_gapfilled_LogR_new.txt`,
`SV_ROOT=...`, `CN_ROOT=...`. Output: `runs/ctcallr_TERT/chromothripsis_annotated_calls_with_patient.txt`, Circos PNGs,
`inputs/TERT_sample_map.tsv` (files used per tumour). SV classes come from the BEDPE `strand1`/`strand2` pair of the
lower breakend (`+-` del, `-+` td, `++` h2h, `--` t2t; other chromosome -> tra); rows without strands fall back to
`svclass` (INV without strands becomes `inv`, which CTCallR does not count as h2h/t2t).

## Run
```bash
run_ctcallr.sh --cna allCNAs.txt --sv allSVs.txt --outdir out --genome hg38 --cores 8          # GRCh38 data
run_ctcallr.sh --help                                                                        # all options
```
Options pass through to `CTCallR()`: `--prandomclass 0.01 --psegmentsize 0.05 --min-cna-bp 15 --min-sv-bp 15
--flag-density 3e6 --min-events 5 --no-plot --svclasses del,td,h2h,t2t,tra`. Defaults are the upstream defaults
("suited for WGS and Battenberg"). Outputs: `out/chromothripsis_annotated_calls.txt` (one row per flagged region:
sample, start, end, chrArm, density, breakpoint counts, p-values, CN states, coverage, `Calls`), `out/<sample>/<sample>_im.png`,
`out/ctcallr_sessionInfo.txt`, `out/run_ctcallr.log`. LSF: `hpc/submit_ctcallr_hpc.lsf`.

## Changes made in this bundle (on top of upstream commit bb428d2)
- `docker/context/patches/0001-empty-table-when-nothing-flagged.patch`: when no high-density breakpoint region is
  flagged in any sample, upstream crashes in `deriveTable` (`colnames<-` on NULL). The patched package writes an empty
  calls table with the final column set and returns it. Applied in the image and in the `r-src/` CTCallR tarball.
- Circos under Debian/Ubuntu keeps its configuration in `/etc/circos/`, while the CTCallR configs include
  `etc/image.conf` and `etc/housekeeping.conf` (the upstream tarball layout). The image adds the symlink
  `/etc/circos/etc -> /etc/circos` so those includes resolve. The Ubuntu `circos` package also lacks the Perl module
  `List::MoreUtils` that Circos requires; `liblist-moreutils-perl` is installed.

## Known upstream quirks (handled or documented)
- The Circos config hard-codes the hg19 karyotype file name; for `--genome hg38` the launcher routes Circos through a
  wrapper that rewrites that line per sample, so hg38 plots work (tested).
- `pcf()` is called without an `assembly`, so chromosome-arm labels (`chrArm`) always use hg19 centromere positions,
  also for hg38 data; calls themselves do not depend on it.
- `summaryHD` (printed "Homozygous deletions" summary) always reports 0 because it references columns that do not exist.
- `?CTCallR` is out of date (misses `outputdir`, `genome.build`, `circos_path`, `plot_results`); use `run_ctcallr.sh --help`.
- CTCallR writes temporary Circos files into the output directory and `setwd()`s there; give every run its own `--outdir`.

## Licences
All open source (CTCallR GPL-3; Bioconductor packages Artistic-2.0; CRAN packages GPL/Apache/BSD; Circos GPL). No
licence keys, no reference downloads. See `LICENSES/README.md`.

## Offline behaviour
Nothing in the image contacts the network (verified by running the example in a network-less namespace).
