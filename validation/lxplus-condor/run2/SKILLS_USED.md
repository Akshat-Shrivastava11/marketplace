# SKILLS_USED.md: lxplus_condor_haiku run2

Skills followed (from `plugins/af-cern-lxplus/skills/`): `lxplus-access`, `lxplus-htcondor`, `eos-xrootd`.
Run on an FNAL cmslpc node driving CERN lxplus947 over ssh. Output staged to FNAL EOS (CERN eosuser quota full).

Deviations from TASK.md that the brief required: work dir on the AFS home (no AFS work volume);
output to `root://cmseos.fnal.gov//store/user/<user>/cms-marketplace-tests/lxplus-condor/run2/`
instead of eosuser; the VOMS proxy was read in place from AFS by the jobs (not copied).

## Steps and the skill passage that guided each

1. **Access check.** `klist -s` on the local node returned 0. `ssh -O check lxtunnel` reported the master running.
   Guided by `lxplus-access` "Connecting": "Wrap every ssh in `timeout`", and "Check that the master is alive with `ssh -O check <jump>`."
   Ssh form used: `timeout N ssh -T -o BatchMode=yes -o PreferredAuthentications=gssapi-with-mic -o GSSAPIDelegateCredentials=yes lxplus947.cern.ch`.
   Worked first time. The skill's `Pin a node (lxplus9NN ...)` was followed by pinning lxplus947.
   Tokens: `tokens` on lxplus printed an empty list, yet AFS reads worked. See "Unclear" below.

2. **Work area.** No `/afs/cern.ch/work/` area (checked with `ls -ld`). Used the AFS home instead:
   `/afs/cern.ch/user/<u>/<user>/cms-marketplace-tests/lxplus-condor-haiku-run2-2026-11-15`, with `logs/` created before submit.
   Guided by `lxplus-htcondor` "Where to submit from": "**Default:** submit from AFS (`/afs/cern.ch/work/...`) on the standard schedd." and `lxplus-access` "Quotas on login areas": "Keep code and logs on AFS and outputs on EOS." The home quota (2 GB) was 59% used (`fs lq`), with ~860 MB free. Submitting from the home area worked.

3. **Quota checks.** `EOS_MGM_URL=root://eosuser.cern.ch eos quota /eos/user/<u>/<user>` (wrapped in `timeout`). The result was "exceeded": 2.01 TB used against 1.00 TB logical, 100% filled.
   Guided by `eos-xrootd` "Quotas": "Check: `eos quota <path>`" and "Wrap `eos` calls in `timeout`". The brief said the CERN quota was full, and the check confirmed it.
   FNAL EOS quota was not checked (no command in the skill, see Unclear).

4. **Input list.** `xrdfs root://eospublic.cern.ch ls -l .../UL2016_MiniAODv2_NanoAODv9-v1` (parent listed first), then `.../130000` and `.../260000`.
   Guided by `eos-xrootd` "Copying reliably": "Don't guess path prefixes or tags. List the parent dir first."
   Selection: first 8 files in recursive name order (`130000/CD205112...` first, then `260000/` in name order). Jobs: (0) CD205112+0673B754, (1) 07E886E0+0816386A, (2) 0FAAB36E+1258413A, (3) 1B2EC787+1CA06DD5. See `filelist.txt`, `jobs.txt`.

5. **Software.** LCG_106 view from CVMFS: `source /cvmfs/sft.cern.ch/lcg/views/LCG_106/x86_64-el9-gcc13-opt/setup.sh`, inside `set +u`.
   Guided by `lxplus-access` "Shell-scripting traps": "`set -u` while sourcing LCG/CMSSW/key4hep setup scripts fails (`COMPILER: unbound variable`). Wrap them in `set +u … set -u`."
   The worker script never re-enables `set -u`, which is a simplification. uproot 5.3.7 and awkward 2.6.4 imported fine.

6. **Payload** (`payload.py`, frozen copy in run2/). Reads the first 20,000 events per file for `HLT_PFHT900` and for >= 2 jets with `Jet_pt > 500`, then writes JSON.
   Inputs are staged to `$_CONDOR_SCRATCH_DIR` with `xrdcp`, guided by `eos-xrootd` "FUSE vs xrootd": "On batch workers `/eos/user` is usually mounted, but `/eos/cms` may not be readable. Stage inputs with `xrdcp` to `$_CONDOR_SCRATCH_DIR`."

