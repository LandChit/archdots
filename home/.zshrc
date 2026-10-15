# Other
export EDITOR=nano
# The `simplychit` command and the scripts stowed beside it. The Hyprland
# session already has this (uwsm/env-hyprland); a TTY or ssh login does not.
[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"
alias py=python
alias ssh="TERM=xterm-256color ssh"

export _JAVA_OPTIONS='-Dawt.useSystemAAFontSettings=lcd -Dswing.aatext=true' 


# Pywal — restore terminal palette on every new shell
(cat ~/.cache/wal/sequences &)

# oh my zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_CUSTOM=~/.ohmyzsh_custom
ZSH_THEME="chit"

plugins=(git)

source $ZSH/oh-my-zsh.sh


#
# COPPIED FROM SOMEONE ELSE WALL
#

# ---- FZF -----

# Set up fzf key bindings and fuzzy completion
eval "$(fzf --zsh)"

# --- setup fzf theme (colors come from pywal16 via colors.sh sourced below) ---

# -- Use fd instead of fzf --

export FZF_DEFAULT_COMMAND="fd --hidden --strip-cwd-prefix --exclude .git"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND="fd --type=d --hidden --strip-cwd-prefix --exclude .git"

# Use fd (https://github.com/sharkdp/fd) for listing path candidates.
# - The first argument to the function ($1) is the base path to start traversal
# - See the source code (completion.{bash,zsh}) for the details.
_fzf_compgen_path() {
  fd --hidden --exclude .git . "$1"
}

# Use fd to generate the list for directory completion
_fzf_compgen_dir() {
  fd --type=d --hidden --exclude .git . "$1"
}

show_file_or_dir_preview="if [ -d {} ]; then eza --tree --color=always {} | head -200; else bat -n --color=always --line-range :500 {}; fi"

export FZF_CTRL_T_OPTS="--preview '$show_file_or_dir_preview'"
export FZF_ALT_C_OPTS="--preview 'eza --tree --color=always {} | head -200'"

# Advanced customization of fzf options via _fzf_comprun function
# - The first argument to the function is the name of the command.
# - You should make sure to pass the rest of the arguments to fzf.
_fzf_comprun() {
  local command=$1
  shift

  case "$command" in
    cd)           fzf --preview 'eza --tree --color=always {} | head -200' "$@" ;;
    export|unset) fzf --preview "eval 'echo \${}'"         "$@" ;;
    ssh)          fzf --preview 'dig {}'                   "$@" ;;
    *)            fzf --preview "$show_file_or_dir_preview" "$@" ;;
  esac
}

# CANT BE A RELATIVE PATH afaik
EZA_CONFIG_DIR="~/.config/eza/"
alias ls="eza --icons=always --color=always --git --no-time --no-user --no-permissions --no-filesize -lha"


# ---- Zoxide (better cd) ----
eval "$(zoxide init zsh)"

alias cd="z"
alias cat="bat"

# Pywal — load color variables + override FZF colors with current palette
source ~/.cache/wal/colors.sh

# Your own settings: ~/.config/simplychit/local/zshrc (not tracked, never
# overwritten by updates). Sourced after everything else so it can override
# it, but before the plugins below, so syntax highlighting still wraps any
# widget it defines.
# ~/.custom.zsh is the old location and is still read if it exists.
[[ -r ~/.custom.zsh ]] && source ~/.custom.zsh
[[ -r ~/.config/simplychit/local/zshrc ]] && source ~/.config/simplychit/local/zshrc

# zsh plugins, from pacman (zsh-autosuggestions, zsh-syntax-highlighting).
# Syntax highlighting goes last: it wraps every widget defined before it.
[[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] &&
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] &&
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
