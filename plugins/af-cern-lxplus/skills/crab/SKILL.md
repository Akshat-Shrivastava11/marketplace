---
name: crab
description: >-
  Use when submitting, monitoring or recovering CMS CRAB tasks on EL9:
  crab-setup and proxy delegation, sandbox size limits, memory/cores and
  maxJobRuntimeMin, site white/blacklists, crab resubmit vs recovery tasks
  with a lumiMask, PrivateMC seeds, CRAB as a backend for non-cmsRun
  payloads (law/dhi combine fits), or decoding CRAB failures such as
  SUBMITREFUSED, SUBMITFAILED, exit 50660, 50665, 50115, 8021, 8028,
  60323, 60326, 60328, "Argument list too long", "A different CMSSW
  configuration was already cached" or "Problems delegating My-proxy".
metadata:
  summary: "CRAB on EL9: setup, sizing, sites, exit codes, recovery tasks, CRAB as a backend for law/combine fits"
---

# CRAB

## Overview

CRAB runs cmsRun (or wrapped non-cmsRun) payloads on the CMS grid from a
CMSSW area on lxplus. Its limits are tight and enforced at submit time
(sandbox ~120 MB, ~2.5–3 GB per core, ~45 h wall time), its failures are
reported as numeric exit codes, and some states (SUBMITREFUSED, a FAILED
scheduler, task expiry) can't be resubmitted and need a new or recovery
task. Validate outputs, not exit codes.

