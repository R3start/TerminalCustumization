# TerminalCustumization - Nushell configuration
# Installed to: ($nu.default-config-dir)/autoload/terminal-customization.nu
# Nushell loads every file in that folder automatically after config.nu.

$env.config.show_banner = false

# Windows: the console starts on the system OEM codepage, not UTF-8, unless something already
# switched it (PowerShell does this before handing off to Nushell, but Windows Terminal launches
# nu.exe directly). Under the wrong codepage, bat/eza/oh-my-posh's UTF-8 box-drawing and icon
# glyphs come out as mojibake (e.g. "Γöé" instead of a single "│").
if $nu.os-info.name == 'windows' { ^chcp 65001 | ignore }

# --- shared tool settings (same files as bash / PowerShell) ----------------
let tc_home = ('~/.config/terminal-customization' | path expand)
$env.TC_HOME = $tc_home
$env.EZA_CONFIG_DIR = ($tc_home | path join eza)
$env.FZF_DEFAULT_OPTS_FILE = ($tc_home | path join fzf fzfrc)
$env.RIPGREP_CONFIG_PATH = ($tc_home | path join ripgrep ripgreprc)
$env.BAT_THEME = 'Microverse'

# fzf: list files with ripgrep, preview with bat / eza
$env.FZF_DEFAULT_COMMAND = 'rg --files --hidden --glob "!.git/"'
# fzf's Nushell key bindings run FZF_CTRL_T_COMMAND through `sh -c`, which doesn't exist on Windows.
# There Ctrl+T uses fzf's built-in walker instead (skips .git, node_modules, ...).
if $nu.os-info.name != 'windows' { $env.FZF_CTRL_T_COMMAND = $env.FZF_DEFAULT_COMMAND }
$env.FZF_CTRL_T_OPTS = "--preview 'bat --color=always --style=numbers --line-range=:300 {}'"
$env.FZF_ALT_C_OPTS = "--preview 'eza --tree --level=2 --icons=always --color=always {}'"

# --- colours: oh-my-posh "microverse-power" palette ------------------------
#   red #f1184c, yellow #FFBB00, green #33DD2D, blue #3A86FF
$env.config.color_config = ($env.config.color_config | merge {
    separator: '#6c6c6c'
    leading_trailing_space_bg: { attr: n }
    header: { fg: '#3A86FF' attr: b }
    row_index: { fg: '#FFBB00' attr: b }
    empty: '#3A86FF'
    bool: '#2EC4E6'
    int: '#FFBB00'
    float: '#FFBB00'
    filesize: '#33DD2D'
    duration: '#FFBB00'
    date: '#FFBB00'
    range: '#FFBB00'
    string: '#d0d0d0'
    nothing: '#6c6c6c'
    binary: '#B45CFF'
    cell-path: '#d0d0d0'
    hints: '#6c6c6c'
    search_result: { bg: '#f1184c' fg: '#ffffff' }
    shape_external: '#3A86FF'
    shape_external_resolved: { fg: '#3A86FF' attr: b }
    shape_internalcall: { fg: '#3A86FF' attr: b }
    shape_garbage: { fg: '#ffffff' bg: '#f1184c' attr: b }
    shape_string: '#33DD2D'
    shape_string_interpolation: '#2EC4E6'
    shape_int: '#FFBB00'
    shape_float: '#FFBB00'
    shape_bool: '#2EC4E6'
    shape_flag: { fg: '#FFBB00' attr: b }
    shape_variable: '#B45CFF'
    shape_operator: '#f1184c'
    shape_keyword: { fg: '#f1184c' attr: b }
    shape_filepath: '#2EC4E6'
    shape_directory: '#2EC4E6'
    shape_globpattern: '#2EC4E6'
    shape_pipe: { fg: '#f1184c' attr: b }
})
$env.config.cursor_shape.emacs = 'line'

# --- aliases ----------------------------------------------------------------
# Nushell's built-in `ls` and `du` return structured tables, so they are kept.
# eza gives the classic colourful listing with icons and git status.
alias ll = eza --icons=auto --group-directories-first --long --header --git
alias la = eza --icons=auto --group-directories-first --long --header --git --all
alias lt = eza --icons=auto --group-directories-first --tree --level=2
alias l = eza --icons=auto --group-directories-first
alias cat = bat --paging=never
alias df = duf
