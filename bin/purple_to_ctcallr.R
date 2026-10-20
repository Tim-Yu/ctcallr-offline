#!/usr/bin/env Rscript
# purple_to_ctcallr.R - convert hmftools PURPLE output (as produced by oncoanalyser) into the two CTCallR input tables.
#   Rscript purple_to_ctcallr.R --sample NAME --purple-cnv S.purple.cnv.somatic.tsv --purple-sv S.purple.sv.vcf.gz \
#                               --out-cna allCNAs.txt --out-sv allSVs.txt [--append] [--filters PASS] [--keep-y]
# CNA: samplename chr startpos endpos nMaj1_A nMin1_A frac1_A  <- chromosome,start,end, round(majorAlleleCopyNumber),
#      round(minorAlleleCopyNumber), 1. "chr" prefix removed; chromosomes 1-22 and X kept (CTCallR iterates 1:22,X).
# SV : samplename chr1 pos1 chr2 pos2 class               <- one row per breakend pair from the PURPLE SV VCF (BND records
#      with MATEID; single/inferred breakends dropped). class from the bracket notation of the LOWER breakend:
#      N[p[ -> del (+/-), ]p]N -> td (-/+), N]p] -> h2h (+/+), [p[N -> t2t (-/-); different chromosomes -> tra.
# Caveats: PURPLE copy numbers are purity-adjusted continuous values; rounding to integers mimics Battenberg's
# nMaj/nMin but loses subclonality (frac1_A is set to 1). Review thresholds with your caller in mind (see ?CTCallR).
args <- commandArgs(trailingOnly = TRUE)
opt <- list(sample = NULL, cnv = NULL, sv = NULL, out_cna = NULL, out_sv = NULL, append = FALSE, filters = "PASS", keep_y = FALSE)
i <- 1
while (i <= length(args)) {
  a <- args[i]; v <- if (i < length(args)) args[i + 1] else NA
  switch(a,
    "--sample" = { opt$sample <- v; i <- i + 2 }, "--purple-cnv" = { opt$cnv <- v; i <- i + 2 }, "--purple-sv" = { opt$sv <- v; i <- i + 2 },
    "--out-cna" = { opt$out_cna <- v; i <- i + 2 }, "--out-sv" = { opt$out_sv <- v; i <- i + 2 }, "--filters" = { opt$filters <- v; i <- i + 2 },
    "--append" = { opt$append <- TRUE; i <- i + 1 }, "--keep-y" = { opt$keep_y <- TRUE; i <- i + 1 },
    "-h" = , "--help" = { cat(paste(readLines(sub("--file=", "", grep("--file=", commandArgs(), value = TRUE)))[2:11], collapse = "\n"), "\n"); quit(status = 0) },
    stop("unknown option: ", a))
}
for (k in c("sample", "cnv", "sv", "out_cna", "out_sv")) if (is.null(opt[[k]])) stop("missing --", gsub("_", "-", k))
keep_chr <- c(as.character(1:22), "X", if (opt$keep_y) "Y")
strip <- function(x) sub("^chr", "", as.character(x))
## ---- copy number
cn <- read.delim(opt$cnv, check.names = FALSE, stringsAsFactors = FALSE)
need <- c("chromosome", "start", "end", "majorAlleleCopyNumber", "minorAlleleCopyNumber")
if (!all(need %in% names(cn))) stop("PURPLE cnv file lacks columns: ", paste(setdiff(need, names(cn)), collapse = ", "))
cn$chr <- strip(cn$chromosome); cn <- cn[cn$chr %in% keep_chr, ]
cna <- data.frame(samplename = opt$sample, chr = cn$chr, startpos = as.integer(cn$start), endpos = as.integer(cn$end),
                  nMaj1_A = pmax(0L, as.integer(round(cn$majorAlleleCopyNumber))),
                  nMin1_A = pmax(0L, as.integer(round(cn$minorAlleleCopyNumber))), frac1_A = 1L, stringsAsFactors = FALSE)
