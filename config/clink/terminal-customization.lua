-- TerminalCustumization - Clink script for cmd.exe
-- (plain cmd, the Visual Studio "Developer Command Prompt" and every other cmd window).
-- install.ps1 registers this folder with `clink installscripts`, and Clink runs this
-- script in every cmd.exe it is injected into (Clink autorun).
--
-- Provides: the Oh My Posh prompt, the shared tool settings, doskey aliases for eza / bat /
-- duf / dust, and `z` / `zi` (zoxide). Anything whose tool is not installed is skipped.

local home = os.getenv("USERPROFILE") or ""
local tc = os.getenv("TC_HOME") or (home .. "\\.config\\terminal-customization")
local here = tc .. "\\clink"

-- Which tools are on PATH (one `where` call for all of them).
local tools = {}
local where = io.popen('where oh-my-posh eza bat duf dust zoxide fzf rg 2>nul')
if where then
    for line in where:lines() do
        local name = line:match("([^\\/]+)%.[eE][xX][eE]$")
        if name then tools[name:lower()] = true end
    end
    where:close()
end

-- Shared tool settings (same files as PowerShell, bash and Nushell).
os.setenv("EZA_CONFIG_DIR", tc .. "\\eza")
os.setenv("FZF_DEFAULT_OPTS_FILE", tc .. "\\fzf\\fzfrc")
os.setenv("RIPGREP_CONFIG_PATH", tc .. "\\ripgrep\\ripgreprc")
os.setenv("BAT_THEME", "Microverse")
if tools["rg"] then os.setenv("FZF_DEFAULT_COMMAND", 'rg --files --hidden --glob "!.git/"') end

-- Aliases (doskey macros: they work at the start of a command line).
local eza = "eza --icons=auto --group-directories-first"
if tools["eza"] then
    os.setalias("ls", eza .. " $*")
    os.setalias("ll", eza .. " --long --header --git $*")
    os.setalias("la", eza .. " --long --header --git --all $*")
    os.setalias("lt", eza .. " --tree --level=2 $*")
end
if tools["bat"] then os.setalias("cat", "bat --paging=never $*") end
if tools["duf"] then os.setalias("df", "duf $*") end
if tools["dust"] then os.setalias("du", "dust $*") end

-- zoxide: `z <name>` jumps, `zi` picks with fzf. cmd has no hooks, so every directory shown at
-- a new prompt is added to zoxide's database here.
if tools["zoxide"] then
    os.setalias("z", 'call "' .. here .. '\\z.cmd" $*')
    os.setalias("zi", 'call "' .. here .. '\\zi.cmd" $*')
    local last_dir
    clink.onbeginedit(function()
        local cwd = os.getcwd()
        if cwd and cwd ~= last_dir then
            last_dir = cwd
            local add = io.popen('zoxide add -- "' .. cwd .. '" 2>nul')
            if add then add:close() end
        end
    end)
end

-- Oh My Posh prompt (forward slashes, as recommended for cmd).
if tools["oh-my-posh"] then
    local config = (tc .. "\\oh-my-posh\\microverse-power.omp.json"):gsub("\\", "/")
    local init = io.popen('oh-my-posh init cmd --config "' .. config .. '"')
    if init then
        local script = init:read("*a")
        init:close()
        local chunk = script and load(script)
        if chunk then chunk() end
    end
end
