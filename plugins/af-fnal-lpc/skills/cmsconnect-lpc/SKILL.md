---
name: cmsconnect-lpc
description: >-
  Use when submitting or debugging HTCondor jobs on CMS Connect
  (login.uscms.org, cmscon) or running large productions on the FNAL LPC
  pool: the CMS Connect condor_submit wrapper (no -dry-run), +REQUIRED_OS
  and x86-64-v3 microarchitecture requirements, DESIRED_Sites and site
  vetoes, proxies for long premix productions, output transfer back to
  /scratch, schedd transfer throttling, law/luigi on cmscon, GEN to NANO
  or MadGraph/gridpack production settings, finding jobs across lpcschedd
  schedds, oversubscribed multiprocessing pools, or errors such as
  "Illegal instruction", "JobLeaseDuration (2400 seconds) expired" or law
  jobs exiting with 60.
metadata:
  summary: "CMS Connect and FNAL LPC condor field notes: wrapper traps, microarch, site vetoes, large GEN productions, FNAL EOS"
---

# CMS Connect and FNAL LPC

## Overview

CMS Connect (`login.uscms.org`) submits glidein jobs to CMS grid sites
through a wrapped `condor_submit`; the FNAL LPC pool runs jobs in an
apptainer on Fermilab workers. These are field notes from production
campaigns on both: large GEN→NANO productions, gridpacks, law workflows.

For the step-by-step LPC batch workflow (job list, wrapper, one-job test,
submit, check and resubmit) use the **`lpc-condor`** skill, which was tested
end to end; this skill adds what came up at scale. Where the two differ
(e.g. shipping the proxy yourself, or `set -e` in multi-file payloads),
follow `lpc-condor` for ordinary analysis jobs and these notes for the
production cases they describe.

