#!/usr/bin/env Rscript
# make_ctcallr_input.R - build the two CTCallR input tables for one sample from
#   copy number : --battenberg-subclones <sample>_subclones.txt   (Battenberg; nMaj1_A/nMin1_A/frac1_A copied as they are)
#              or --purple-cnv <sample>.purple.cnv.somatic.tsv      (hmftools PURPLE; major/minor CN rounded, frac1_A = 1)
#   SVs         : --sv-vcf <file.vcf[.gz]>  breakend (BND) VCF with MATEID, e.g. <sample>.purple.sv.vcf.gz, ESVEE/GRIDSS output
#              or --sv-bedpe <file.bedpe>    BEDPE with header (chrom1 start1 end1 chrom2 start2 end2 ... strand1 strand2 svclass ...),
#                                            e.g. the GEL consensus calls <TumourID>.somatic.sv.bedpe
# Usage:
#   Rscript make_ctcallr_input.R --sample NAME (--battenberg-subclones F | --purple-cnv F) (--sv-vcf F | --sv-bedpe F) \
#                                --out-cna allCNAs.txt --out-sv allSVs.txt [--append] [--filters PASS] [--keep-y]
# Output columns: CNA  samplename chr startpos endpos nMaj1_A nMin1_A frac1_A   (chr without "chr", 1-22 and X)
#                 SV   samplename chr1 pos1 chr2 pos2 class  with class del/td/h2h/t2t/tra. VCF: from the bracket notation of
#                      the lower breakend (N[p[ del, ]p]N td, N]p] h2h, [p[N t2t); BEDPE: from the strand pair of the lower
#                      breakend (+- del, -+ td, ++ h2h, -- t2t), falling back to svclass (DEL/DUP/TRA; INV without strands -> inv);
#                      different chromosomes -> tra. VCF rows: PASS only by default (--filters).
args <- commandArgs(trailingOnly = TRUE)
opt <- list(sample = NULL, bb = NULL, cnv = NULL, sv = NULL, bedpe = NULL, out_cna = NULL, out_sv = NULL, append = FALSE, filters = "PASS", keep_y = FALSE)
i <- 1
while (i <= length(args)) {
  a <- args[i]; v <- if (i < length(args)) args[i + 1] else NA
  switch(a,
    "--sample" = { opt$sample <- v; i <- i + 2 }, "--battenberg-subclones" = { opt$bb <- v; i <- i + 2 },
    "--purple-cnv" = { opt$cnv <- v; i <- i + 2 }, "--sv-vcf" = , "--purple-sv" = { opt$sv <- v; i <- i + 2 }, "--sv-bedpe" = { opt$bedpe <- v; i <- i + 2 },
    "--out-cna" = { opt$out_cna <- v; i <- i + 2 }, "--out-sv" = { opt$out_sv <- v; i <- i + 2 }, "--filters" = { opt$filters <- v; i <- i + 2 },
    "--append" = { opt$append <- TRUE; i <- i + 1 }, "--keep-y" = { opt$keep_y <- TRUE; i <- i + 1 },
    "-h" = , "--help" = { cat(paste(readLines(sub("--file=", "", grep("--file=", commandArgs(), value = TRUE)))[2:12], collapse = "\n"), "\n"); quit(status = 0) },
    stop("unknown option: ", a))
}
for (k in c("sample", "out_cna", "out_sv")) if (is.null(opt[[k]])) stop("missing --", gsub("_", "-", k))
if (is.null(opt$bb) == is.null(opt$cnv)) stop("give exactly one of --battenberg-subclones or --purple-cnv")
if (is.null(opt$sv) == is.null(opt$bedpe)) stop("give exactly one of --sv-vcf or --sv-bedpe")
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
## ---- structural variants
sv <- NULL
if (!is.null(opt$bedpe)) {
  ## BEDPE with header; strands may be written as + / - / ['+'] / . ; positions: end1/end2 are the 1-based breakpoints
  b <- read.delim(opt$bedpe, check.names = FALSE, stringsAsFactors = FALSE, comment.char = "")
  names(b) <- sub("^#", "", names(b))
  need <- c("chrom1", "start1", "end1", "chrom2", "start2", "end2")
  if (!all(need %in% names(b))) stop("BEDPE lacks columns: ", paste(setdiff(need, names(b)), collapse = ", "))
  strand_of <- function(x) { x <- gsub("[^+-]", "", as.character(x)); ifelse(nchar(x) == 1, x, NA_character_) }
  s1 <- if ("strand1" %in% names(b)) strand_of(b$strand1) else rep(NA_character_, nrow(b))
  s2 <- if ("strand2" %in% names(b)) strand_of(b$strand2) else rep(NA_character_, nrow(b))
  cls_col <- if ("svclass" %in% names(b)) toupper(as.character(b$svclass)) else rep(NA_character_, nrow(b))
  d <- data.frame(c1 = strip(b$chrom1), p1 = as.integer(b$end1), c2 = strip(b$chrom2), p2 = as.integer(b$end2), s1 = s1, s2 = s2, svclass = cls_col, stringsAsFactors = FALSE)
  d <- d[d$c1 %in% keep_chr & d$c2 %in% keep_chr, ]
  if (nrow(d)) {
    # order each pair so that breakend 1 is the lower one (chromosome order, then position)
    swap <- match(d$c1, keep_chr) > match(d$c2, keep_chr) | (d$c1 == d$c2 & d$p1 > d$p2)
    d[swap, c("c1", "p1", "s1", "c2", "p2", "s2")] <- d[swap, c("c2", "p2", "s2", "c1", "p1", "s1")]
    cls <- ifelse(d$c1 != d$c2, "tra",
           ifelse(!is.na(d$s1) & !is.na(d$s2),
                  ifelse(d$s1 == "+" & d$s2 == "-", "del", ifelse(d$s1 == "-" & d$s2 == "+", "td", ifelse(d$s1 == "+" & d$s2 == "+", "h2h", "t2t"))),
                  ifelse(d$svclass %in% c("DEL", "DELETION"), "del", ifelse(d$svclass %in% c("DUP", "TANDEMDUP", "TD"), "td",
                         ifelse(d$svclass %in% c("TRA", "BND", "TRANSLOCATION"), "tra", ifelse(d$svclass %in% c("INV", "INVERSION"), "inv", "unknown"))))))
    sv <- data.frame(samplename = opt$sample, chr1 = d$c1, pos1 = d$p1, chr2 = d$c2, pos2 = d$p2, class = cls, stringsAsFactors = FALSE)
    n_nostrand <- sum(is.na(d$s1) | is.na(d$s2))
    if (n_nostrand) cat(sprintf("[make_ctcallr_input] note: %d of %d SVs had no strand information; class taken from svclass (INV -> inv, not counted as h2h/t2t)\n", n_nostrand, nrow(d)))
  }
} else {
lines <- readLines(if (grepl("\\.gz$", opt$sv)) gzfile(opt$sv) else opt$sv)
lines <- lines[!startsWith(lines, "#")]
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
}
if (is.null(sv)) sv <- data.frame(samplename = character(), chr1 = character(), pos1 = integer(), chr2 = character(), pos2 = integer(), class = character())
sv <- sv[order(match(sv$chr1, keep_chr), sv$pos1), ]
wr <- function(df, path) { app <- opt$append && file.exists(path) && file.size(path) > 0
  write.table(df, path, sep = "\t", quote = FALSE, row.names = FALSE, col.names = !app, append = app) }
wr(cna, opt$out_cna); wr(sv, opt$out_sv)
cat(sprintf("[make_ctcallr_input] %s: %d CN segments from %s (%d subclonal), %d SV pairs (%s) -> %s, %s\n", opt$sample, nrow(cna), cn_source,
            sum(cna$frac1_A < 1), nrow(sv), paste(sprintf("%s=%d", names(table(sv$class)), table(sv$class)), collapse = " "), opt$out_cna, opt$out_sv))
