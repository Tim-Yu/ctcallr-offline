# Licences of the redistributed components (research use)

| Component | Version | Licence |
| --- | --- | --- |
| CTCallR (galder-max/CTCallR, commit bb428d2) | 1.0 | GPL-3 (`LICENSE-CTCallR-GPL-3.txt`) |
| copynumber (Bioconductor, last release, from git.bioconductor.org RELEASE_3_17) | 1.40.0 | Artistic-2.0 |
| GenomicRanges, IRanges, S4Vectors, BiocGenerics, GenomeInfoDb, XVector (Bioconductor 3.20) | as in `docs/VERSIONS.txt` | Artistic-2.0 |
| vcd, EMT, RColorBrewer, lmtest, zoo, colorspace, MASS (CRAN) | as in `docs/VERSIONS.txt` | GPL-2/GPL-3 (vcd, EMT, lmtest, zoo, MASS), Apache-2.0 (RColorBrewer), BSD-3 (colorspace) |
| R | 4.4.3 | GPL-2/GPL-3 |
| Circos (Ubuntu package `circos` 0.69.9+dfsg-2, with its Perl module dependencies) | 0.69.9 | GPL-2+ (Circos), Perl modules under Artistic/GPL |
| Base image rocker/r-ver:4.4.3 (Ubuntu 24.04) | | GPL-2 (rocker scripts), Ubuntu component licences |

The Singularity image bundles all of the above unchanged. Each R package carries its own licence file in the image under
`/usr/local/lib/R/site-library/<pkg>/` and in the shipped `r-src/` source tarballs. No proprietary software, no licence
keys, no reference downloads are involved: CTCallR only needs the hg19/hg38 karyotype files bundled in its own `inst/`.
