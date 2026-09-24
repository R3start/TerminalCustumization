# >>> terminal-customization >>>
# Regenerates oh-my-posh, zoxide and fzf integration scripts on every start, so they
# always match the installed versions. Nushell loads them from the autoload folders.
do {
    let autoload = ($nu.default-config-dir | path join autoload)
    mkdir $autoload
    if (which zoxide | is-not-empty) { ^zoxide init nushell | save -f ($autoload | path join zoxide.nu) }
    if (which fzf | is-not-empty) { ^fzf --nushell | save -f ($autoload | path join fzf.nu) }
    if (which oh-my-posh | is-not-empty) {
        ^oh-my-posh init nu --config ('~/.config/terminal-customization/oh-my-posh/microverse-power.omp.json' | path expand)
    }
}
# <<< terminal-customization <<<
