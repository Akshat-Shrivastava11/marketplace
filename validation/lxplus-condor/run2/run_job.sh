#!/bin/bash
# Worker wrapper. Args: <job label> <root:// input 1> <root:// input 2>
# Stages inputs with xrdcp, runs payload.py on the LCG view from CVMFS,
# validates the JSON, then stages it to FNAL EOS with the eos-xrootd copy pattern.
LABEL=$1; IN1=$2; IN2=$3
echo "host=$(hostname) date=$(date -u +%FT%TZ) label=${LABEL} cluster=${CONDOR_CLUSTER:-?}"
RUN_DIR="${_CONDOR_SCRATCH_DIR:-$PWD}"
cd "$RUN_DIR" || exit 2

export X509_USER_PROXY=/afs/cern.ch/user/<u>/<user>/private/<proxy>
export PYTHONNOUSERSITE=1
export EOS_DIR_XROOT=root://cmseos.fnal.gov
export EOS_DIR_PATH=/store/user/<user>/cms-marketplace-tests/lxplus-condor/run2

# (no set -u: the LCG setup script reads unset variables)
set +u
source /cvmfs/sft.cern.ch/lcg/views/LCG_106/x86_64-el9-gcc13-opt/setup.sh
python3 -c "import uproot, awkward; print('uproot', uproot.__version__, 'awkward', awkward.__version__)" || { echo "ENV_FAIL"; exit 3; }

# Stage inputs (retry with backoff; never skip silently).
LOCAL_FILES=()
for URL in "$IN1" "$IN2"; do
  BASE=$(basename "$URL")
  OK=0
  for TRY in 1 2 3 4 5 6; do
    if timeout 900 xrdcp -f -s "$URL" "$RUN_DIR/$BASE"; then OK=1; break; fi
    echo "stage retry $TRY for $URL"; sleep 20
  done
  if [ "$OK" -ne 1 ]; then echo "STAGE_FAIL $URL"; exit 4; fi
  LOCAL_FILES+=("$RUN_DIR/$BASE")
done
ls -l "${LOCAL_FILES[@]}"

OUT="$RUN_DIR/job_${LABEL}.json"
python3 payload.py --out "$OUT" --job "$LABEL" --nevents 20000 "${LOCAL_FILES[@]}"
RC=$?
if [ "$RC" -ne 0 ] || [ ! -s "$OUT" ]; then echo "PAYLOAD_FAIL rc=$RC"; exit 5; fi
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['events_read_total']==40000, d; print('content ok')" "$OUT" \
  || { echo "CONTENT_FAIL"; exit 6; }

# Stage out: mkdir, xrdcp with posc + adler32, then verify size and checksum on FNAL EOS.
BASE_NAME=$(basename "$OUT")
REMOTE="$EOS_DIR_PATH/$BASE_NAME"
xrdfs "$EOS_DIR_XROOT" mkdir -p "$EOS_DIR_PATH" || echo "mkdir warning (may already exist)"
OK=0
for TRY in 1 2 3 4 5 6; do
  if timeout 600 xrdcp -f -s --posc --cksum adler32 "$OUT" "$EOS_DIR_XROOT/$REMOTE"; then OK=1; break; fi
  echo "copy retry $TRY"; sleep 20
done
if [ "$OK" -ne 1 ]; then echo "COPYFAIL $REMOTE"; exit 7; fi

LOCAL_SIZE=$(stat -c %s "$OUT")
LOCAL_CK=$(python3 -c "import zlib,sys; print('%08x' % zlib.adler32(open(sys.argv[1],'rb').read()))" "$OUT")
REMOTE_SIZE=$(xrdfs "$EOS_DIR_XROOT" stat "$REMOTE" | awk '/^Size:/{print $2}')
REMOTE_CK=$(xrdfs "$EOS_DIR_XROOT" query checksum "$REMOTE" | awk '{print $2}')
echo "local size=$LOCAL_SIZE adler32=$LOCAL_CK | remote size=$REMOTE_SIZE adler32=$REMOTE_CK"
if [ "$LOCAL_SIZE" = "$REMOTE_SIZE" ] && [ "${LOCAL_CK,,}" = "${REMOTE_CK,,}" ]; then
  echo "VERIFY_OK $REMOTE"
else
  echo "MISMATCH $REMOTE"; exit 8
fi
exit 0
