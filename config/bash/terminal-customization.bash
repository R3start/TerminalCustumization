# shellcheck shell=bash
# TerminalCustumization - bash configuration
# Sourced from ~/.bashrc:
#   [ -f ~/.config/terminal-customization/bash/terminal-customization.bash ] && . ~/.config/terminal-customization/bash/terminal-customization.bash
#
# Every block is guarded, so a missing tool never breaks the shell.

# Only for interactive shells
[[ $- == *i* ]] || return 0

TC_HOME="${TC_HOME:-$HOME/.config/terminal-customization}"

_tc_has() { command -v "$1" >/dev/null 2>&1; }

# User binaries installed by install.sh
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# ---------------------------------------------------------------------------
# Nushell as the default interactive shell
#   The first interactive bash in a terminal hands over to nu.
#   - TC_IN_NU is inherited by everything started from nu, so typing `bash`
#     inside nu gives you a normal bash (no loop).
#   - Set TC_NO_NU=1 (e.g. `TC_NO_NU=1 bash`) or create ~/.config/terminal-customization/no-nu
#     to stay in bash.
# ---------------------------------------------------------------------------
if [[ -z ${TC_IN_NU:-} && -z ${TC_NO_NU:-} && ! -e $TC_HOME/no-nu && -t 0 && -t 1 ]] && _tc_has nu; then
  export TC_IN_NU=1
  exec nu
fi

# ---------------------------------------------------------------------------
# Shared tool settings (same files are used by PowerShell and Nushell)
# ---------------------------------------------------------------------------
export EZA_CONFIG_DIR="$TC_HOME/eza"
export FZF_DEFAULT_OPTS_FILE="$TC_HOME/fzf/fzfrc"
export RIPGREP_CONFIG_PATH="$TC_HOME/ripgrep/ripgreprc"
export BAT_THEME="Microverse"

# Debian/Ubuntu ship bat as `batcat`
if ! _tc_has bat && _tc_has batcat; then
  alias bat='batcat'
  _tc_bat=batcat
else
  _tc_bat=bat
fi

# ---------------------------------------------------------------------------
# oh-my-posh prompt
# ---------------------------------------------------------------------------
if _tc_has oh-my-posh; then
  eval "$(oh-my-posh init bash --config "$TC_HOME/oh-my-posh/microverse-power.omp.json")"
fi

# ---------------------------------------------------------------------------
# eza - modern ls
# ---------------------------------------------------------------------------
if _tc_has eza; then
  alias ls='eza --icons=auto --group-directories-first'
  alias ll='eza --icons=auto --group-directories-first --long --header --git'
  alias la='eza --icons=auto --group-directories-first --long --header --git --all'
  alias lt='eza --icons=auto --group-directories-first --tree --level=2'
fi

# ---------------------------------------------------------------------------
# bat - cat with syntax highlighting
# ---------------------------------------------------------------------------
if _tc_has "$_tc_bat"; then
  # shellcheck disable=SC2139
  alias cat="$_tc_bat --paging=never"
  export MANPAGER="sh -c 'col -bx | $_tc_bat -l man -p'"
  export MANROFFOPT="-c"
fi

# ---------------------------------------------------------------------------
# duf / dust - disk usage
# ---------------------------------------------------------------------------
_tc_has duf && alias df='duf'
_tc_has dust && alias du='dust'

# ---------------------------------------------------------------------------
# fzf - fuzzy finder (Ctrl+T files, Ctrl+R history, Alt+C cd)
# ---------------------------------------------------------------------------
if _tc_has fzf; then
  if _tc_has rg; then
    export FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git/"'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  fi
  export FZF_CTRL_T_OPTS="--preview '$_tc_bat --color=always --style=numbers --line-range=:300 {}'"
  if _tc_has eza; then
    export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --icons=always --color=always {}'"
  fi
  eval "$(fzf --bash)"
fi

# ---------------------------------------------------------------------------
# gh - GitHub CLI completion
# ---------------------------------------------------------------------------
if _tc_has gh; then
  eval "$(gh completion -s bash)"
fi

# ---------------------------------------------------------------------------
# zoxide - smarter cd (z, zi). Keep last: it hooks into the prompt.
# ---------------------------------------------------------------------------
if _tc_has zoxide; then
  eval "$(zoxide init bash)"
fi

unset _tc_bat