7. **Local memory measurement.** Two files staged to node-local `/tmp` on lxplus, then `/usr/bin/time -v python3 payload.py ...`: max RSS 108,908 KB (~109 MB), wall 3.8 s, counts identical to the job.
   Guided by `lxplus-htcondor` "Sizing": "**Bid from measurement:** use `condor_history <id> -af MemoryUsage`, or the 'Partitionable Resources' table in the job log. Never bid defensively."
   That passage only covers measurement after a job has run. The skill has no local-measurement recipe, so `/usr/bin/time -v` was my choice (see Unclear).
   Bid: `request_memory = 1000`, `request_cpus = 1`, `request_disk = 6000000` (KB, because the two inputs total ~2.6 GB).

8. **Credentials and proxy.** `MY.SendCredential = True` in both submit files. The VOMS proxy stayed on AFS at its existing path, `chmod 600`, and the wrapper sets `X509_USER_PROXY` to that path. Proxy lifetime checked with `voms-proxy-info -timeleft -actimeleft` (688988 s / 688987 s, ~191 h).
   Guided by `eos-xrootd` "Unattended access": "keep one on AFS/EOS readable from where it's used (`chmod 600`), and set `X509_USER_PROXY` to it, not `/tmp/x509up_u*`... Check both `voms-proxy-info -timeleft` and `-actimeleft`."
   Guided by `lxplus-htcondor` "Credentials": "kinit plus `MY.SendCredential = True` is enough for CERN EOS from jobs... A voms proxy is only needed for non-CERN storage." This matches the FNAL output: the proxy was needed there, and it worked.
   Followed: "Never copy grid proxies or keys between sites or into shared places." Only one copy exists, at its original AFS path.
   Followed: "Non-interactive ssh shells have no `X509_USER_PROXY`; export it in every remote command."

9. **Submit files.** `campaign.sub` (4 jobs, `queue Label,In1,In2 from jobs.txt`) and `test.sub` (1 job, label `test`). Both set `+JobFlavour = "espresso"`, `MY.SendCredential = True`, `transfer_output_files = ""`, `output/error/log` in `logs/`, and `transfer_input_files = payload.py`.
   Guided by `lxplus-htcondor` "Wall time": "Pick the flavour at submit and confirm with `condor_q <id> -af MaxRuntime`" (confirmed: 1200 s). Also "Condor doesn't create log directories; `mkdir` them before submitting."

10. **Dry run.** `condor_submit -dry-run /dev/stdout test.sub`, with the resolved ads filtered by grep.
    Guided by `lxplus-htcondor` "Dry run": "`condor_submit -dry-run - x.sub` shows the resolved ads."
    I did not use the literal `-` form the skill shows, because the skill's `-` placeholder is ambiguous (see Unclear).
    Mistake: the campaign submit command also contained a stray `condor_submit -dry-run /dev/null` (output discarded). A dry run does not submit, and no jobs were created by it. Cluster IDs below come only from the real submissions.

11. **Test job.** Cluster 21004056, schedd bigbird08.cern.ch, label `test`, files of job 0. Return 0. Wall 39 s (executing to terminated). Output verified on FNAL EOS (VERIFY_OK, size 522, adler32 f53e85b8). Counts matched the local measurement.
    Guided by `lxplus-htcondor` "Dry run": "Run one short test job before any campaign."

12. **Campaign.** Cluster 21004172, procs 0-3, same schedd. All four terminated normally (return 0) with no holds or removals. Per-job wall (executing to terminated): 40, 39, 50, 45 s.
    Memory: `request_memory` 1000 in the file, 3000 in the queue (see Unclear). Used: 50 MB (test MemoryUsage); campaign image size peaks 69-84 MB, RSS 24-69 MB in the job logs.

13. **Monitoring.** Polls were `if timeout 30 condor_q $C -af ... > file; then ... else poll failed; fi`, so only successful polls were trusted. Guided by `lxplus-htcondor` "Robustness": "`condor_q` can fail silently... Accept a poll only on exit 0". An empty successful `condor_q` was read as "left the queue", and the user logs confirmed termination.
    Guided by `lxplus-htcondor` "Robustness": "The cluster's user log is much faster than `condor_history`". `condor_history` returned nothing for the test job and timed out (110 s) for the campaign, so the job logs were the source of truth.

14. **Worker wrapper** (`run_job.sh`, frozen copy in run2/). Staged the two inputs with `xrdcp -f -s` and 6 retries, ran `payload.py`, checked the JSON content (`events_read_total == 40000`), then staged out.
    Guided by `lxplus-htcondor` "Robustness": "Save `RC=$?` immediately after the payload", and "Make the job exit non-zero when its output is missing"; and by "HTCondor transfers back the outputs of FAILED jobs too... Validate content (event counts, a marker line), not existence."