Field notes collected by [DickyChant](https://gist.github.com/DickyChant/5c2a7a8db793a129ae8f637b9c6dfe1a) from about 25 Claude Code
sessions running CMS work at CERN (Oct–Nov 2026). Every item was hit in
practice; where sessions disagreed, both observations are kept.

## When to Use

- Before any `crab submit` or `crab resubmit`
- Decoding a CRAB exit code or a SUBMITREFUSED task
- Recovering missing lumis or an all-failed task
- Running non-cmsRun payloads (law/dhi, combine fits) on the grid

## Setup (EL9)

```
source /cvmfs/cms.cern.ch/cmsset_default.sh
cd CMSSW_X/src && eval $(scram runtime -sh)
source /cvmfs/cms.cern.ch/common/crab-setup.sh
export PYTHONNOUSERSITE=1          # stop ~/.local packages shadowing CRAB's
export X509_USER_PROXY=<proxy on AFS/EOS, chmod 600>
voms-proxy-info -timeleft; voms-proxy-info -actimeleft
```

- On the first submission the proxy is delegated to myproxy, which can prompt for the certificate password. An agent can't answer that, so the user runs the first submit once.
- With an AFS token expired mid-submission, the remaining tasks fail with `[Errno 13] Permission denied: '/afs/.../.crab3.NNNN'`. After the user runs `kinit`, resubmit only the SUBMIT FAILED tasks, found by grepping the submit log.
- The CRAB client caches its config inside one Python process. To submit many configs, use one subprocess per task.

## Sandbox and payload

- **Sandbox limit ~120 MB.** A payload that sources a big software stack before calling the client got its whole install packed (149 MB, rejected). Fix: run the CRAB client from a clean environment, in an empty CMSSW release; jobs fetch the heavy software themselves (xrdcp from EOS).
- Ship everything the payload reads. Jobs all failed with exit 5 because one analysis's TMVA weight files were missing from the tarball. Run a one-task test after any payload change.
- Non-cmsRun payloads (law's CRAB workflow): the client needs `python` on EL9; ship a `python`→`python3` shim. law 0.1.16 misreads `CMSSW_14` as version 4.
- Linux limits a single argument to 128 KB. law packed a ~750 KB per-job argument table into one argument, and 841 jobs died with `Argument list too long`. Pass job tables as files, not arguments.
- Grid workers don't see your filesystem. Paths checked on disk at job start (e.g. a datacard) must be skipped or shipped.
- Delete `inputs/*default.tgz` in project dirs after submitting, to save quota.
- `scriptExe` chaining several steps broke the bookkeeping (exit 50115). Keep only the heavy step on the grid and harvest the rest with condor.
- PrivateMC randomizes seeds per job. In cmsDriver configs run outside CRAB, set the seed (`RandomNumberGeneratorService.generator.initialSeed`) and `firstLuminosityBlock` per job yourself.

## Memory, cores, runtime

- Single-core jobs are capped at ~3000 MB (2000 MB default), and the cap is about 2.5–3 GB per core. A request beyond it is refused outright. For more memory request more cores: e.g. `numCores=2`, `maxMemoryMB=5000`.
- CRAB requires `process.options.numberOfThreads == JobType.numCores` in the PSet. For non-cmsRun payloads, generate a dummy PSet with N threads.
- Exit 50660: memory limit exceeded. Use fewer events per job or more memory and cores.
- Wall time: the practical ceiling is ~45 h (`maxJobRuntimeMin`). A fit that can't finish there won't finish on resubmit either; change the method or split the work.

## Sites

- Whitelist or blacklist **wildcards** (`T1_*,T2_*,T3_*` plus a CERN blacklist) were SUBMITREFUSED with no reason. An explicit list of T1/T2 site names, taken from CRIC, was accepted. CRAB then drops sites on its own blacklist.
- A blacklist that covers every disk replica of the input strands the jobs: they idle out with exit 50665 at site "Unknown". Check replicas first with `rucio list-dataset-replicas cms:<DS>`. On LPC, set `RUCIO_ACCOUNT` to the CERN username.
- `crab resubmit --siteblacklist=X` **replaces** the task's blacklist rather than adding to it, which is also a way to un-block a site.
- A crash in the first seconds at a single site (a segfault in 2 of 101 jobs, both at RAL) is a node or site problem. Resubmit with that site excluded.
- Exit 8028 (FallbackFileOpenError) with a dCache socket timeout repeats on every retry. Pin the other replica with `--sitewhitelist`.
- Exit 5 is generic; often it's xrootd `Operation expired` on input reads. Fix with `crab resubmit --siteblacklist=<bad sites>`.
- Stageout: 60323 means quota (check `eos quota`); 60328 is also stageout-related. Calibration-only runs need the framework's no-output switch, or every job fails at stageout.

## Recovery

- SUBMITREFUSED or SUBMITFAILED tasks can't be resubmitted. Move the project dir aside and run `crab submit` again. A failed submit can leave a stale `crab_projects/crab_<name>/` with no `.requestcache`; remove it first.
- An existing project dir blocks a duplicate submit, which is a useful guard.
- Once "Status on the scheduler" is FAILED, `crab resubmit` says "sent" but nothing reruns. Make a recovery task instead.
- Near expiry (within 7 days of 30), resubmit is refused. Make a top-up task with a new `requestName` but the same `outputPrimaryDataset`/`outputDatasetTag`.
- A job can finish with exit 0 and still lose its stageout, and then `crab report` raises `KeyError`. Compute the real gap as the input lumiMask minus the lumis read back from the outputs, and submit a recovery task with that JSON. Before killing the stale task, check that no new outputs appeared.
- Don't poll `crab status` in tight loops: one pass over hundreds of dirs takes minutes.

## Pattern: CRAB as a backend for non-cmsRun fits (law/dhi)

- Submit-and-return (`--<Task>-no-poll`), then rerun the same command to advance the chain: workspace (local) → snapshot (1 grid job) → per-parameter fits (N grid jobs) → merge (local). When the downstream merge reports "failed" right after submitting, that's expected.
- Upstream bundles (code, software, CMSSW) live on EOS and the jobs xrdcp them, so the sandbox stays tiny.
- Dry-run every submission first: `--print-status N` (law) shows what is absent or present. Never run two submissions at once from the same checkout; one of them hung.

## Gotchas

More field notes, each from a real failure.

- **Before a campaign:**
  - `crab checkwrite --site=T2_CH_CERN --lfn=<area>`, plus a group quota check;
  - a proxy that outlives the first days;
  - one canary task.
  - `crab submit --dryrun` unpacks the sandbox locally: with a big gridpack it put ~2.9 GB in crab_projects on AFS and filled the quota. Check `fs lq` first, or test with a small condor job instead.
- **Cores:** prefer 1 core with measured memory. A 4-core/8 GB task lost 13.7% of jobs to 50665 (idle; never started), against 0.05% for 1 core / 2 GB. `crab resubmit` can't change numCores.
- **Measure memory on whole files:** 5k-event tests underestimated, giving 50660. `crab resubmit --maxmemory 2500` works for ordinary jobs.
- **Automatic splitting:** failed processing and tail jobs aren't restarted by resubmit. Run `crab report`, then a new task with `lumiMask = notFinishedLumis.json`, `ignoreLocality=True` and a whitelist, writing to the same output tag (rounds rec1, rec2, …). `crab report` crashes on a task with no completed job.
- **SUBMITREFUSED variants:**
  - a block with >100k lumis: use `splitting = 'FileBased'`;
  - "intersection []": the lumi mask has no runs in that dataset.
- **CRAB API caches the PSet per process** ("A different CMSSW configuration was already cached"). Use one process per submission.
- **Site lists:**
  - The server's global blacklist overrides your whitelist; `Site.ignoreGlobalBlacklist` forces a site.
  - A site in both your whitelist and `--siteblacklist` stays allowed.
  - A `T2_*` whitelist made blacklisting useless when T2_CH_CERN nodes lacked `/cvmfs` (636 failures in the first minute): resubmit with an explicit whitelist.
  - Long jobs were killed at T3_US_FNALLPC; blacklist it for them.
- **Exit codes:**
  - 60326 with `curl error (56)` in stageout is a failed FTS pull from a site's dCache temp area, and plain retries keep failing; blacklist those sites. Inspect the FTS job with `curl --cert $X509_USER_PROXY --key $X509_USER_PROXY https://fts3-cms.cern.ch:8446/jobs/<id>/files`.
  - 8021/8028 repeating at one site: check replicas in Rucio, then whitelist the holders.
  - "Postprocessing failed" after a good run is a site stage-out problem.
- **All-failed tasks:** resubmit is silently ignored (API SUCCESS, DAG still FAILED). Move the dir aside (`*_FAILED_<id>`) and submit again with the same tag and LFN. `crab kill` on a dead scheduler can return KILLFAILED.
- **Stuck status:** `crab status` byte-identical for days means an ASO stageout backlog, which is a case for CRAB support.
- **Expired user certificate with a valid proxy:** `crab resubmit` fails ("Problems delegating My-proxy"). Use the Python API `crabCommand('resubmit', ..., proxy=...)`. Client v3.260630 also needed a patch to forward the proxy in resubmit's nested status call.
- **Proxy on EOS:** works across machines, but it becomes unreadable when the Kerberos ticket expires, and then every CRAB command fails. Claude can't create proxies (passphrase), so the user runs `voms-proxy-init -voms cms -rfc -valid 192:00 --out <file>`.
- **Validate outputs, not exit codes:** 6.8% of NanoGEN POWHEG sub-processes produced wrong weights in successful jobs. Each thread unpacks the gridpack separately (1.26 GB each), so strip unused files from gridpacks. NanoGEN drops custom LHE weight groups unless you add branches.
- **Sizing reference:** MINIAOD→HiForest with ParT, 2.1–2.3 GB RSS, 3000 MB / 720 min with 250 lumis per job: comfortable. NanoGEN with 4 threads, 500 events: 3.4 h mean, 7.2 h max, 4.1 GB peak.

## Docs

- CRAB3 tutorial and configuration: <https://twiki.cern.ch/twiki/bin/view/CMSPublic/CRAB3ConfigurationFile>
- CRAB3 FAQ: <https://twiki.cern.ch/twiki/bin/view/CMSPublic/CRAB3FAQ>
- CMS job exit codes: <https://twiki.cern.ch/twiki/bin/view/CMSPublic/JobExitCodes>
- CRIC site list: <https://cms-cric.cern.ch/>
- Source field notes (DickyChant): <https://gist.github.com/DickyChant/5c2a7a8db793a129ae8f637b9c6dfe1a>
