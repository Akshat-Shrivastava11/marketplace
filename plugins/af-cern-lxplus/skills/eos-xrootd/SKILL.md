---
name: eos-xrootd
description: >-
  Use when reading, writing, copying, verifying or deleting files on
  CERN EOS (eoscms, eosuser) or FNAL EOS (cmseos) from login nodes, batch
  or grid jobs: building root:// URLs, xrdcp/xrdfs/eos CLI commands,
  checksum-verified copies, FUSE vs xrootd in jobs, quota checks (eos
  quota, inode quota), bulk deletes and the CMS recycle bin, sharing via
  the www area, uproot over root://, or errors such as "MGM
  root://localhost not online/reachable", "Operation expired", "Redirect
  limit has been reached", "No servers are available to read the file",
  "[3021] Unable to get quota space" or being mapped to user nobody.
metadata:
  summary: "EOS and xrootd at CERN and FNAL: URLs, verified copies, FUSE pitfalls, quotas, recycle-bin etiquette"
---

# EOS and xrootd

## Overview

EOS is reached two ways: the `/eos` FUSE mount (fine for reading on
lxplus) and xrootd (`root://` URLs with `xrdcp`, `xrdfs`, `eos`). In jobs,
write with `xrdcp` and verify size and checksum; never write through FUSE.
eoscms and eosuser are separate instances with separate quotas, and the CMS
recycle bin is shared by everyone, so check quotas before a large run and
pace bulk deletes.

