#!/usr/bin/env Rscript
# make_ctcallr_input.R - build the two CTCallR input tables for one sample from
#   copy number : --battenberg-subclones <sample>_subclones.txt   (Battenberg; nMaj1_A/nMin1_A/frac1_A copied as they are)
#              or --purple-cnv <sample>.purple.cnv.somatic.tsv      (hmftools PURPLE; major/minor CN rounded, frac1_A = 1)
#   SVs         : --sv-vcf <file.vcf[.gz]>  breakend (BND) VCF with MATEID, e.g. <sample>.purple.sv.vcf.gz, ESVEE/GRIDSS output
# Usage:
#   Rscript make_ctcallr_input.R --sample NAME (--battenberg-subclones F | --purple-cnv F) --sv-vcf F \
#                                --out-cna allCNAs.txt --out-sv allSVs.txt [--append] [--filters PASS] [--keep-y]
# Output columns: CNA  samplename chr startpos endpos nMaj1_A nMin1_A frac1_A   (chr without "chr", 1-22 and X)
#                 SV   samplename chr1 pos1 chr2 pos2 class  with class del/td/h2h/t2t/tra from the bracket notation of the
#                      lower breakend (N[p[ del, ]p]N td, N]p] h2h, [p[N t2t; different chromosomes tra); PASS pairs only by default
args <- commandArgs(trailingOnly = TRUE)
opt <- list(sample = NULL, bb = NULL, cnv = NULL, sv = NULL, out_cna = NULL, out_sv = NULL, append = FALSE, filters = "PASS", keep_y = FALSE)
i <- 1
while (i <= length(args)) {
  a <- args[i]; v <- if (i < length(args)) args[i + 1] else NA
  switch(a,
    "--sample" = { opt$sample <- v; i <- i + 2 }, "--battenberg-subclones" = { opt$bb <- v; i <- i + 2 },
    "--purple-cnv" = { opt$cnv <- v; i <- i + 2 }, "--sv-vcf" = , "--purple-sv" = { opt$sv <- v; i <- i + 2 },
    "--out-cna" = { opt$out_cna <- v; i <- i + 2 }, "--out-sv" = { opt$out_sv <- v; i <- i + 2 }, "--filters" = { opt$filters <- v; i <- i + 2 },
    "--append" = { opt$append <- TRUE; i <- i + 1 }, "--keep-y" = { opt$keep_y <- TRUE; i <- i + 1 },
    "-h" = , "--help" = { cat(paste(readLines(sub("--file=", "", grep("--file=", commandArgs(), value = TRUE)))[2:12], collapse = "\n"), "\n"); quit(status = 0) },
    stop("unknown option: ", a))
}
for (k in c("sample", "sv", "out_cna", "out_sv")) if (is.null(opt[[k]])) stop("missing --", gsub("_", "-", k))
if (is.null(opt$bb) == is.null(opt$cnv)) stop("give exactly one of --battenberg-subclones or --purple-cnv")
keep_chr <- c(as.character(1:22), "X", if (opt$keep_y) "Y")
strip <- function(x) sub("^chr", "", as.character(x))
## ---- copy number
if (!is.null(opt$bb)) {
  bb <- read.delim(opt$bb, check.names = FALSE, stringsAsFactors = FALSE)
  need <- c("chr", "startpos", "endpos", "nMaj1_A", "nMin1_A", "frac1_A")
  if (!all(need %in% names(bb))) stop("Battenberg subclones file lacks columns: ", paste(setdiff(need, names(bb)), collapse = ", "))
  bb$chr <- strip(bb$chr); bb <- bb[bb$chr %in% keep_chr, ]
  cna <- data.frame(samplename = opt$sample, chr = bb$chr, startpos = as.integer(bb$startpos), endpos = as.integer(bb$endpos),
                    nMaj1_A = as.integer(round(bb$nMaj1_A)), nMin1_A = as.integer(round(bb$nMin1_A)), frac1_A = as.numeric(bb$frac1_A), stringsAsFactors = FALSE)
  cna <- cna[!is.na(cna$nMaj1_A) & !is.na(cna$nMin1_A), ]
  cn_source <- sprintf("Battenberg %s", basename(opt$bb))
} else {
  cn <- read.delim(opt$cnv, check.names = FALSE, stringsAsFactors = FALSE)
  need <- c("chromosome", "start", "end", "majorAlleleCopyNumber", "minorAlleleCopyNumber")
  if (!all(need %in% names(cn))) stop("PURPLE cnv file lacks columns: ", paste(setdiff(need, names(cn)), collapse = ", "))
  cn$chr <- strip(cn$chromosome); cn <- cn[cn$chr %in% keep_chr, ]
  cna <- data.frame(samplename = opt$sample, chr = cn$chr, startpos = as.integer(cn$start), endpos = as.integer(cn$end),
                    nMaj1_A = pmax(0L, as.integer(round(cn$majorAlleleCopyNumber))), nMin1_A = pmax(0L, as.integer(round(cn$minorAlleleCopyNumber))),
                    frac1_A = 1, stringsAsFactors = FALSE)
  cn_source <- sprintf("PURPLE %s", basename(opt$cnv))
}
cna <- cna[order(match(cna$chr, keep_chr), cna$startpos), ]
## ---- structural variants (breakend VCF)
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
  v$mate <- getinfo(v$info, "MATEID")
  filters <- strsplit(opt$filters, ",")[[1]]
  v <- v[v$filter %in% filters & !is.na(v$mate), ]
  m <- regmatches(v$alt, regexec("^[ACGTNacgtn]*([][])([^:]+):([0-9]+)([][])[ACGTNacgtn]*$", v$alt))
  ok <- lengths(m) == 5; v <- v[ok, ]; m <- m[ok]
  v$br1 <- sapply(m, `[`, 2); v$chrom2 <- strip(sapply(m, `[`, 3)); v$pos2 <- as.integer(sapply(m, `[`, 4))
  v$leading_base <- grepl("^[ACGTNacgtn]", v$alt)
  v <- v[v$chrom %in% keep_chr & v$chrom2 %in% keep_chr, ]
  if (nrow(v)) {
    key <- ifelse(v$id < v$mate, paste(v$id, v$mate), paste(v$mate, v$id))
    classify <- function(idx) {
      r <- v[idx, , drop = FALSE]
      if (nrow(r) == 2) { o <- order(match(r$chrom, keep_chr), r$pos); r <- r[o[1], , drop = FALSE] }
      cls <- if (r$chrom != r$chrom2) "tra" else if (r$leading_base && r$br1 == "[") "del" else if (!r$leading_base && r$br1 == "]") "td" else if (r$leading_base && r$br1 == "]") "h2h" else "t2t"
      data.frame(samplename = opt$sample, chr1 = r$chrom, pos1 = r$pos, chr2 = r$chrom2, pos2 = r$pos2, class = cls, stringsAsFactors = FALSE)
    }
    sv <- do.call(rbind, lapply(split(seq_len(nrow(v)), key), classify))
  }
}
if (is.null(sv)) sv <- data.frame(samplename = character(), chr1 = character(), pos1 = integer(), chr2 = character(), pos2 = integer(), class = character())
sv <- sv[order(match(sv$chr1, keep_chr), sv$pos1), ]
wr <- function(df, path) { app <- opt$append && file.exists(path) && file.size(path) > 0
  write.table(df, path, sep = "\t", quote = FALSE, row.names = FALSE, col.names = !app, append = app) }
wr(cna, opt$out_cna); wr(sv, opt$out_sv)
cat(sprintf("[make_ctcallr_input] %s: %d CN segments from %s (%d subclonal), %d SV pairs (%s) -> %s, %s\n", opt$sample, nrow(cna), cn_source,
            sum(cna$frac1_A < 1), nrow(sv), paste(sprintf("%s=%d", names(table(sv$class)), table(sv$class)), collapse = " "), opt$out_cna, opt$out_sv))
