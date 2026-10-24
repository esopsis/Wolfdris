#!/usr/bin/env bash
# Run a long command and stop it if it stalls.
#
# Usage: scripts/watch.sh [--stall SECONDS] [--log FILE] -- COMMAND [ARGS...]
#
# Progress means any of: the command's output grew, its Linux processes used
# CPU, or the Windows Wolfram kernels used CPU (generated programs run there,
# outside the Linux process tree). If none of that happens for --stall
# seconds (default 300), it prints a STALL report, kills the command and
# exits 3. Otherwise it exits with the command's own status.
#
# Only kernels started after the command count, so unrelated long-running
# kernels (e.g. an editor's or MCP server's) can't mask a stall.
#
# This catches *silent* hangs. A busy infinite loop keeps using CPU, so it
# isn't a stall; that's what WOLFDRIS_TIMEOUT (enforced inside the kernel)
# is for. Use both.
#
# Note: killing the command does not reach a Windows kernel it started; the
# report lists those kernels so they can be stopped (Stop-Process) if needed.
set -u
stall=300
log=""
while [ $# -gt 0 ]; do
  case "$1" in
    --stall) stall=$2; shift 2 ;;
    --log) log=$2; shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done
[ $# -gt 0 ] || { echo "usage: $0 [--stall S] [--log FILE] -- COMMAND..."; exit 2; }
[ -n "$log" ] || log=$(mktemp)

# Windows Wolfram processes started since the command began.
winProcs="Get-Process wolfram,WolframKernel,wolframscript -ErrorAction SilentlyContinue |
  Where-Object { \$_.StartTime -ge [DateTimeOffset]::FromUnixTimeSeconds(START).LocalDateTime }"
# Their total CPU seconds (0 if not on WSL).
winCpu() {
  command -v powershell.exe > /dev/null || { echo 0; return; }
  powershell.exe -NoProfile -Command \
    "[int](${winProcs//START/$start} | Measure-Object CPU -Sum).Sum" \
    2> /dev/null | tr -d '\r' | grep -E '^[0-9]+$' || echo 0
}
# Total CPU seconds of a Linux process group.
groupCpu() {
  ps -o times= -g "$1" 2> /dev/null | awk '{s += $1} END {print s + 0}'
}

start=$(date +%s)
setsid "$@" > "$log" 2>&1 &
pid=$!
pgid=$pid
last=$start
prevSize=0; prevCpu=0; prevWin=$(winCpu)

while kill -0 "$pid" 2> /dev/null; do
  # notice completion within a second; check progress every 15 s
  for _ in $(seq 15); do
    sleep 1
    kill -0 "$pid" 2> /dev/null || break 2
  done
  size=$(stat -c %s "$log" 2> /dev/null || echo 0)
  cpu=$(groupCpu "$pgid")
  win=$(winCpu)
  now=$(date +%s)
  if [ "$size" != "$prevSize" ] || [ "$cpu" != "$prevCpu" ] || [ "$win" != "$prevWin" ]; then
    last=$now
  fi
  prevSize=$size; prevCpu=$cpu; prevWin=$win
  if [ $((now - last)) -ge "$stall" ]; then
    echo "STALL: no output or CPU progress for $((now - last))s (after $((now - start))s): $*"
    echo "--- last output ($log):"
    tail -15 "$log"
    echo "--- Windows Wolfram processes started by this run (CPU s):"
    powershell.exe -NoProfile -Command \
      "${winProcs//START/$start} | Select-Object Id,ProcessName,StartTime,CPU | Format-Table -AutoSize | Out-String" \
      2> /dev/null | tr -d '\r' | sed '/^\s*$/d'
    kill -TERM -- -"$pgid" 2> /dev/null; sleep 2; kill -KILL -- -"$pgid" 2> /dev/null
    exit 3
  fi
done
wait "$pid"
rc=$?
cat "$log"
echo "--- done in $(( $(date +%s) - start ))s, exit $rc"
exit $rc
