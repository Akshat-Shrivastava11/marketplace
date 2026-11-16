# Validation: `af-cern-lxplus`

**Status: validated** (`lxplus-access`, `lxplus-htcondor`, `eos-xrootd`),
Nov 2026. The task in [PROMPT.md](PROMPT.md) was run by Claude Haiku with no
other context, reading only the three skill files, from an FNAL cmslpc node
that drove lxplus over ssh through an `lxtunnel` ControlMaster. Results and
fixes: [RESULTS.md](RESULTS.md). `python3 check_results.py` repeats the
comparison with the LPC reference.

## Goal

Exercise `lxplus-access`, `lxplus-htcondor` and `eos-xrootd` end to end: a
4-job HTCondor run on lxbatch over 2016G JetHT NanoAOD Open Data, outputs
staged to EOS with verified `xrdcp`. The selection and inputs are the same as
[validation/lpc-condor](../lpc-condor), so the event counts can be compared
directly with the LPC run.

`crab` needs a grid certificate and a CMSSW area, so it is not covered here;
it should be validated separately with a one-task PrivateMC or a short
NanoAOD skim. The same PR adds `af-fnal-lpc/cmsconnect-lpc`
(production field notes); the LPC batch workflow itself is already validated
by [validation/lpc-condor](../lpc-condor).

## Credits

The skills are field notes by [@DickyChant](https://github.com/DickyChant),
from his [gist](https://gist.github.com/DickyChant/5c2a7a8db793a129ae8f637b9c6dfe1a).
See [CREDITS.md](../../CREDITS.md).
