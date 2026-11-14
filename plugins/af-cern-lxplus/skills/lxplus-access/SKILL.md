---
name: lxplus-access
description: >-
  Use when driving lxplus (or cmslpc) over ssh from an agent or script:
  non-interactive ssh with Kerberos/GSSAPI, lxtunnel jumps and 2FA,
  pinning an lxplus9NN node, files vanishing from /tmp between calls,
  nohup or setsid processes killed at logout, expired or non-renewable
  Kerberos tickets, AFS quota or token problems, apptainer not seeing
  /eos/user, or errors such as "Permission denied (publickey,gssapi-with-mic)",
  "Could not resolve hostname lxplus.cern.ch.cern.ch", ".bashrc: Permission
  denied", "kex_exchange_identification: Connection closed" or
  "COMPILER: unbound variable".
metadata:
  summary: "Reaching lxplus from agents: Kerberos, node pinning, node-local /tmp, killed background processes, shell traps"
---

# lxplus access for agents

## Overview

Agents reach lxplus through non-interactive ssh, and most failures come
from four facts: Kerberos tickets expire, `lxplus` is a round-robin alias
with node-local `/tmp`, lxplus9 kills background processes at logout, and
AFS areas are small. This skill collects what broke in practice and the fix.
Read it before any ssh-driven work on CERN (or FNAL) login nodes; for batch
jobs continue with `lxplus-htcondor`, for storage with `eos-xrootd`.

