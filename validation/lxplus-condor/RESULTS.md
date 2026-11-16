# lxplus-condor validation results

The validating agent (Claude Haiku, no prior context) performed the task in
[PROMPT.md](PROMPT.md) on CERN HTCondor (lxbatch) using only the
`lxplus-access`, `lxplus-htcondor` and `eos-xrootd` skills, read as files.
It ran on an FNAL cmslpc node and drove a pinned lxplus node over ssh,
through an `lxtunnel` ControlMaster the user opened (2FA).

| Run           | Jobs (test + main)              | Exit codes                  | Resubmissions | Totals (160k events)                    | Outcome                     |
| ------------- | ------------------------------- | --------------------------- | ------------- | --------------------------------------- | --------------------------- |
| [run1](run1/) | 21003704 (test only, bigbird08) | payload 0, stage-out failed | 0             | not reached                             | blocked: eosuser quota full |
| [run2](run2/) | 21004056 + 21004172 (bigbird08) | all 0                       | 0             | HLT_PFHT900 21383; ≥2 jets pT>500: 2987 | pass, identical to LPC      |

## run1: blocked at stage-out

The user's `/eos/user` area was at 100% of its 1 TB quota. The test job's
payload succeeded, but every `xrdcp` to eosuser failed with
`[3021] Unable to get quota space ... Disk quota exceeded`. The agent stopped
before the campaign and deleted nothing. Its test-job counts for job 0
(5297 / 753) already matched the LPC run.

## run2: pass

Only the output target changed: FNAL EOS
(`root://cmseos.fnal.gov//store/user/<user>/...`), written from lxbatch with a
CMS VOMS proxy kept in a private AFS dir and exported as `X509_USER_PROXY` in
the job script, alongside `MY.SendCredential = True`. The proxy was created on
cmslpc and copied to lxplus at the user's direction.

- Per-job and total counts agree exactly with
  [lpc-condor/run2](../lpc-condor/run2/summary.json) (`check_results.py`).
- All 5 outputs passed the size + adler32 check against FNAL EOS.
- Memory: ~109 MB max RSS measured locally; `request_memory = 1000` was
  queued as 3000 MB by the schedd; jobs used 50–84 MB.
- Wall time 39–50 s per job under `espresso`. No holds, no resubmissions.

Deviations from PROMPT.md the brief imposed: AFS home instead of a work
volume (the account has none), and FNAL EOS instead of eosuser.

## Fixed after run1 and run2

`lxplus-htcondor`:
- Submitting without an AFS work volume (AFS home works).
- Dry run: working form `condor_submit -dry-run /dev/stdout x.sub`; it does not
  show the schedd's memory/CPU transforms.
- `condor_q -af Requirements` prints `false`; use `condor_q -l`.
- Local memory measurement with `/usr/bin/time -v` before the first job;
  small requests are raised to 3000 MB too.
- Writing to non-CERN storage (FNAL EOS) from jobs with a proxy on AFS.
- Log paths are relative to `initialdir`.

`eos-xrootd`:
- Full byte quota (`vol-status exceeded`, `[3021]`) is a hard stop, not a retry.
- `eos quota` without `EOS_MGM_URL` answers `no quota for path`.
- FNAL quota: `eosquota` on cmslpc.
- `xrdadler32` is not in the LCG views; python `zlib.adler32` fallback.
- Moving a proxy between sites only at the user's direction, into a private dir.

`lxplus-access`:
- The 2FA symptom (`gssapi-with-mic` "partial success"), a working
  `lxtunnel` ControlMaster config, and the node-local socket caveat.
- Accounts without a work volume.

## Open

- `lxplus-access` says a batch submission needs the user's go-ahead in the
  agent's own session. Both runs were delegated subagents whose brief carried
  the user's approval; how the skill should treat such briefs is left to the
  maintainers.
- `tokens` printed no AFS token on lxplus while AFS reads and writes worked
  (run2); not explained by the skill.
- lxtunnel asked for a password as well as the OTP although a valid Kerberos
  ticket was present (one observation).

## Not exercised

- `crab`, EosSubmit, GPU jobs, DAGMan, held-job recovery, resubmission from a
  missing-list (no failures occurred).
