# Working rules

Core name GBA, author BitBird, logo EZ, identity BitBird.GBA, platform gba.
Preserve internal GBK_* compatibility identifiers and .gbkstat formats.
The current release has source-bound hashes matching the qualified playtime
candidate. Only the older November 4 baseline had an independent byte-identical
standalone rebuild. Do not replace source baselines or relax timing constraints
without appropriate qualification.
Use fresh output directories, bounded subprocesses, explicit result receipts
and appropriate simulation/timing checks for future RTL changes.

Keep launch drafts, private checklists, historical trial ZIPs and private logs
outside tracked source. Generated build and package outputs belong in build/.
Do not publish releases or change repository visibility without owner approval.