cna <- cna[order(match(cna$chr, keep_chr), cna$startpos), ]
## ---- structural variants
lines <- readLines(if (grepl("\\.gz$", opt$sv)) gzfile(opt$sv) else opt$sv)
lines <- lines[!startsWith(lines, "#")]
sv <- NULL
if (length(lines)) {
  f <- do.call(rbind, strsplit(lines, "\t", fixed = TRUE))
  v <- data.frame(chrom = strip(f[, 1]), pos = as.integer(f[, 2]), id = f[, 3], alt = f[, 5], filter = f[, 7], info = f[, 8], stringsAsFactors = FALSE)
  getinfo <- function(info, key) {
    r <- regexpr(paste0("(^|;)", key, "=[^;]*"), info, perl = TRUE); out <- rep(NA_character_, length(info))
    hit <- r > 0; out[hit] <- sub(paste0("^;?", key, "="), "", regmatches(info, r)); out
  }
  v$mate <- getinfo(v$info, "MATEID"); v$svtype <- getinfo(v$info, "SVTYPE")
  filters <- strsplit(opt$filters, ",")[[1]]
  v <- v[v$filter %in% filters & !is.na(v$mate), ]
  m <- regmatches(v$alt, regexec("^[ACGTNacgtn]*([][])([^:]+):([0-9]+)([][])[ACGTNacgtn]*$", v$alt))
  ok <- lengths(m) == 5
  v <- v[ok, ]; m <- m[ok]
  v$br1 <- sapply(m, `[`, 2); v$chrom2 <- strip(sapply(m, `[`, 3)); v$pos2 <- as.integer(sapply(m, `[`, 4))
  v$leading_base <- grepl("^[ACGTNacgtn]", v$alt)   # base before the bracket: N[p[ or N]p] ; otherwise [p[N or ]p]N
  v <- v[v$chrom %in% keep_chr & v$chrom2 %in% keep_chr, ]
  key <- ifelse(v$id < v$mate, paste(v$id, v$mate), paste(v$mate, v$id))
  rows <- split(seq_len(nrow(v)), key)
  classify <- function(idx) {
    r <- v[idx, , drop = FALSE]
    if (nrow(r) == 2) {  # pick the lower breakend
      o <- order(match(r$chrom, keep_chr), r$pos); r <- r[o[1], , drop = FALSE]
    }
    if (r$chrom != r$chrom2) cls <- "tra"
    else if (r$leading_base && r$br1 == "[") cls <- "del"      # N[p[  (+/-)
    else if (!r$leading_base && r$br1 == "]") cls <- "td"      # ]p]N  (-/+)
    else if (r$leading_base && r$br1 == "]") cls <- "h2h"      # N]p]  (+/+)
    else cls <- "t2t"                                           # [p[N  (-/-)
    data.frame(samplename = opt$sample, chr1 = r$chrom, pos1 = r$pos, chr2 = r$chrom2, pos2 = r$pos2, class = cls, stringsAsFactors = FALSE)
  }
  if (length(rows)) sv <- do.call(rbind, lapply(rows, classify))
}
if (is.null(sv)) sv <- data.frame(samplename = character(), chr1 = character(), pos1 = integer(), chr2 = character(), pos2 = integer(), class = character())
sv <- sv[order(match(sv$chr1, keep_chr), sv$pos1), ]
## ---- write
wr <- function(df, path) {
  app <- opt$append && file.exists(path) && file.size(path) > 0
  write.table(df, path, sep = "\t", quote = FALSE, row.names = FALSE, col.names = !app, append = app)
}
wr(cna, opt$out_cna); wr(sv, opt$out_sv)
cat(sprintf("[purple_to_ctcallr] %s: %d CN segments (%d chromosomes), %d SV pairs (%s) -> %s, %s\n", opt$sample, nrow(cna),
            length(unique(cna$chr)), nrow(sv), paste(sprintf("%s=%d", names(table(sv$class)), table(sv$class)), collapse = " "), opt$out_cna, opt$out_sv))
