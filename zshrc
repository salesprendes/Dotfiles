# ~/.zshrc — configuración de zsh

# ---------------------------------------------------------------------------
# Historial mejorado
# ---------------------------------------------------------------------------
HISTFILE=~/.zsh_history
HISTSIZE=50000               # entradas en memoria
SAVEHIST=50000               # entradas guardadas en disco

setopt SHARE_HISTORY         # comparte el historial entre terminales abiertas
setopt INC_APPEND_HISTORY    # escribe el historial al instante, no al cerrar
setopt HIST_IGNORE_DUPS      # no guarda un comando igual al anterior
setopt HIST_IGNORE_ALL_DUPS  # elimina duplicados antiguos del historial
setopt HIST_IGNORE_SPACE     # comandos que empiezan por espacio no se guardan
setopt HIST_REDUCE_BLANKS    # limpia espacios sobrantes antes de guardar
setopt HIST_VERIFY           # al expandir !! muestra antes de ejecutar
setopt EXTENDED_HISTORY      # guarda marca de tiempo de cada comando

# ---------------------------------------------------------------------------
# Comportamiento general
# ---------------------------------------------------------------------------
setopt AUTO_CD               # escribir un directorio = cd a él
setopt CORRECT               # sugiere correcciones de typos en comandos
setopt INTERACTIVE_COMMENTS  # permite comentarios con # en la línea interactiva

# ---------------------------------------------------------------------------
# Autocompletado
# ---------------------------------------------------------------------------
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select                          # menú navegable con flechas
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'   # case-insensitive
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}       # colores en el menú
zstyle ':completion:*' group-name ''                        # agrupa resultados por tipo
zstyle ':completion:*:descriptions' format '%F{yellow}─ %d ─%f'  # cabecera por grupo
zstyle ':completion:*:warnings' format '%F{red}sin coincidencias%f'
zstyle ':completion:*' rehash true                          # detecta binarios nuevos al vuelo
zstyle ':completion:*' use-cache on                         # cachea para autocompletar más rápido

# ---------------------------------------------------------------------------
# Búsqueda en el historial con las flechas ↑/↓
#   Escribes parte de un comando y ↑ busca coincidencias que empiecen igual
# ---------------------------------------------------------------------------
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search    # flecha arriba
bindkey '^[[B' down-line-or-beginning-search  # flecha abajo
bindkey '^[OA' up-line-or-beginning-search    # flecha arriba (modo aplicación)
bindkey '^[OB' down-line-or-beginning-search  # flecha abajo (modo aplicación)

# ---------------------------------------------------------------------------
# Navegación cómoda en la línea de comandos
# ---------------------------------------------------------------------------
bindkey '^[[1;5C' forward-word        # Ctrl+→  salta una palabra adelante
bindkey '^[[1;5D' backward-word       # Ctrl+←  salta una palabra atrás
bindkey '^[[H'  beginning-of-line     # Inicio
bindkey '^[[F'  end-of-line           # Fin
bindkey '^[[3~' delete-char           # Supr
bindkey '^[[3;5~' kill-word           # Ctrl+Supr  borra palabra siguiente

# ---------------------------------------------------------------------------
# Entorno
# ---------------------------------------------------------------------------
export EDITOR='nano'         # editor por defecto (lo pedía starship/git)
export VISUAL='nano'
export PAGER='less'
export LESS='-R'             # respeta los colores en less

# ---------------------------------------------------------------------------
# Aliases útiles
# ---------------------------------------------------------------------------
# Listados: usa 'eza' (más bonito) si está instalado; si no, ls de toda la vida
if command -v eza &>/dev/null; then
    alias ls='eza --group-directories-first --icons=auto'
    alias ll='eza -lh --group-directories-first --icons=auto --git'
    alias la='eza -lha --group-directories-first --icons=auto --git'
    alias lt='eza --tree --level=2 --icons=auto'
    alias l='eza -1 --icons=auto'
else
    alias ll='ls -lh --color=auto'
    alias la='ls -lha --color=auto'
    alias l='ls -CF --color=auto'
    alias ls='ls --color=auto'
fi
# 'cat' con colores si tienes bat
command -v bat   &>/dev/null && alias cat='bat --paging=never'
command -v batcat &>/dev/null && alias cat='batcat --paging=never'
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias mkdir='mkdir -pv'
alias path='echo $PATH | tr ":" "\n"'
alias reload='source ~/.zshrc && echo "✔ zsh recargado"'
alias ff='fastfetch'
alias cls='clear'
alias h='history'
alias ip='ip --color=auto'
alias ports='ss -tulpn'              # puertos en escucha
alias myip='curl -s ifconfig.me; echo'  # IP pública
# Git rápido
alias gs='git status -sb'
alias ga='git add'
alias gc='git commit -m'
alias gp='git push'
alias gl='git log --oneline --graph --decorate --all'
alias gd='git diff'
# Crea un directorio y entra en él de un paso
mkcd() { mkdir -pv "$1" && cd "$1"; }

# ---------------------------------------------------------------------------
# Plugins (cargados al final; el resaltado de sintaxis debe ir el último)
# ---------------------------------------------------------------------------
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#565f89'   # gris azulado, a juego con el tema
ZSH_AUTOSUGGEST_STRATEGY=(history completion)  # sugiere por historial y autocompletado
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# ---------------------------------------------------------------------------
# Prompt: Starship
# ---------------------------------------------------------------------------
eval "$(starship init zsh)"

# ---------------------------------------------------------------------------
# Abrir siempre en la carpeta personal (~) al iniciar la terminal
#   Solo la primera vez (no en subshells ni al abrir pestañas dentro de un
#   proyecto): si arranca en ~/.config la cambia a ~.
# ---------------------------------------------------------------------------
if [[ -o interactive ]] && [[ -z "$ZSH_STARTED" ]]; then
    export ZSH_STARTED=1
    [[ "$PWD" == "$HOME/.config" ]] && cd "$HOME"
fi

# ---------------------------------------------------------------------------
# Fastfetch al abrir terminal
#   Solo en shells interactivos sobre una terminal real (evita ejecutarlo
#   dentro de scripts, editores o sesiones sin TTY).
# ---------------------------------------------------------------------------
if [[ -o interactive ]] && [[ -t 1 ]] && command -v fastfetch &>/dev/null; then
    fastfetch
fi
export PATH="$HOME/.local/bin:$PATH"
