# shellcheck shell=bash
#
# bb-lock.sh — workspace-wide mutual exclusion for the bb-* scripts. Source it
# and take the lock before touching the workspace:
#
#   . "$(dirname "$0")/bb-lock.sh"
#   bb_lock_acquire "$WORKSPACE" "$@"
#
# The lock is a directory, so creating it is atomic everywhere we run. A second
# instance waits for the first, reporting who it is waiting on, until you either
# get the lock or give up with ^C. A lock left behind by a killed process is
# reclaimed automatically.
#
# BB_LOCK_OWNER carries the pid of the holder, so a process that inherits the
# lock — either across `exec` (bb-check becomes bb-each) or as a child — sees it
# as its own rather than waiting on itself forever. Only the pid that took the
# lock drops it.

BB_LOCK_DIR=""
BB_LOCK_WAITING_ON=""

bb_lock_acquire() {
  local workspace="$1"; shift
  local lockdir="$workspace/.bb-lock"
  local label

  label="$(basename "$0")"
  [[ $# -gt 0 ]] && label="$label $*"

  if [[ -n "${BB_LOCK_OWNER:-}" && "$(bb_lock_owner_field "$lockdir" pid)" == "$BB_LOCK_OWNER" ]]; then
    [[ "$BB_LOCK_OWNER" == "$$" ]] && bb_lock_arm_release "$lockdir"
    return 0
  fi

  while ! mkdir "$lockdir" 2>/dev/null; do
    # Released underneath us between the mkdir and the look — try again now.
    [[ -d "$lockdir" ]] || continue
    if bb_lock_is_stale "$lockdir"; then
      echo "==> reclaiming lock left behind by a dead process" >&2
      rm -rf "$lockdir"
      continue
    fi
    bb_lock_report_wait "$lockdir"
    sleep 2
  done

  [[ -n "$BB_LOCK_WAITING_ON" ]] && echo "==> lock acquired, carrying on" >&2
  {
    echo "pid=$$"
    echo "host=$(hostname)"
    echo "started=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "command=$label"
  } > "$lockdir/owner"
  export BB_LOCK_OWNER="$$"
  bb_lock_arm_release "$lockdir"
  return 0
}

bb_lock_release() {
  local status=$?
  if [[ -n "$BB_LOCK_DIR" && "$(bb_lock_owner_field "$BB_LOCK_DIR" pid)" == "$$" ]]; then
    rm -rf "$BB_LOCK_DIR"
  fi
  BB_LOCK_DIR=""
  return $status
}

bb_lock_arm_release() {
  BB_LOCK_DIR="$1"
  trap bb_lock_release EXIT
  trap 'bb_lock_release; exit 130' INT
  trap 'bb_lock_release; exit 143' TERM
}

# Announce who we are queued behind, once per holder — a wait that outlives one
# holder has something new to say, a wait that doesn't should stay quiet.
bb_lock_report_wait() {
  local lockdir="$1" holder
  holder="$(bb_lock_owner_field "$lockdir" pid)@$(bb_lock_owner_field "$lockdir" started)"
  [[ "$holder" == "$BB_LOCK_WAITING_ON" ]] && return 0
  BB_LOCK_WAITING_ON="$holder"

  printf '==> waiting for %s (pid %s on %s) since %s — ^C to give up\n' \
    "$(bb_lock_owner_field "$lockdir" command)" \
    "$(bb_lock_owner_field "$lockdir" pid)" \
    "$(bb_lock_owner_field "$lockdir" host)" \
    "$(bb_lock_owner_field "$lockdir" started)" >&2
  return 0
}

# A pid is only meaningful on the host that recorded it, and an owner file that
# is still missing a moment after the directory appeared belongs to a holder
# that died mid-acquisition.
bb_lock_is_stale() {
  local lockdir="$1" pid host

  if [[ ! -f "$lockdir/owner" ]]; then
    sleep 1
    [[ -f "$lockdir/owner" ]] || return 0
  fi

  pid="$(bb_lock_owner_field "$lockdir" pid)"
  host="$(bb_lock_owner_field "$lockdir" host)"
  [[ -n "$pid" && "$host" == "$(hostname)" ]] || return 1

  ps -p "$pid" >/dev/null 2>&1 && return 1
  return 0
}

bb_lock_owner_field() {
  local lockdir="$1" wanted="$2" key value
  [[ -f "$lockdir/owner" ]] || return 0
  while IFS='=' read -r key value; do
    if [[ "$key" == "$wanted" ]]; then
      printf '%s' "$value"
      return 0
    fi
  done < "$lockdir/owner"
  return 0
}
