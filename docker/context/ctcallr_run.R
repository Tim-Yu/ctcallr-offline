#!/usr/bin/env Rscript
# ctcallr_run.R - command-line driver for CTCallR::CTCallR() (chromothripsis calling from CN segments + SVs).
# Usage: Rscript ctcallr_run.R --cna FILE --sv FILE --outdir DIR [options]
#   --outputfile NAME      table file name inside outdir (default chromothripsis_annotated_calls.txt)
#   --genome hg19|hg38     karyotype used for the Circos plots (default hg19)
#   --cores N              MC.CORES (default 4)
#   --no-plot              skip Circos plotting
#   --circos PATH          circos executable (default: $CTCALLR_CIRCOS or /usr/bin/circos)
#   --prandomclass P       prandomclass_threshold (default 0.01)
#   --psegmentsize P       psegmentsize_threshold (default 0.05)
#   --min-cna-bp N         min_cna_breakpoints (default 15)
#   --min-sv-bp N          min_sv_breakpoints (default 15)
#   --flag-density X       flagDensity (default 150000000/50 = 3e6)
#   --min-events N         minEvents (default 5)
#   --svclasses del,td,h2h,t2t,tra   codes used in the SV file's class column for deletion, tandem duplication,
#                          head-to-head inversion, tail-to-tail inversion, translocation (default del,td,h2h,t2t,tra)
args <- commandArgs(trailingOnly = TRUE)
opt <- list(cna = NULL, sv = NULL, outdir = NULL, outputfile = "chromothripsis_annotated_calls.txt", genome = "hg19",
            cores = 4L, plot = TRUE, circos = Sys.getenv("CTCALLR_CIRCOS", "/usr/bin/circos"),
            prandomclass = 0.01, psegmentsize = 0.05, min_cna_bp = 15, min_sv_bp = 15,
            flag_density = 150000000 / 50, min_events = 5, svclasses = "del,td,h2h,t2t,tra")
usage <- function(code = 0) { cat(paste(readLines(sub("--file=", "", grep("--file=", commandArgs(), value = TRUE)))[2:17], collapse = "\n"), "\n"); quit(status = code) }
i <- 1
while (i <= length(args)) {
  a <- args[i]; v <- if (i < length(args)) args[i + 1] else NA
  take <- function(x) { i <<- i + 2; x }
  switch(a,
    "--cna" = opt$cna <- take(v), "--sv" = opt$sv <- take(v), "--outdir" = opt$outdir <- take(v),
    "--outputfile" = opt$outputfile <- take(v), "--genome" = opt$genome <- take(v),
    "--cores" = opt$cores <- as.integer(take(v)), "--circos" = opt$circos <- take(v),
    "--prandomclass" = opt$prandomclass <- as.numeric(take(v)), "--psegmentsize" = opt$psegmentsize <- as.numeric(take(v)),
    "--min-cna-bp" = opt$min_cna_bp <- as.numeric(take(v)), "--min-sv-bp" = opt$min_sv_bp <- as.numeric(take(v)),
    "--flag-density" = opt$flag_density <- as.numeric(take(v)), "--min-events" = opt$min_events <- as.numeric(take(v)),
    "--svclasses" = opt$svclasses <- take(v),
    "--no-plot" = { opt$plot <- FALSE; i <- i + 1 },
    "-h" = usage(), "--help" = usage(),
    stop("unknown option: ", a))
}
if (is.null(opt$cna) || is.null(opt$sv) || is.null(opt$outdir)) { cat("ERROR: --cna, --sv and --outdir are required\n\n"); usage(1) }
for (f in c(opt$cna, opt$sv)) if (!file.exists(f)) stop("input not found: ", f)
if (!opt$genome %in% c("hg19", "hg38")) stop("--genome must be hg19 or hg38")
sc <- strsplit(opt$svclasses, ",")[[1]]
if (length(sc) != 5) stop("--svclasses needs 5 comma-separated codes (deletion,tandemdup,head2headI,tail2tailI,translocation)")
svclasses <- c(deletion = sc[1], tandemdup = sc[2], head2headI = sc[3], tail2tailI = sc[4], translocation = sc[5])
dir.create(opt$outdir, recursive = TRUE, showWarnings = FALSE)
opt$outdir <- normalizePath(opt$outdir); opt$cna <- normalizePath(opt$cna); opt$sv <- normalizePath(opt$sv)
outputfile <- file.path(opt$outdir, opt$outputfile)
setwd(opt$outdir)
# hg38 plots: the package conf hard-codes the hg19 karyotype file name; a wrapper around circos rewrites it (see circos_build.sh)
circos_path <- opt$circos
if (opt$plot) {
  if (opt$genome == "hg38" && file.exists("/opt/ctcallr/circos_build.sh")) circos_path <- "/opt/ctcallr/circos_build.sh"
  Sys.setenv(CTCALLR_GENOME = opt$genome, CTCALLR_REAL_CIRCOS = opt$circos)
  if (!file.exists(opt$circos) && Sys.which(opt$circos) == "") warning("circos not found at ", opt$circos, "; plots will fail")
}
cat(sprintf("[ctcallr_run] CTCallR %s | CNA=%s | SV=%s | outdir=%s | genome=%s | cores=%d | plot=%s\n",
            as.character(packageVersion("CTCallR")), opt$cna, opt$sv, opt$outdir, opt$genome, opt$cores, opt$plot))
suppressPackageStartupMessages(library(CTCallR))
t0 <- Sys.time()
ct <- CTCallR(CNA_file = opt$cna, SV_file = opt$sv, outputdir = opt$outdir, plot_results = opt$plot,
              outputfile = outputfile, svclasses = svclasses,
              prandomclass_threshold = opt$prandomclass, psegmentsize_threshold = opt$psegmentsize,
              min_cna_breakpoints = opt$min_cna_bp, min_sv_breakpoints = opt$min_sv_bp,
              flagDensity = opt$flag_density, minEvents = opt$min_events,
              genome.build = opt$genome, circos_path = circos_path, MC.CORES = opt$cores)
setwd(opt$outdir)
writeLines(capture.output(sessionInfo()), file.path(opt$outdir, "ctcallr_sessionInfo.txt"))
n_ct <- sum(ct$Calls == "Chromothripsis"); n_cl <- sum(ct$Calls == "Cluster")
cat(sprintf("[ctcallr_run] done in %.1f min: %d flagged regions in %d samples: %d Chromothripsis, %d Cluster -> %s\n",
            as.numeric(difftime(Sys.time(), t0, units = "mins")), nrow(ct), length(unique(ct$samplename)), n_ct, n_cl, outputfile))
if (opt$plot) { pngs <- list.files(opt$outdir, pattern = "_im\\.png$", recursive = TRUE); cat(sprintf("[ctcallr_run] circos PNGs: %d\n", length(pngs))) }
