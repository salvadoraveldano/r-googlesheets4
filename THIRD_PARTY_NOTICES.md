# Third-party notices

This skill **calls** the R packages below at run time. It does not copy or
redistribute their code, so their licenses are not bundled here. They are credited
because this project would not exist without them.

| Project | Authors / copyright holders | License | Link |
|---|---|---|---|
| googlesheets4 | Jennifer Bryan (creator); Posit Software, PBC | MIT | https://googlesheets4.tidyverse.org |
| gargle | Jennifer Bryan, Craig Citro (Google), Hadley Wickham; Google Inc and Posit Software, PBC | MIT | https://gargle.r-lib.org |
| googledrive | Lucy D'Agostino McGowan, Jennifer Bryan; Posit Software, PBC | MIT | https://googledrive.tidyverse.org |
| tidyverse | Hadley Wickham; Posit Software, PBC (formerly RStudio) | MIT | https://www.tidyverse.org |
| rig (referenced for installing R) | r-lib / Posit | MIT | https://github.com/r-lib/rig |
| httr | Hadley Wickham; Posit, PBC | MIT | https://httr.r-lib.org |
| glue | Jim Hester, Jennifer Bryan; Posit Software, PBC | MIT | https://glue.tidyverse.org |
| httpuv | Joe Cheng, Winston Chang; Posit, PBC and bundled-library contributors | **GPL (>= 2)** | https://github.com/rstudio/httpuv |

Attributions were checked against each package's installed DESCRIPTION. httpuv
(used by gargle to receive the OAuth redirect) is GPL-licensed; this skill only
calls it at run time and never bundles it, but if you redistribute a bundle that
includes it, GPL terms apply to that bundle. Check each package's LICENSE for
the authoritative text. If you vendor any of their code into this
repository, include their MIT notice alongside it.

This is an unofficial community project. It is not affiliated with, sponsored by,
or endorsed by Posit, the tidyverse team, or Google. "Google Sheets" and "Google
Drive" are trademarks of Google LLC.
