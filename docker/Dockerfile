# CTCallR offline image: R 4.4.3 + Bioconductor 3.20 + copynumber 1.40.0 (last Bioconductor release) + Circos 0.69.9 + CTCallR
FROM rocker/r-ver:4.4.3
ARG CTCALLR_COMMIT=unknown
LABEL org.opencontainers.image.title="ctcallr" \
      org.opencontainers.image.description="CTCallR chromothripsis caller (galder-max/CTCallR) with all R dependencies and Circos" \
      org.opencontainers.image.source="https://github.com/galder-max/CTCallR" \
      ctcallr.commit="${CTCALLR_COMMIT}" \
      ctcallr.copynumber="1.40.0 from git.bioconductor.org RELEASE_3_17 (0c087dac)"
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8 TZ=Etc/UTC
# Circos and its Perl modules come from Ubuntu 24.04; dev libraries for compiling Bioconductor packages
RUN apt-get update && apt-get install -y --no-install-recommends \
      circos fonts-cmu fonts-circos-symbols liblist-moreutils-perl patch \
      build-essential zlib1g-dev libbz2-dev liblzma-dev libcurl4-openssl-dev libssl-dev libxml2-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /etc/circos /etc/circos/etc \
    && circos -modules | tee /tmp/circos_modules.txt && ! grep -q "^missing" /tmp/circos_modules.txt \
    && circos -v 2>&1 | head -3
# CRAN packages from the rocker p3m snapshot (binary), then Bioconductor 3.20
RUN Rscript -e 'install.packages(c("vcd","EMT","RColorBrewer","BiocManager"), Ncpus = 4); ok <- sapply(c("vcd","EMT","RColorBrewer","BiocManager"), requireNamespace, quietly = TRUE); print(ok); stopifnot(all(ok))'
RUN Rscript -e 'BiocManager::install(c("GenomicRanges","IRanges"), version = "3.20", update = FALSE, ask = FALSE, Ncpus = 4); stopifnot(requireNamespace("GenomicRanges", quietly = TRUE))'
# copynumber was removed from Bioconductor 3.18; install the last release from its Bioconductor git export
COPY context/copynumber_1.40.0_bioc-RELEASE_3_17.tar.gz /opt/src/
RUN R CMD INSTALL /opt/src/copynumber_1.40.0_bioc-RELEASE_3_17.tar.gz && Rscript -e 'stopifnot(packageVersion("copynumber") == "1.40.0")'
# CTCallR from the pinned source checkout, plus the bundle patch (empty result table instead of a crash when no
# high-density region is flagged in any sample; see patches/ and docs)
COPY context/CTCallR /opt/src/CTCallR
COPY context/patches /opt/src/patches
RUN cd /opt/src/CTCallR && for p in /opt/src/patches/*.patch; do patch -p1 < "$p"; done && R CMD INSTALL /opt/src/CTCallR && Rscript -e 'library(CTCallR); cat("CTCallR", as.character(packageVersion("CTCallR")), "\n")'
COPY context/ctcallr_run.R context/circos_build.sh context/audit_deps.R /opt/ctcallr/
RUN chmod +x /opt/ctcallr/circos_build.sh /opt/ctcallr/ctcallr_run.R && Rscript /opt/ctcallr/audit_deps.R
ENV CTCALLR_CIRCOS=/usr/bin/circos
WORKDIR /data
ENTRYPOINT ["Rscript", "/opt/ctcallr/ctcallr_run.R"]
CMD ["--help"]
