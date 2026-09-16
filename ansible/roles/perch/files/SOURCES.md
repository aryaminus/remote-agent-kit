# Vendored sources — reading this before editing

`perch-approvals/` is vendored from the PUBLIC repo
[aryaminus/perch-site](https://github.com/aryaminus/perch-site/tree/main/perch-approvals)
(`pair.sh`, setup scripts and privacy pages live there too). The private
`aryaminus/perch` app repo is deliberately NOT referenced anywhere in this
project — every external link must resolve for strangers.

* Vendored: 2026-09-15, plugin version 0.1.0. Verified byte-identical to the
  upstream copy at vendor time.
* Re-vendor when the upstream changes: copy the two files again, update the
  version + date here, and note it in the commit message.
* Never edit the vendored files in place for local needs — fork or wrap
  instead, so the next re-vendor is a clean overwrite.
