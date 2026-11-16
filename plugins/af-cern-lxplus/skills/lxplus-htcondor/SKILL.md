---
name: lxplus-htcondor
description: >-
  Use when writing a CERN HTCondor (lxbatch) submit file (.sub) or
  debugging CERN batch jobs, CPU or GPU: choosing between the standard
  schedd and EosSubmit, sizing request_memory/request_cpus/request_gpus,
  picking a +JobFlavour or +MaxRuntime, staging outputs to EOS with xrdcp,
  jobs sitting idle that never match, held jobs ("FILETRANSFER: plugin for
  type root not found", HoldReasonCode 12/13), jobs removed by
  SYSTEM_PERIODIC_REMOVE for wall time or disk, requirements overwritten by
  the schedd, Kerberos/EOS access inside jobs, DAGMan campaigns, or
  resubmitting missing outputs.
metadata:
  summary: "CERN lxbatch HTCondor: where to submit, memory/CPU/GPU sizing, flavours, holds, EosSubmit, robust stage-out"
---

# CERN HTCondor (lxbatch)

## Overview

CERN batch (lxbatch) is HTCondor, submitted from lxplus. Unlike a plain
pool, the CERN schedds rewrite parts of your job: they derive CPUs from
memory, overwrite `requirements`, enforce wall time through `+JobFlavour`,
and reject `/eos` paths on the standard schedds. Most idle, held and
removed jobs trace back to one of those. Make jobs self-contained (CVMFS
software, tarball code, `xrdcp` outputs to EOS), size them from
measurements, run one test job, then the campaign.

Field notes collected by [DickyChant](https://gist.github.com/DickyChant/5c2a7a8db793a129ae8f637b9c6dfe1a) from about 25 Claude Code
sessions running CMS work at CERN (Oct–Nov 2026). Every item was hit in
practice; where sessions disagreed, both observations are kept.

## When to Use

- Writing or fixing a `.sub` file for lxbatch (CPU or GPU)
- Jobs idle for hours, held, or removed by the system
- Deciding between the standard schedd and EosSubmit
- Planning a campaign of many jobs or a DAG

## Where to submit from

- **Default:** submit from AFS (`/afs/cern.ch/work/...`) on the standard schedd. The standard schedds refuse `/eos` paths in the submit file.
- **No work volume?** Not every account has one (`ls -d /afs/cern.ch/work/<u>/<user>` fails; request it at the CERN resources portal). Submitting from the AFS home works (validated Nov 2026); check `fs lq ~` first, since the home is small (~2 GB).
- **The job itself:** make it self-contained. Software from CVMFS, code as a tarball (or git clone), small inputs embedded, and an explicit `xrdcp` of the outputs to EOS at the end, with `transfer_output_files = ""` when nothing should come back.
- **EosSubmit** (`module load lxbatch/eossubmit`, submit from an `/eos` dir): reports are mixed.
  - Several sessions saw every job held at input transfer: `FILETRANSFER: plugin for type root not found` (HoldReasonCode 13, subcode 11). Some workers (including GPU nodes) lack the xrootd plugin. `should_transfer_files = NO` doesn't help, because the schedd rewrites the executable to `root://`.
  - One GPU session used it successfully, with these rules:
    - every path (executable, log, out/err, inputs) must be under `/eos`;
    - one log per cluster (`logs/x.$(ClusterId).log`);
    - no directories in `transfer_input_files` (send tarballs);
    - `queue` can't sit inside `if/else`.
  - If you use it, add `periodic_release = (HoldReasonCode == 12 || HoldReasonCode == 13) && (NumJobStarts < 10)`, and expect churn.
- **`requirements` is overwritten** by the CERN schedd (only Hostgroup/PreLocalRequirements survive). A `stringListMember("root", HasFileTransferPluginMethods)` guard never applies. GPU-model `requirements` (`TARGET.GPUs_DeviceName =?= "NVIDIA H100 NVL"`) were reported to work. Check what was kept with `condor_q <id> -l | grep '^Requirements'`; `condor_q <id> -af Requirements` printed `false` (it evaluates the expression instead of showing it).
- **Kerberos in jobs:** `MY.SendCredential = True` forwards a krb5 ccache. Don't `export XrdSecPROTOCOL=krb5` (spurious `[3012] Unable to open file; Bad address`); let xrdcp negotiate. DAG POST scripts run on the schedd without that ccache, so EOS I/O there silently does nothing.
- **Dry run:** `condor_submit -dry-run /dev/stdout x.sub` prints the job ads without submitting (`-dry-run` takes an output file, and the submit file must still be named: `condor_submit -dry-run - < x.sub` fails with "No submit filename was provided"). It shows the ads _before_ the schedd's transforms, so a memory or CPU raise only appears in `condor_q <id> -af RequestMemory RequestCpus` after submitting. Run one short test job before any campaign.

## Sizing (the biggest source of idle jobs)

- **Memory and CPUs are tied:** the schedd sets `RequestCpus` from `RequestMemory` at about 2–3 GB per core (`ceil(mem/3072)` measured once; ~2 GB/core reported elsewhere).
  - 32 GB became 11 CPUs and matched 1 slot of 5214; 14 GB matched at once.
  - 150 GB became 50 CPUs and could never match on 28-CPU GPU nodes.
  - Asking 4 CPU / 6 GB for single-threaded cmsRun matched 122 of 4647 slots; 1 CPU / 3 GB matched 393.
- **Bid from measurement:** before the first job, run the payload once on lxplus on one job's inputs under `/usr/bin/time -v` and read "Maximum resident set size" (KB). After jobs ran, use the "Partitionable Resources" table in the job log, or `condor_history <id> -af MemoryUsage` (which can hang for minutes; the log is faster). Never bid defensively.
- **Small requests are raised too:** `request_memory = 1000` was queued as 3000 MB (Nov 2026), with `RequestCpus` still 1. Below ~3 GB, bidding lower doesn't buy faster matching.
- **Fix idle jobs in place:** `condor_qedit <cluster> RequestMemory 2500`. Use only the cluster id you just submitted: a constraint-based `condor_qedit` once rewrote 9,567 unrelated jobs. Preview the count and owners before any bulk qedit, rm or hold.
- **The schedd can raise RequestMemory after submit** (16000 → 24000 seen), which then never matches a GPU slot. Check with `condor_q <id> -af RequestMemory`.
- **Exceeding `request_memory` holds the job via the cgroup**, even after its useful work is done. Split memory-heavy post-steps into their own job. Pin the application's own parallelism (MadGraph without `nb_core` used every core of the node and blew the limit).
- **GPU:**
  - `request_gpus = 1` forces 8 CPUs per GPU, and a dynamic GPU slot has 16000 MB, so `request_memory > 16000` never matches.
  - Some GPU nodes require `RequestCpus >= 4`.
  - Don't filter on GPU properties that aren't advertised everywhere (`CUDADeviceName`, `GlobalMemoryMb`); check the type at runtime instead (`nvidia-smi --query-gpu=compute_cap`).
  - A regex on "H100" also matches MIG slices.
  - List the cards with `condor_status -af GPUs_DeviceName GPUs_GlobalMemoryMb | sort | uniq -c`.
  - Throughput is per account: about 7–9 GPU jobs by day and about 4 at night.

## Wall time

- `+JobFlavour` limits: espresso 20 m, microcentury 1 h, longlunch 2 h, workday 8 h, tomorrow 1 d, testmatch 3 d, nextweek 1 w. `+MaxRuntime` (seconds, under 14 days) is honoured on some schedds, but one GPU/EosSubmit session found it ignored (the schedd derives it from the flavour), and a later `condor_qedit MaxRuntime` didn't save a running job. Pick the flavour at submit and confirm with `condor_q <id> -af MaxRuntime`.
- Overruns are removed, not held: `Job removed by SYSTEM_PERIODIC_REMOVE due to wall time exceeded allowed max`. The same rule applies to disk (`... disk usage exceeded allowed max`).
- Size for the slowest node or GPU you accept, and leave a margin of about 3×. Jobs died at 8h01m under `workday` and at 23.8 h under `tomorrow`.
- **96 h is a practical ceiling.** Combine robust fits on a huge workspace (HHVV impacts nominal fit) exceeded both CRAB (~45 h) and 96 h HTCondor. Change the method (e.g. a split Hessian) rather than buy more wall time.
- Write checkpoints and partial outputs to EOS during the job, so a removal doesn't lose finished work. At job start, exit 0 if the final output already exists, so a rerun is a no-op.

## Holds, retries and failures

- Diagnose with `condor_q -hold -af HoldReason`, `condor_q -better-analyze <id>` ("would match if drained" means wait), and `condor_history <id> -af JobStatus ExitCode RemoveReason`.
- Holds aren't failures, so DAG `RETRY` doesn't cover them; add a `periodic_release` for the specific codes.
- Retries with seeds derived from the job index repeat byte-identical failures (one campaign burned ~570 pool-hours). Seed from ClusterId/ProcId, or exit without retry for deterministic failure classes.
- Some nodes lack `/usr/bin/python`, or have a broken `gfal-ls`. A job that dies in the first minute on one node and succeeds on others is a node problem; resubmit.
- HTCondor transfers back the outputs of FAILED jobs too: an empty 1.5 kB ROOT file passed `test -s`. Validate content (event counts, a marker line), not existence. rc=0 is not proof: a generator printed "success" with an empty tarball.

## Output and stdout

- The CERN schedd rejects `stream_output`/`stream_error`, so stdout only comes back at the end. To watch progress, tee the log to EOS.
- Condor doesn't create log directories; `mkdir` them before submitting.
- `transfer_input_remaps` only renames outputs. `transfer_input_files` with `root://` takes files only. `executable`, `initialdir` and `log` can't be xrootd URLs. `condor_submit -spool` keeps the sandbox off AFS.
- Late materialization (`max_materialize`, `max_idle`) keeps spawning jobs while the cluster is held: `condor_rm` a dead cluster instead of leaving it held.
- DAGs: `condor_submit_dag -maxidle 200 -maxjobs 500 -batch-name <name>`; pass per-node values through `VARS`.

## Etiquette

- Act only on cluster ids you submitted. Never remove or edit by owner or by constraint.
- Ask the user before campaigns of more than ~20 jobs on shared accounts.
- Payload tarballs on EOS are read when a job starts, not when it's submitted. Redeploying one changes queued jobs. Hold the idle ids during the swap, keep a dated backup of the old tarball, then release.

## Gotchas

More field notes, each from a real failure.
**EosSubmit specifics**

- Set `transfer_output_files = ""` (or `+TransferOutput = ""`). Otherwise the whole sandbox comes back, including the proxy and the `<user>.cc` Kerberos cache. That filled a quota (hold code 12), and concurrent jobs collided on "File exists".
- Keep each `condor_submit` to ≤ 500 jobs; 1000+ failed with "Failed to create proc". Release or resubmit in waves of ≲ 500 every ~10 min. A 5k-job burst caused an hour-long xrootd `Operation expired` storm.
- `SYSTEM_PERIODIC_REMOVE` removes a job after 11 starts, and every hold-and-release uses one. Watch `NumJobStarts`.
- On EOS schedds `Iwd` is the spool and `Err` is a `root://` URL, so match jobs on `Err`.
- `max_materialize` on bigbird103 (Nov 2026) applied the requirement transforms twice and left a loop that matched nothing (`-better-analyze`: "[1] never PreVerRequirements"). Submit without it, and always run `-better-analyze` right after submitting.
- `next_job_start_delay` is refused.
- A proxy stored on /eos/user made a normal submit hold (the schedd can't read it). `condor_submit -spool` ships it; CERN then requires an explicit `transfer_output_files`. `condor_rm` the completed spooled jobs afterwards, which removes the proxy copy.

**Software in jobs**

- Don't run code or a venv from EOS FUSE at scale. Imports failed with `OSError: [Errno 5]` in ~half of 800 jobs, and the wrapper exited 0. Hundreds of jobs writing `.pyc` at once caused EIO too. Ship a tarball and unpack it in `$_CONDOR_SCRATCH_DIR`, or set `PYTHONDONTWRITEBYTECODE=1` and precompile once.
- `getenv = True` ships values literally: `$PYTHONPATH` inside a value is never expanded. Write explicit `export` lines in the executable. Check with a test job that runs `python -c 'import pkg; print(pkg.__file__)'`.
- `export PYTHONNOUSERSITE=1` in jobs too: the AFS `~/.local` is visible on workers and shadows env packages.
- CMS/LCG environments set `PYTHONHOME`/`PYTHONPATH`, which break a venv or pixi Python; use `env -u PYTHONHOME -u PYTHONPATH`. A reproducible env that worked: pixi from cvmfs, with the package cache as a tarball on EOS and an offline `pixi install` per job (≈20 s).
- `MY.WantOS = "el8"` runs el8 builds on el9 workers. `MY.SingularityImage = "/cvmfs/unpacked.cern.ch/..."` runs in an image.
- Build portably: `-march=native` binaries built on lxplus die with illegal instructions on older workers. Use `-march=x86-64-v2`.
- condor_submit from inside apptainer needs `-B /afs -B /cvmfs/cms.cern.ch -B /tmp -B /eos/cms -B /eos/user -B /etc/sysconfig/ngbauth-submit -B $XDG_RUNTIME_DIR --env KRB5CCNAME=FILE:$XDG_RUNTIME_DIR/krb5cc`.
- Freeze payloads before submitting (an immutable copy with sha256 recorded). Editing a bash driver while jobs run it corrupted ~20 jobs. Pickled configs (cloudpickle) freeze code at submit, so swapping the tarball doesn't fix queued jobs.

**Robustness**

- Save `RC=$?` immediately after the payload. A stage-out block before `if [ $? -eq 0 ]` made failed jobs look successful.
- Make the job exit non-zero when its output is missing; `max_retries` never sees a 0 exit.
- Keep retry budgets small (1–2 job retries, ~3 per command). 10×10 nested retries hid a deterministic failure for 4.5 h. Alarm on output progress, not on running counts.
- Don't `periodic_remove` held jobs. An AFS volume outage held ~600 jobs, which were then deleted at once; release with a limit instead. During that outage the schedd also truncated output files at 512 KiB (`vos examine` showed "Volume is busy").
- In DAGMan, one nonzero node can remove all its siblings (945 nearly done jobs lost). Have jobs `exit 0`, write a GUARD-FAIL marker, and count complete outputs between stages.
- Node loss (events 022 → 024 → 004, code 1008) restarts jobs ~1.5 h later, so make jobs idempotent.
- `condor_q` can fail silently: "Could not fetch schedd mapping data" prints nothing. Accept a poll only on exit 0, and require the expected outputs (or two consecutive empty polls).
- ssh exit 124 (timeout) doesn't mean the remote command never started; three duplicate drivers came from that once. Confirm with a marker line in the remote log.
- Completed jobs were seen reappearing as idle. Guard with "exit 0 if the final output exists".
- Find gaps by comparing expected outputs on EOS with what's there, then resubmit from a missing-list (`queue ... from missing.txt`). That catches held, evicted and lost jobs.
- Memory request that adapts: `RequestMemory = ifThenElse(isUndefined(MemoryUsage), <MB>, int(MemoryUsage*1.1))`. Cap log verbosity: a looping job wrote a 3 GB log (combine `-v` ≤ 3).
- To tell slow from hung: `condor_ssh_to_job`. Stream stdout with `condor_tail -maxbytes N <id>`. The cluster's user log is much faster than `condor_history`, and history rolls off after a few weeks, so record stats while it's fresh.
- AFS: ~33–40k entries per directory, then every create fails with `errno 27 File too large`. AFS is write-on-close: a file being written on node A reads as empty on node B. `cp dir/*` hits "argument list too long" at ~2 MB.
- `condor_prio` only orders one user's jobs; raising one campaign starves your others.
- Credentials: kinit plus `MY.SendCredential = True` is enough for CERN EOS from jobs (credmon renews it). A voms proxy is only needed for non-CERN storage. Jobs keep running ~31 h after the submitter's ticket expires.
- Writing to non-CERN storage (e.g. FNAL EOS, `root://cmseos.fnal.gov//store/user/<user>/...`) from lxbatch: keep the proxy on AFS (`chmod 600`), keep `MY.SendCredential = True`, and `export X509_USER_PROXY=<afs path>` in the job script; the worker reads it through the forwarded AFS token (validated Nov 2026). Check `voms-proxy-info -timeleft` covers the campaign.
- Output and error paths (`output`, `error`, `log`) are relative to the submit directory (`initialdir`), and their directories must exist.

## Docs

- CERN batch docs: <https://batchdocs.web.cern.ch/>
- Job flavours and wall time: <https://batchdocs.web.cern.ch/local/submit.html>
- EOS submission (EosSubmit): <https://batchdocs.web.cern.ch/troubleshooting/eos.html>
- HTCondor submit description: <https://htcondor.readthedocs.io/en/latest/man-pages/condor_submit.html>
- Source field notes (DickyChant): <https://gist.github.com/DickyChant/5c2a7a8db793a129ae8f637b9c6dfe1a>