15. **Stage-out and verification.** `xrdfs root://cmseos.fnal.gov mkdir -p <dir>`, then `xrdcp -f -s --posc --cksum adler32 <json> root://cmseos.fnal.gov//store/...` (6 tries, 20 s apart). Verification: remote size from `xrdfs stat`, remote checksum from `xrdfs query checksum`, local size and adler32 (python `zlib.adler32`, see Unclear).
    Guided by `eos-xrootd` "Copying reliably": "Pattern: `xrdfs <host> mkdir -p <dir>`... then `xrdcp -f -s --posc --cksum adler32 <src> <dst>`, with a retry loop (e.g. 6 tries, 20 s apart)." and "Verify each file after copying: remote size (`xrdfs stat`) and checksum (`xrdfs query checksum` vs local `xrdadler32`)."
    Result: all 5 files (job_test.json and job_0..3.json) VERIFY_OK. The JSONs were fetched back with `xrdcp -s` for the merge.

16. **Resubmissions.** None. Zero failures among the 5 jobs, so no missing-list was needed.
    Guided by `lxplus-htcondor` "Holds, retries and failures" and "Find gaps by comparing expected outputs on EOS": not needed in this run.

17. **Comparison.** Read `validation/lpc-condor/run2/summary.json` only after the merge. Per-job counts and totals agree exactly: 160,000 events, 21,383 HLT_PFHT900, 2,987 with >= 2 jets pT > 500. The file list order chosen in step 4 therefore matches the LPC run.

## Unclear / missing / wrong

- **No work volume.** `lxplus-htcondor` "Where to submit from" only names `/afs/cern.ch/work/...`: "submit from AFS (`/afs/cern.ch/work/...`) on the standard schedd." `lxplus-access` says "AFS work dirs fill quickly" but not what to do without one. The AFS home worked, but the skills do not say whether home-area submission is supported. Missing guidance.
- **Quota full, no fallback.** `eos-xrootd` "Quotas" describes the quota and the cleanup advice, but nothing about the case where the quota is full and another site's EOS must be used. The fallback to FNAL EOS was my choice (the brief directed it). Missing.
- **No FNAL EOS quota command.** `eos-xrootd` documents `eos quota` for CERN instances only. The FNAL quota was not checked. Missing.
- **Local measurement recipe missing.** `lxplus-htcondor` "Sizing" says "Bid from measurement: use `condor_history <id> -af MemoryUsage`..." This needs a finished job, which is circular for the test job. A local-run recipe (e.g. `/usr/bin/time -v`) would help. Missing.
- **`condor_submit -dry-run - x.sub` is ambiguous.** The skill writes `-` as a placeholder in a flag-style example. I ran `-dry-run /dev/stdout` instead. Wrong or unclear.
- **Dry run does not show the schedd's memory raise.** `lxplus-htcondor` "Dry run" says the dry run "shows the resolved ads". Here it showed `RequestMemory=1000`, but the queued jobs had `RequestMemory=3000`. The skill's "The schedd can raise RequestMemory after submit (16000 → 24000 seen)" describes the same effect but says "after submit". In this run the raise was already visible in `condor_q` right after `condor_submit`, and the dry run did not show it. Misleading.
- **`condor_q -af Requirements` printed `false`.** `lxplus-htcondor` "Where to submit from": "Check what was kept with `condor_q <id> -af Requirements`." That printed `false` for both clusters (schedd-side evaluation). `condor_q -l` showed the real expression: `(TARGET.Hostgroup =?= "bi/condor/gridworker/share/mixed" || ...) && PreLocalRequirements`. The skill's command is misleading; `-l` should be suggested.
- **`xrdadler32` not in the LCG_106 view.** `eos-xrootd` "Copying reliably" assumes `xrdadler32` is available locally. It was not in the view's `bin/`; `/usr/bin/xrdadler32` exists on lxplus only. I used python `zlib.adler32`, formatted `%08x`, which matched `/usr/bin/xrdadler32` on the same file (61e886f0 both). Not stated in the skill.
- **AFS token on lxplus.** `tokens` on lxplus printed no tokens, but AFS reads and writes worked. `lxplus-access` ties "no AFS token" to "condor 401 on a node... run `aklog`", which did not apply here. The jobs read the proxy from AFS and it worked, but I did not check the job's token, so the skill does not explain this case. Unclear.
- **"First 8 files" order.** TASK.md does not define the order. The skills do not either. The recursive name order was my choice, and the result matches the LPC reference. Not a skill issue, but worth noting.
- **`CONDOR_CLUSTER` not set in jobs.** Cosmetic: my wrapper echoes `${CONDOR_CLUSTER:-?}`, and it printed `?`. The skills do not mention this variable. Not a problem for the run.

## Pass / fail summary

- Access, pinned node, ssh timeout wrapping: worked.
- Quota check, dry run, test job, campaign, log-based monitoring, content validation, staged output with size and adler32 verification: all worked on the first attempt.
- 0 failures, 0 resubmissions. Results agree with the LPC reference.
