# your custom zshconfig (Add this to your home directory)
source ~/.zsh_custom 

# Other
export EDITOR=nano
alias py=python
alias ssh="TERM=xterm-256color ssh"

# Development
export ANDROID_HOME=~/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/tools
export PATH=$PATH:$ANDROID_HOME/tools/bin
export PATH=$PATH:$ANDROID_HOME/platform-tools

export PATH=$/usr/lib/flutter/bin:$PATH
export _JAVA_OPTIONS='-Dawt.useSystemAAFontSettings=lcd -Dswing.aatext=true' 


# Gaming
alias protontricks='flatpak run com.github.Matoking.protontricks'
alias protontricks-launch='flatpak run --command=protontricks-launch com.github.Matoking.protontricks'


# oh my zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_CUSTOM=~/.ohmyzsh_custom
ZSH_THEME="fino"

plugins=(git zsh-syntax-highlighting)

source $ZSH/oh-my-zsh.sh


#
# COPPIED FROM SOMEONE ELSE WALL
#

# ---- FZF -----

# Set up fzf key bindings and fuzzy completion
eval "$(fzf --zsh)"

# --- setup fzf theme ---
fg="#CBE0F0"
purple="#B388FF"
pink="#FF5784"
pink_dark="#8c344b"

export FZF_DEFAULT_OPTS="--color=fg:${fg},hl:${purple},fg+:${fg},bg+:${pink},hl+:${purple},info:${pink},prompt:${pink},pointer:${pink_dark},marker:${pink},spinner:${pink},header:${pink}"

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
