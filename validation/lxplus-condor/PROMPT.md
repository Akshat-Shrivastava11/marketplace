# Validation task for the `af-cern-lxplus` skills

A fresh agent, with no other context, performs this task on lxplus using
only the `af-cern-lxplus` skills. Its notes (`SKILLS_USED.md`) and results
(`summary.json`) are committed next to this file as evidence that the skills
work as written.

## Task

Using only the skills in `plugins/af-cern-lxplus/skills/` (`lxplus-access`,
`lxplus-htcondor`, `eos-xrootd`; read them as files if the plugin is not
installed), run a small batch analysis on CERN HTCondor (lxbatch):

- **Access:** reach lxplus as the skills describe (Kerberos ticket checked
  with `klist -s`, a pinned `lxplus9NN` node, every ssh wrapped in
  `timeout`). If a ticket or 2FA is needed, stop and ask the user.
- **Input:** the first 8 ROOT files of 2016G JetHT NanoAOD Open Data,
  `root://eospublic.cern.ch//eos/opendata/cms/Run2016G/JetHT/NANOAOD/UL2016_MiniAODv2_NanoAODv9-v1`,
  2 files per job, so 4 jobs.
- **Payload:** for each file, read the first 20,000 events and count those
  with `HLT_PFHT900` fired and those with at least two jets with pT > 500 GeV.
  Software from CVMFS (an LCG view); write the counts per job to a small JSON
  file.
- **Submission:** from an AFS work directory on the standard schedd, with
  `+JobFlavour = "espresso"`, memory sized from a local measurement, and
  `MY.SendCredential = True`.
- **Output:** `xrdcp` each job's JSON to
  `root://eosuser.cern.ch//eos/user/<u>/<username>/cms-marketplace-tests/lxplus-condor/`
  with a size and adler32 check (the `eos-xrootd` copy pattern), and
  `transfer_output_files = ""`.
- Follow the skills' workflow: quota check (`eos quota`, `fs lq`), dry run
  (`condor_submit -dry-run`), one test job, full submission, monitoring that
  only trusts successful `condor_q` calls, content validation of outputs,
  resubmission of missing ones from a missing-list, then merge the counts.

**Limits:** at most 4 jobs plus one test job and resubmissions of failures.
Act only on cluster IDs you submitted. No EosSubmit, no GPU, no CRAB.
Work in a fresh directory. No commits.

**Deliverables:**

- `summary.json`: job count, cluster IDs and schedd, per-job and total
  counts, requested vs used memory, wall time per job, number of
  resubmissions.
- `SKILLS_USED.md`: every step and the part of the skill that guided it.
  List explicitly anything that was unclear, missing, wrong, or that you had
  to work around (quote the line). No personal paths or usernames.
- Compare the totals with `validation/lpc-condor/run2/summary.json`
  (same files and selection); they must agree.