Field notes collected by [DickyChant](https://gist.github.com/DickyChant/5c2a7a8db793a129ae8f637b9c6dfe1a) from about 25 Claude Code
sessions running CMS work at CERN (Oct–Nov 2026). Every item was hit in
practice; where sessions disagreed, both observations are kept.

## When to Use

- Copying outputs to or from EOS (CERN or FNAL), in jobs or by hand
- A file that is "there" but unreadable, truncated or a stub
- Quota errors, or before a large run or bulk delete
- Reading EOS files with ROOT or uproot over xrootd

## Instances and URLs

- `/eos/cms/...` → `root://eoscms.cern.ch//eos/cms/...`; `/eos/user/...` → `root://eosuser.cern.ch//eos/user/...`; FNAL → `root://cmseos.fnal.gov//store/...`. Note the double slash. eoscms and eosuser are different instances, with different quotas.
- For the `eos` CLI on /eos/cms, set `EOS_MGM_URL=root://eoscms.cern.ch`, or pass it explicitly: `eos root://eoscms.cern.ch ls -l /eos/cms/...`.
- `xrdfs` takes host and path separately (`xrdfs root://eoscms.cern.ch stat /eos/cms/...`); `xrdcp` takes full URLs. When splitting `root://host//path`, normalize the slashes.
- Check who you are: `xrdcp -s "root://eoscms.cern.ch//proc/user/?mgm.cmd=whoami" -`. With an expired proxy eosuser maps you to `nobody` (uid 65534).

## FUSE vs xrootd

- On lxplus, reading through the `/eos` FUSE mount is fine. In jobs, **write with xrdcp, never through FUSE**: ROOT files written onto FUSE came out partly damaged, with some branches readable and others not.
- FUSE has transient failures under load: 24 of 25 "corrupt" files read fine on retry, and fresh files can show `-?????????` for minutes. Retry with backoff, then fail. Never skip silently: a catch-all `except` once dropped 35 of 429 inputs. Confirm with `xrdfs stat` before calling an output missing.
- On batch workers `/eos/user` is usually mounted, but `/eos/cms` may not be readable. Stage inputs with `xrdcp` to `$_CONDOR_SCRATCH_DIR`.
- Don't mount or probe /eos FUSE from a small local box: hanging reads spawn eosxd daemons until memory runs out.
- Don't read files while a copy into them is running: you'll see half-written files or zombie ROOT files. Wait for the copy's done marker.

## Copying reliably

- Pattern: `xrdfs <host> mkdir -p <dir>` (xrdcp into a missing dir fails, unless you pass `--path`), then `xrdcp -f -s --posc --cksum adler32 <src> <dst>`, with a retry loop (e.g. 6 tries, 20 s apart).
- Verify each file after copying: remote size (`xrdfs stat`) and checksum (`xrdfs query checksum` vs local `xrdadler32`). Log OK, MISMATCH or COPYFAIL per file and end with `DONE nbad=N`.
- `xrdadler32` is in `/usr/bin` on lxplus but not in the LCG views (LCG_106 checked), so don't assume it in jobs. Where it's missing: `python3 -c "import zlib,sys; print('%08x' % zlib.adler32(open(sys.argv[1],'rb').read()))" <file>` (whole-file read; fine for small outputs).
- Bulk moves: `xrdcp -r --parallel 16 root://eosuser...//src root://eoscms...//dst`. Compare file count and bytes on both sides before deleting the source. Copying and deleting the source are separate approvals.
- Cross-site (IHEP → FNAL): `xrdcp --cksum adler32:source --posc --path --retry 2`. Skip files already present at the right size. Try the site endpoint before `cms-xrd-global`.
- `scp` onto /eos keeps the local mode (0600 files end up unreadable to others); xrdcp gives 0644. Check modes on other people's areas too: listable is not readable.
- Check sizes, not just names: some "present" merged files were 1 kB stubs from a failed hadd.
- Don't guess path prefixes or tags. List the parent dir first.
- Merge EDM4hep/PODIO files with PODIO's merger, never bare hadd.

## Quotas

- Check: `EOS_MGM_URL=root://eosuser.cern.ch eos quota <path>` (eoscms for /eos/cms; or `eos quota -m`). Without the right `EOS_MGM_URL` it answers `error: no quota for path ...`, which doesn't mean there is no quota. EOS shows raw bytes at 2× logical; the enforced number is used/max **logical** bytes. The user quota binds even inside a large group quota.
- FNAL EOS: `eosquota` on a cmslpc node (no CERN-side command).
- **Full quota is a hard stop.** `vol-status exceeded` (100% filled) makes every write fail with `[3021] Unable to get quota space ... Disk quota exceeded`. Retrying doesn't help. Check quota before submitting; if a test job hits this, stop, don't submit the campaign, and ask the user to free space or pick another area (e.g. FNAL EOS with a proxy; see `lxplus-htcondor` credentials). Never delete the user's files to make room.
- `/eos/cms/store/user/<u>`: 1 TB logical. When it's full, CRAB stageout fails (HTTP 507 / exit 60323) and new tasks come back SUBMITREFUSED.
- `/eos/user` (1 TB) filled from unrelated folders and killed jobs at their final copy. Check before long runs, and copy partial outputs as you go.
- Group areas may have no per-user quota, which suits archives. Some are **write-once** (ACL `rw!d`, e.g. phys_bphys; phys_generator): members can create but not delete. Never put test files or write probes there.
- `eos mv` between group quota nodes is an instant rename that moves the usage, with no copy.
- `/eos/user/<u>/<user>/www` is public and counts against the user quota.

## Deleting at scale

- The CMS recycle bin is shared by all of CMS (100M inodes, 5 PB, 30-day lifetime; `eos recycle -m`). Mass deletes can fill it for everyone, and users can't purge it. Pace deletes against a cap; your entries free up only after 30 days.
- `eos rm -r` refuses trees above ~90k entries ("query limit"). Remove subdirectories bottom-up.
- Undo: `eos recycle ls` shows the restore keys (`pxid:...`); `eos recycle restore <key>` restores.
- The parent `treefiles` count lags after big removals; sum the child dirs instead.
- Wrap `eos` calls in `timeout`: 300 s hangs on `eos ls` / `eos quota` were seen.

## Unattended access

- Cron uses `FILE:/tmp/krb5cc_<uid>`, and tickets renew for at most 5 days, so plan a manual `kinit` (or a keytab).
- Grid proxies for xrootd: keep one on AFS/EOS readable from where it's used (`chmod 600`), and set `X509_USER_PROXY` to it, not `/tmp/x509up_u*` (node-local). Check both `voms-proxy-info -timeleft` and `-actimeleft`.
- `xrdfs stat` succeeds even with an expired proxy. Test real access by opening a file.
- Never copy grid proxies or keys between sites or into shared places on your own. Prefer `voms-proxy-init` where the proxy is used; if the user decides to move one (e.g. LPC → lxplus for FNAL writes), put it in a private AFS dir (`~/private`, `chmod 600`) and tell them where it is so they can delete it.

## Gotchas

More field notes, each from a real failure.

- **Checksums in one call:** `eos find -f --checksum <dir>` lists the stored adler32 of every file. Compare with `xrdadler32` on the copies.
- **ROOT and FUSE:** ROOT redirects `/eos` FUSE paths to `root://`, and opening just-written files that way hung. `ROOT.gEnv.SetValue("TFile.CrossProtocolRedirects", 0)` fixes it.
- **IPv4:** from a laptop or desktop, set `XRD_NETWORKSTACK=IPv4`. eoscms resolved IPv6 first, which went over slow WiFi and was ~50× slower.
- **uproot over root://** needs `fsspec-xrootd`. For large reads use `handler=uproot.source.xrootd.MultithreadedXRootDSource`, because the fsspec backend timed out mid-stream. For one-off reads, xrdcp locally first.
- **Print a remote file:** `xrdcp -s -f root://.../file -` (writing to `/dev/stdout` fails). FUSE `ls` on /eos/cms can hang; `xrdfs ... ls -l` is safer, and its times are UTC.
- **Inode quotas:** these are per group node and shared. Per-chunk dumps created 46M files and nearly filled a shared node (`[3021] Unable to get quota space`; the same error comes from a full byte quota, see Quotas). Before a campaign, count a canary job's files (`eos find --count`) × number of jobs, compare with `eos quota ls -m`, and write one merged file per job.
- **Listing caps:** `eos find` and an unscoped `eos recycle ls` stop at 100k entries; use `eos recycle ls -m <YYYY/MM/DD>`.
- **Symlinked areas:** `/store/user/<x>` or `/store/group/<g>` can be EOS symlinks, and `xrdfs ls -l` on the link shows a tiny root-owned file. List a path below it.
- **Start-burst errors:** `Operation expired` at file open hits bursts of hundreds of jobs. Frameworks with `--skipbadfiles`-style validation drop the file and exit 0 (5.6k of 59k files lost in one pass). Grep for the validation errors, compare processed with input files, and recover only the dropped ones.
- **Redirectors:** "Redirect limit has been reached" through the global/INFN redirectors is intermittent. Rewrite inputs that have a CERN replica to `root://eoscms.cern.ch`, and fall back to `cmsxrootd.fnal.gov`.
- **Lost files:** `No servers are available to read the file` can mean 0 replicas while DBS still says valid; check Rucio. A file corrupt through every redirector should be excluded and recorded, not retried.
- **Read path in jobs:** FUSE reads from batch nodes stalled (42 min CPU in 9.6 h). Use `root://` URLs in input lists.
- **Auth:** on the CERN network a Kerberos ticket alone reads eoscms; no proxy is needed. With a grid proxy, eosuser maps you to `nobody`. Losing the ticket kills FUSE access mid-job.
- **Publishing a file atomically:** write `dir/.f.tmp`, then `mv` it to `dir/f`. Write archives to a temporary name and verify them (`gzip -t`, entry count) before removing the source: a quota hit left a truncated tgz.
- **Archiving AFS to EOS:** `tar --zstd`, restored with `xrdcp root://...x.tar.zst - | zstd -dc | tar -xf -`.
- **Sharing:** `/eos/user/<u>/<user>` is `drwx------`; share through the www dir. A copy into `www/<sub>/` is served immediately at `<user>.web.cern.ch/<sub>/`.
- **Moving data from CMS Connect** without proxy writes: `ssh cmscon 'tar cf - -C dir x' | ssh lxplus 'tar xf - -C /eos/...'`.
- **Gridpacks:** new PdmV gridpacks on EOS may not be on /cvmfs for weeks; xrdcp them from EOS in the job.
- **Bulk DAS download pattern:** `dasgoclient -query="file dataset=<ds>" | xargs -P 8 -I{} sh -c 'timeout 300 xrdcp -s root://cms-xrd-global.cern.ch/{} . || echo FAIL {}'`.
- **Rucio:** `source /cvmfs/cms.cern.ch/rucio/setup-py3.sh; export RUCIO_ACCOUNT=<cern user>`, then `rucio rule add cms:<ds> --rses T2_CH_CERN --copies 1 --lifetime <s> --activity "User AutoApprove" --ask-approval --asynchronous`.
- **Empty is not missing:** an empty branch isn't a missing one (`nLHEScaleWeight == 0` in a whole file).
- **NanoAOD merging:** `hadd -fk` keeps the Runs tree; normalise with sum(`Runs.genEventSumw`) and check the entry counts.
- **eos CLI not connected:** "MGM root://localhost not online/reachable" means `EOS_MGM_URL` isn't set (eosuser for /eos/user, eoscms for /eos/cms).
- **Directory sizes:** `eos ls -la <dir>` shows the recursive size of each directory instantly. `du` over FUSE is very slow.
- **Truncated find:** `eos find -f --size` truncates at 100k files / 50k dirs ("Result is truncated!"). Run it per top-level subdirectory and check stderr.
- **Old versions** live in hidden `.sys.v#.<name>/` dirs and count against quota (~10 GB seen). Removing them is safe, since they go to the recycle bin.
- **Grepping many files over FUSE hangs:** list with `eos find` first, filter to small text files, then `xargs -P` grep. Batch deletes: `xargs -0 -P 8 eos rm` handles ~10k files in minutes, within the recycle-bin etiquette above.

## Docs

- XRootD client (xrdcp, xrdfs): <https://xrootd.web.cern.ch/doc/man/xrdcp.1.html>
- EOS CLI: <https://eos-docs.web.cern.ch/>
- EOS at the LPC: <https://uscms.org/uscms_at_work/computing/LPC/usingEOSAtLPC.shtml>
- Source field notes (DickyChant): <https://gist.github.com/DickyChant/5c2a7a8db793a129ae8f637b9c6dfe1a>