Field notes collected by [DickyChant](https://gist.github.com/DickyChant/5c2a7a8db793a129ae8f637b9c6dfe1a) from about 25 Claude Code
sessions running CMS work at CERN (Oct–Nov 2026). Every item was hit in
practice; where sessions disagreed, both observations are kept.

## When to Use

- Running commands on lxplus from Claude Code or a script over ssh
- State written in one ssh call missing in the next
- Long processes disappearing after the ssh session ends
- Kerberos, AFS token or 2FA errors on login

## Connecting

- Non-interactive ssh: `ssh -T -o BatchMode=yes -o PreferredAuthentications=gssapi-with-mic -o GSSAPIDelegateCredentials=yes <user>@lxplus.cern.ch`, after `kinit <user>@CERN.CH` on the local machine. Wrap every ssh in `timeout`, so it fails fast instead of hanging on a prompt.
- Off-site machines that get a 2FA prompt: hop through `lxtunnel.cern.ch` (`ssh -J`) with GSSAPI and a ControlMaster on the jump alias only. Check that the master is alive with `ssh -O check <jump>`. An agent can't answer 2FA, so if the master is down the user opens it.
- `Could not resolve hostname lxplus.cern.ch.cern.ch`: the local ssh config appends the domain. Use the `lxplus` alias.
- "Too many authentication failures": too many keys are offered; restrict `PreferredAuthentications`.
- `".bashrc: Permission denied"`, or condor 401 on a node: no AFS token. Reconnect with `GSSAPIDelegateCredentials=yes`, or run `aklog`.
- `ssh host 'cmd'` doesn't load the login profile, so `module load` etc. are missing. Use `ssh host "bash -lc '...'"`.
- With `ssh host 'bash -s' <<'EOF'`, the remote stdin is the script itself. A `cat`, `awk` or `python3 -` inside reads the rest of the script.

## Kerberos expiry

- Tickets last ~25 h and renew for up to 5 days, then the user must run `kinit` again (`kinit -R` is refused).
- Symptoms:
  - ssh: `Permission denied (publickey,gssapi-with-mic,keyboard-interactive)`;
  - a running CRAB submit: `[Errno 13] Permission denied: '/afs/.../.crab3.NNNN'`;
  - `eos ls` returns an empty listing, not an error.
- Test with `klist -s` (exit code), not by reading "renew until". Before reading "empty" as "done", make one call you know must succeed.
- During a KDC outage `condor_q` fails. Only count jobs from a query that succeeded; a watcher once read the failure as "no jobs" and exited.

## Node pinning and /tmp

- `lxplus` (and `cmslpc-el9`) is round-robin, and `/tmp` is node-local. Files written in one ssh call are gone in the next. Pin a node (`lxplus9NN`, `cmslpc3NN`), or keep state on AFS/EOS.
- Even on a pinned node `/tmp` loses old files (lost runtime libraries after a few days). Don't keep anything precious there.
- Some aliases land on nodes that refuse connections (`kex_exchange_identification: Connection closed`). Pick a specific node.

## Long-running processes

- lxplus9 has `KillUserProcesses=yes`: `nohup` / `setsid` processes are killed silently at ssh logout. Either hold the ssh session open (a local background job with a long timeout) or use HTCondor. lxplus-gpu is interactive only, for the same reason.
- Bulk CRAB submissions can take more than 2 h. Give the holding timeout plenty of room; killing one mid-submit leaves a half-made project dir.
- The interactive cgroup is limited (~96 GB on GPU nodes; much less on cmsconnect login). Big builds or PyROOT jobs get OOM-killed; send them to batch.

## Quotas on login areas

- AFS work dirs fill quickly (~95% seen). Keep code and logs on AFS and outputs on EOS.
- AFS directories hold ~32k entries; use per-step log subdirectories.
- LPC: `$HOME` ~3 GB, `/uscms_data` 200 GB soft for all projects.

## Shell-scripting traps seen in batch/ssh wrappers

- `set -u` while sourcing LCG/CMSSW/key4hep setup scripts fails (`COMPILER: unbound variable`). Wrap them in `set +u … set -u`.
- `set -o pipefail` with `xzcat big | awk '...exit'` returns 141 (SIGPIPE) after a correct result.
- `cmd | grep -v X && next`: grep exits 1 when it prints nothing, so `next` is silently skipped.
- Never pass `root://` URLs through Python `pathlib`: `Path("root://h//p")` becomes `root:/h/p`.
- Never `pkill -f` with a pattern that also matches your own shell or ssh command.

## Gotchas

More field notes, each from a real failure.

- Pinned nodes need `-o HostKeyAlias=lxplus.cern.ch`. If your ssh config has `HostName %h.cern.ch`, pass the bare node name.
- Non-interactive ssh shells have no `X509_USER_PROXY`; export it in every remote command.
- Kerberos tickets can be non-renewable; then nothing helps but the user's `kinit` (`! kinit <user>@CERN.CH` in Claude Code).
- Apptainer on lxplus needs `-B ${XDG_RUNTIME_DIR} --env KRB5CCNAME=FILE:${XDG_RUNTIME_DIR}/krb5cc` to see /eos/user. Without it, it silently falls back to the AFS home.
- `scp` no longer expands remote `{a,b}`; use `ssh lxplus 'tar cf - a b' | tar xf -`.
- `pkill -f`/`pgrep -f` over ssh matches the remote `bash -c` of that same ssh command: it killed its own session and gave false "still running" answers. List processes, then kill explicit PIDs.
- zsh: `echo =====` fails (`=word` expands to a command path), and `$var` isn't word-split. Process substitution `<(...)` can fail in sandboxed shells.
- Job managers that call `os.get_terminal_size()` crash without a TTY. Use tmux, or run the generated executables directly.
- Keep caches off a full AFS: point `XDG_CACHE_HOME`, `MPLCONFIGDIR` and `PIP_CACHE_DIR` at `/tmp/$USER`.
- **For agents:** a batch submission or other shared-resource mutation needs the user's go-ahead in your own session. A peer relaying "user approved" doesn't count, and auto mode blocks it.

## Docs

- lxplus service: <https://lxplusdoc.web.cern.ch/>
- Kerberos at CERN: <https://linux.web.cern.ch/docs/kerberos-access/>
- lxtunnel / 2FA ssh access: <https://lxplusdoc.web.cern.ch/connect/>
- Source field notes (DickyChant): <https://gist.github.com/DickyChant/5c2a7a8db793a129ae8f637b9c6dfe1a>
