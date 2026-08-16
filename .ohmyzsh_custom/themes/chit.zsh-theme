# chit.zsh-theme — pywal-driven prompt for the floating-glass setup.
# Colors reference ANSI palette slots, which pywal repaints via
# ~/.cache/wal/sequences (sourced in .zshrc), so the prompt re-themes
# automatically with every wallpaper change. Accent = color4, like the shell.
#
#   ╭─ chit at lancetop in ~/archdots on (main ✗) using «.venv»
#   ╰─❯

setopt prompt_subst

ZSH_THEME_GIT_PROMPT_PREFIX="%F{8}on %F{6}("
ZSH_THEME_GIT_PROMPT_SUFFIX="%F{6})%f "
ZSH_THEME_GIT_PROMPT_DIRTY="%F{1} ✗%F{6}"
ZSH_THEME_GIT_PROMPT_CLEAN="%F{2} ✓%F{6}"

# venv segment (omz's default prompt injection is disabled)
VIRTUAL_ENV_DISABLE_PROMPT=1
function chit_venv_info {
  [[ -n "$VIRTUAL_ENV" ]] && echo "%F{8}using %F{5}«${VIRTUAL_ENV:t}»%f "
}

PROMPT='%F{8}╭─%f %F{6}%n%f %F{8}at%f %F{5}%m%f %F{8}in%f %B%F{4}%~%f%b $(git_prompt_info)$(chit_venv_info)
%F{8}╰─%(?.%F{4}.%F{1})❯%f '

# non-zero exit code, right-aligned in red
RPROMPT='%(?..%F{1}%?%f)'
