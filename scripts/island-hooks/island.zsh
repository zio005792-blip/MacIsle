# MacIsle: report long terminal commands (>= 20 s) when they finish,
# and show Codex as "running" while it is open in this terminal.
zmodload zsh/datetime 2>/dev/null
typeset -g __island_cmd="" __island_start=0
__island_skip=(vim nvim vi nano less more man top htop btop ssh tmux screen claude python3 python node irb fg watch tail)

__island_preexec() {
  __island_cmd="${1%% *}"; __island_cmd="${__island_cmd:t}"
  __island_start=$EPOCHREALTIME
  if [[ "$__island_cmd" == codex ]]; then
    ( /usr/bin/python3 "$HOME/.macisle/island-notify.py" shell start codex >/dev/null 2>&1 & )
  fi
}

__island_precmd() {
  local exit_status=$? cmd="$__island_cmd"
  __island_cmd=""
  [[ -z "$cmd" || $__island_start == 0 ]] && return
  local elapsed=$(( EPOCHREALTIME - __island_start )); __island_start=0
  if [[ "$cmd" == codex ]]; then
    ( /usr/bin/python3 "$HOME/.macisle/island-notify.py" shell end codex >/dev/null 2>&1 & )
    return
  fi
  (( elapsed < 20 )) && return
  (( ${__island_skip[(Ie)$cmd]} )) && return
  ( /usr/bin/python3 "$HOME/.macisle/island-notify.py" shell done "$cmd" $exit_status ${elapsed%.*} >/dev/null 2>&1 & )
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec __island_preexec
add-zsh-hook precmd __island_precmd
