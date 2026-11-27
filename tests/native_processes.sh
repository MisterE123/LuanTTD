# Local child processes of a disposable native replay. Bound teardown so
# a client stuck closing X cannot make a completed gameplay test time out.
native_stop_children() {
  local pid alive attempt
  local -a children=()
  for pid in "$@"; do
    if [[ -n $pid ]]; then
      children+=("$pid")
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done
  for ((attempt=0;attempt<40;attempt++)); do
    alive=false
    for pid in "${children[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then alive=true; break; fi
    done
    if ! "$alive"; then break; fi
    sleep .125
  done
  for pid in "${children[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      printf 'Forced shutdown of disposable native fixture process %s\n' "$pid" >&2
      kill -KILL "$pid" 2>/dev/null || true
    fi
    # Wait only once the process has actually stopped. The shell will
    # reap any remaining signalled child when it leaves the fixture.
    if ! kill -0 "$pid" 2>/dev/null; then wait "$pid" 2>/dev/null || true; fi
  done
  return 0
}
