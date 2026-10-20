# audit_deps.R - run inside the image: verify every package CTCallR needs is installed, print versions.
deps <- c("CTCallR", "vcd", "MASS", "copynumber", "parallel", "EMT", "GenomicRanges", "IRanges", "RColorBrewer")
ip <- installed.packages()
missing <- deps[!deps %in% rownames(ip)]
if (length(missing)) stop("MISSING packages: ", paste(missing, collapse = ", "))
for (p in deps) suppressPackageStartupMessages(library(p, character.only = TRUE))
# functions referenced via require() in the package source must all resolve
src <- paste(unlist(lapply(ls(asNamespace("CTCallR")), function(f) deparse(get(f, asNamespace("CTCallR"))))), collapse = "\n")
req <- unique(regmatches(src, gregexpr("(?<=require\\()[A-Za-z0-9.]+", src, perl = TRUE))[[1]])
cat("require() calls in CTCallR source:", paste(req, collapse = ", "), "\n")
bad <- req[!req %in% rownames(ip)]
if (length(bad)) stop("require()d but not installed: ", paste(bad, collapse = ", "))
closure <- unique(c(deps, unlist(tools::package_dependencies(deps, db = ip, recursive = TRUE))))
closure <- setdiff(closure, c(rownames(ip)[ip[, "Priority"] %in% "base"]))
cat(sprintf("%d packages in the dependency closure (non-base):\n", length(closure)))
tab <- ip[closure[closure %in% rownames(ip)], c("Package", "Version"), drop = FALSE]
cat(sprintf("  %-22s %s\n", tab[, "Package"], tab[, "Version"]), sep = "")
cat("circos:", system("circos -v 2>&1 | head -1", intern = TRUE), "\n")
cat("R:", R.version.string, "| BiocManager version:", as.character(BiocManager::version()), "\n")
cat("AUDIT OK\n")
