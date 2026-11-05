# Working rules

Core name GBA, author BitBird, logo EZ, identity BitBird.GBA, platform gba.
Preserve internal GBK_* compatibility identifiers and .gbkstat formats.
The release baseline has source-bound hashes and a byte-identical standalone
build. Do not silently replace that baseline or relax timing constraints.
Use fresh output directories, bounded subprocesses, explicit result receipts
and appropriate simulation/timing checks for future RTL changes.

Keep launch drafts, private checklists, historical trial ZIPs and private logs
outside tracked source. Generated build and package outputs belong in build/.
Do not publish releases or change repository visibility without owner approval.