Field notes collected by [DickyChant](https://gist.github.com/DickyChant/5c2a7a8db793a129ae8f637b9c6dfe1a) from about 25 Claude Code
sessions running CMS work (Oct–Nov 2026). Every item was hit in practice.

## When to Use

- Submitting from CMS Connect (`login.uscms.org`) to grid sites
- Large private MC productions (GEN→NANO, MadGraph, premix) on CMS Connect or LPC
- Jobs dying on some sites or worker types and not others
- Finding, debugging and throttling jobs across the LPC schedds

## CMS Connect

- `condor_submit` there is a Python wrapper:

  - it does **not** know `-dry-run`: unknown arguments are taken as the submit file, so it really submits;
  - it reads one submit file per call (no macros on the command line);
  - it adds `x509userproxy`, a default `DESIRED_Sites` (unless `+DESIRED_Sites` is set), `MaxWallTimeMins` and `AccountingGroup`.

  `condor_q` and `condor_rm` are not wrapped.

- EL9 workers: `+REQUIRED_OS = "rhel9"` selects the glidein container; no singularity line is needed.
- **CPU microarchitecture:** CMSSW_16 (el9_amd64_gcc13) needs x86-64-v3. On a v2 worker it died with "Illegal instruction" after hours of GEN. Add `requirements = (TARGET.Microarch == "x86_64-v3") || (TARGET.Microarch == "x86_64-v4")`, plus a check at job start that `/proc/cpuinfo` has avx2/fma/bmi2/movbe, failing fast if not.
- **Proxy:** `voms-proxy-init -voms cms -valid 192:00`, with `use_x509userproxy = true`. Renew it during long productions that read premix over xrootd.
- **Outputs:** condor transfer back to `/scratch/$USER/...` via `transfer_output_files` + `transfer_output_remaps` was the reliable path. Then `xrdcp --posc --cksum adler32:<sum> <local> root://eoscms.cern.ch//eos/cms/store/...`; the grid DN maps to the CERN account at eoscms.
- **Schedd transfer throttle:** during a RAID check, `FILE_TRANSFER_DISK_LOAD_THROTTLE` cut concurrent transfers to 2, and uploads starved for hours. Before transfer-heavy submissions, check `condor_status -schedd <schedd> -af TransferQueueNumUploading TransferQueueNumWaitingToUpload` and `/proc/mdstat`.
- `/scratch` is slow for many-file operations (touching 45k files took >15 min). The login node has limited RSS, so run no PyROOT/cmsRun/analysis there.
- **Large productions:**
  - one cluster per channel, at most 20000 jobs per submission;
  - `max_idle` to throttle late materialization;
  - `periodic_release = (JobStatus == 5) && (HoldReasonCode != 26) && (NumJobStarts < 5) && ((time() - EnteredCurrentStatus) > 300)`, so policy holds stay held for inspection;
  - copy tarballs and configs into a per-submission sandbox, so later rebuilds can't change queued jobs.
- **law/luigi on cmscon:** `/tmp/luigi` belongs to another user. Set `[luigi_core] lock_pid_dir` in law.cfg, **not** on the CLI: law forwards CLI arguments into the jobs, which then exit with 60. Use `local_scheduler = True`. Python there is 3.9.
- genproductions `gridpack_generation.sh` refuses to reuse a process dir unless `export iscmsconnect=1`.

## FNAL LPC condor

- `condor_submit` picks the schedd itself. Find jobs with `condor_q -global <user>`, then `condor_q -name lpcschedd<N>.fnal.gov <id>`. Debug with `condor_ssh_to_job -name lpcschedd<N>.fnal.gov <id>.<proc> "<cmd>"`, which inherits the job's environment.
- Jobs run in a contained apptainer where `/uscms_data` is invisible. Take software from the CVMFS release (`cd /cvmfs/cms.cern.ch/el9_amd64_gcc12/cms/cmssw/CMSSW_X/src && eval $(scramv1 runtime -sh)`). Ship the proxy in `transfer_input_files`, and set `X509_USER_PROXY=$_CONDOR_SCRATCH_DIR/x509up_uNNNN`.
- Input sandboxes over ~1 GB are refused. Stage inputs from EOS inside the job: `xrdcp -s --parallel 4 --infiles list.txt dir/`.
- **Right-size requests:** ~650 MB fits asking for 4 GB sat idle for hours, while 1.5 GB started at once. `condor_qedit <id> RequestMemory 1500` works on idle jobs.
- **CPU counts:** `os.cpu_count()` returns the node's cores, not the slot's. An oversubscribed `mp.Pool` got OOM-killed, and then `Pool.map` hung for 4+ h. Size pools from `len(os.sched_getaffinity(0))`, or set `PYTHON_CPU_COUNT` (py ≥ 3.13).
- **Timeouts:** put `timeout` on every long step. A hung `combineTool.py --parallel` ran 9+ h.
- **Logs:** return only log tails from wrappers. Combine's "Error log follows" dumps made multi-GB `.out` files and filled the quota.
- **Dates:** worker nodes use UTC, and output names built from "today" break when a job crosses midnight. Pin the date and set `TZ`.
- **el7-only tools on el9:** `/cvmfs/cms.cern.ch/common/cmssw-el7 -B /uscms_data -- bash script.sh`. Use the full path over non-interactive ssh.
- **Argument passing:** `queue payload, args from file`, with `arguments = $(args)` and `transfer_input_files = $(payload)`, gives one jdl for many configs. Pass simple tokens; strings containing `=` break in `arguments`.
- **Partial failures:** don't use `set -e` in multi-file payloads. Print a marker line per output and grep the logs for it.
- **Throttling:** `max_materialize = 400` keeps 1500+ job submissions polite. `condor_q -totals` counts only the materialized jobs.
- **Input chunking:** never chunk inputs by list index if more files may arrive later; put late files in a separate extra chunk.

## FNAL EOS

- Write with `xrdfs root://cmseos.fnal.gov mkdir -p /store/user/<u>/<dir>`, then `xrdcp -f -s file root://cmseos.fnal.gov//store/user/<u>/<dir>/`. Read on login nodes through `/eos/uscms/...` FUSE. List with `eos root://cmseos.fnal.gov ls -l /store/...`.
- `xrdfs ls -l`: the size is column 4 and the path is the last column; parse with `awk '{print $4, $NF}'`.
- `/store/user/<cern>` can be a symlink to `/store/user/<unix>`, with one shared quota. Put big outputs in a group area (project quota).

## Gotchas

More field notes, each from a real failure.

- **Never run `condor_submit -dry-run` on CMS Connect:** two sessions independently created real clusters that way. Generate one jdl per variant with a script, since command-line macros don't work there.
- **Site vetoes** in Requirements: `TARGET.GLIDEIN_CMSSite =!= "..."` plus `regexp("<domain>", TARGET.Machine) =!= True`. Vetoed for real:

  - T2_US_Nebraska: premix routing;
  - T2_ES_IFCA: CVMFS I/O errors;
  - T2/T3_US_Vanderbilt: step1 segfaults;
  - T2_BE_IIHE: exit 139;
  - T1_RU_JINR: `pthread_create`/fork failures.

  To add a veto to idle jobs, save the old expression (`condor_q <cl> -af Requirements > backup`), then `condor_qedit <cl> Requirements '<expr>'`.

- **Working GEN→NANO settings:** `RequestCpus 4`, `RequestMemory 8000`, `RequestDisk 20000000`, `+MaxRuntime 86400`, `transfer_output_remaps = "step5.root = out/$(proc)_$(Cluster)_$(Process).root"`. 8-core slots match more slowly than 4-core ones.
- **CSV-driven `queue … from`:** a blank line queues an empty job. Preflight-check every input (`xrdfs stat` for `root://`).
- **OS:** the pool had no rhel8 slots. Run EL8 CMSSW inside `cmssw-el8 -B /local-scratch` on rhel9. slc7 gridpacks run natively on rhel7 slots, which matched in ~15 min.
- **Evictions:** Wisconsin glidein evictions ("JobLeaseDuration (2400 seconds) expired", code 1008) are harmless with `max_retries = 2` and a `periodic_release`, but each costs hours.
- **Memory monitoring:** in an el7 image on a cgroup-v2 host, `/sys/fs/cgroup/memory.current` is the whole node. Use condor's `MemoryUsage`.
- **MadGraph NLO `runcmsgrid`:** with NCPU=8 it peaks ~25 GB (each systematics worker loads all PDF members). Sites that enforce memory SIGKILL a worker, and MG then crashes later with a misleading `IndexError`. Use NCPU=4 (12.4 GB) and ~20 GB disk. `unset PERL5LIB` inside cmssw-el8, or merge.pl fails.
- **Premix:** use `--pileup_input filelist:...`. Randomize `process.mixData.input.seed` and set `skipBadFiles = True`. Jobs reading premix need a proxy valid for the whole run, and 192 h is the maximum, so renew it mid-production.
- **Detached processes over ssh:** use `setsid nohup cmd > log 2>&1 < /dev/null & disown`, or the ssh call hangs. Anchor `pkill -f` patterns (`'^python3 myscript'`).
- **Login:** `ssh <user>@login.uscms.org`. A passphrase-protected key works non-interactively only through an ssh-agent; pass `-o IdentityAgent=<socket>` if a global agent overrides it. Avoid `find /` there, because it hangs.
- **Big inputs** (e.g. 0.7 GB sherpacks for 20k jobs): put them on FNAL EOS and xrdcp them per job. `transfer_input_files` would push ~14 TB through the access point.
- **Usernames:** the FNAL EOS username can differ from the CERN or CMS Connect one; check it before writing paths.
- **Priority:** new jobs sit at JobPrio 0 behind your own older higher-priority jobs.
- **Interrupted transfers** left some outputs at mode 600 (unreadable); check the outputs afterwards.

## Docs

- LPC batch systems: <https://uscms.org/uscms_at_work/computing/setup/batch_systems.shtml>
- EOS at the LPC: <https://uscms.org/uscms_at_work/computing/LPC/usingEOSAtLPC.shtml>
- HTCondor submit description: <https://htcondor.readthedocs.io/en/latest/man-pages/condor_submit.html>
- Source field notes (DickyChant): <https://gist.github.com/DickyChant/5c2a7a8db793a129ae8f637b9c6dfe1a>
