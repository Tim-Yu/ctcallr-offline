#!/usr/bin/env Rscript
# purple_to_ctcallr.R - kept for compatibility: forwards to make_ctcallr_input.R (--purple-cnv/--purple-sv accepted there).
a <- commandArgs(trailingOnly = TRUE); me <- sub("--file=", "", grep("--file=", commandArgs(), value = TRUE))
q <- system2("Rscript", c(file.path(dirname(me), "make_ctcallr_input.R"), shQuote(a))); quit(status = q)
