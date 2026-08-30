local nix = require("nix")
local colors = nix.colors
local paths = nix.paths

local mod = "SUPER"
local scripts = paths.scripts

local function setup_env()
    for _, e in ipairs({
        { "XDG_CURRENT_DESKTOP", "Hyprland" },
        { "XDG_SESSION_TYPE", "wayland" },
        { "XDG_SESSION_DESKTOP", "Hyprland" },
        { "GDK_BACKEND", "wayland" },
        { "GTK_USE_PORTAL", "0" },
        { "QT_QPA_PLATFORMTHEME", "qt5ct" },
        { "QT_STYLE_OVERRIDE", "kvantum" },
        { "COLOR_SCHEME", "prefer-dark" },
        { "ELECTRON_OZONE_PLATFORM_HINT", "auto" },
        { "MOZ_ENABLE_WAYLAND", "1" },
        { "TERMINAL", "alacritty" },
    }) do
        hl.env(e[1], e[2])
    end
end

local monitors = {
    { output = "", mode = "highres", scale = "1" },
    { output = "eDP-1", scale = "1.5" },
    { output = "desc:LG Electronics LG HDR WQHD 207NTXRAJ498", scale = "1" },
    { output = "desc:LG Electronics LG HDR 4K 0x00016261", scale = "1.5" },
}

function _G.reflow_monitors(lid_closed)
    for _, m in ipairs(monitors) do
        local rule = { output = m.output, mode = m.mode, position = "auto", scale = m.scale }
        if lid_closed and m.output == "eDP-1" then
            rule.disabled = true
        end
        hl.monitor(rule)
    end
end

local function lid_closed()
    local f = io.popen("cat /proc/acpi/button/lid/*/state 2>/dev/null")
    if not f then
        return false
    end
    local out = f:read("*a") or ""
    f:close()
    return out:lower():find("closed") ~= nil
end

local function setup_monitors()
    reflow_monitors(lid_closed())
end

local function setup_config()
    hl.config({
        general = {
            layout = "hy3",
            gaps_workspaces = 0,
            gaps_in = 0,
            gaps_out = 0,
            hover_icon_on_border = false,
            col = {
                inactive_border = colors.crust,
                nogroup_border = colors.crust,
                active_border = colors.mauve,
                nogroup_border_active = colors.mauve,
            },
        },
        dwindle = { preserve_split = true },
        master = { new_status = "slave", orientation = "center" },
        ecosystem = { no_update_news = true, no_donation_nag = true },
        decoration = { blur = { enabled = false } },
        animations = { enabled = false },
        input = {
            repeat_rate = 50,
            repeat_delay = 300,
            force_no_accel = true,
            kb_layout = "us,dk,es",
            kb_options = "grp:toggle",
        },
        misc = {
            disable_hyprland_logo = true,
            disable_splash_rendering = true,
            focus_on_activate = false,
            disable_autoreload = true,
            lockdead_screen_delay = 5000,
        },
        xwayland = { force_zero_scaling = true },
    })
end

local function setup_plugins()
    if hl.plugin.hy3 == nil then
        return
    end
    hl.config({
        plugin = {
            hy3 = {
                node_collapse_policy = 2,
                tabs = {
                    height = 15,
                    padding = 5,
                    render_text = true,
                    text_center = false,
                    text_height = 8,
                    text_padding = 3,
                    colors = {
                        active = colors.mauve,
                        active_text = colors.text,
                        urgent = colors.red,
                        urgent_text = colors.text,
                        inactive = colors.surface0,
                        inactive_text = colors.subtext0,
                    },
                },
                autotile = {
                    enable = true,
                    ephemeral_groups = true,
                    trigger_width = 600,
                    trigger_height = 0,
                    workspaces = "all",
                },
            },
        },
    })
end

local function setup_device()
    hl.device({
        name = "snsl0028:00-2c2f:0028-touchpad",
        enabled = not lid_closed(),
        middle_button_emulation = true,
        clickfinger_behavior = true,
        drag_lock = true,
        tap_to_click = true,
        natural_scroll = false,
        scroll_method = "2fg",
        scroll_factor = 1.0,
        disable_while_typing = false,
    })
end

local function setup_autostart()
    hl.on("hyprland.start", function()
        for _, cmd in ipairs({
            "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP GTK_THEME XDG_DATA_DIRS SSH_AUTH_SOCK HYPRLAND_INSTANCE_SIGNATURE",
            "compositor-session hyprland",
            "hyprctl setcursor $XCURSOR_THEME $XCURSOR_SIZE",
            "wl-paste --watch cliphist store",
            "wl-clip-persist --clipboard regular",
            scripts .. "/hy3.tiling.sh",
            scripts .. "/touchpad.unlock-reload.sh",
            "wayle-widget kb-toast hypr",
        }) do
            hl.exec_cmd(cmd)
        end
    end)
end

local function setup_window_events()
    hl.on("window.open", function(w)
        if not w or not w.floating then return end
        if not (w.class and w.class:match("^jetbrains%-")) then return end
        local s = w.size
        hl.dispatch(hl.dsp.window.resize({ x = s.x, y = s.y + 1, window = w }))
        hl.dispatch(hl.dsp.window.resize({ x = s.x, y = s.y, window = w }))
    end)
end

local function hy3_focus(d)
    return function() hl.dispatch(hl.plugin.hy3.move_focus(d)) end
end

local function hy3_move(d)
    return function()
        local f = hl.get_active_window()
        if not f then return end
        local axis = (d == "l" or d == "r") and "x" or "y"
        local toward_max = (d == "r" or d == "d")
        local at_edge = true
        for _, w in ipairs(hl.get_workspace_windows(f.workspace)) do
            local beyond
            if toward_max then
                beyond = w.at[axis] > f.at[axis]
            else
                beyond = w.at[axis] < f.at[axis]
            end
            if beyond then
                at_edge = false
                break
            end
        end
        if not at_edge then hl.dispatch(hl.plugin.hy3.move_window(d)) end
    end
end

local function hy3_to_ws(n)
    return function() hl.dispatch(hl.plugin.hy3.move_to_workspace(tostring(n))) end
end

local function hy3_kill()
    hl.dispatch(hl.plugin.hy3.kill_active())
end

local function resize_active(dx, dy)
    return hl.dsp.window.resize({ x = dx, y = dy, relative = true })
end

local function setup_keybinds()
    hl.bind(mod .. " + RETURN", hl.dsp.exec_cmd("alacritty"))
    hl.bind(mod .. " + SHIFT + E", hl.dsp.exec_cmd("pcmanfm"))
    hl.bind(mod .. " + SPACE", hl.dsp.exec_cmd("rofi -drun-reload-desktop-cache -drun-use-desktop-cache -show drun -location 0 -width 60"))
    hl.bind(mod .. " + SHIFT + SPACE", hl.dsp.exec_cmd([[rofi -show combi -combi-modes "run" -modes combi -run-command "]] .. scripts .. [[/rofi.run.sh {cmd}" -location 0 -width 60]]))
    hl.bind(mod .. " + CTRL + SPACE", hl.dsp.exec_cmd([[rofi -show combi -combi-modes "window" -modes combi]]))
    hl.bind("SHIFT + Print", hl.dsp.exec_cmd("wayle screenshot output"))
    hl.bind("Print", hl.dsp.exec_cmd("wayle screenshot region"))
    hl.bind(mod .. " + Print", hl.dsp.exec_cmd("wayle screenshot window"))
    hl.bind(mod .. " + SHIFT + R", hl.dsp.exec_cmd("wayle recorder toggle"))
    hl.bind(mod .. " + V", hl.dsp.exec_cmd([[cliphist list | rofi -dmenu | cliphist decode | wl-copy && wtype -M ctrl v && notify-send "Pasted selection"]]))
    hl.bind(mod .. " + C", hl.dsp.exec_cmd([[wl-copy "$(wl-paste -p)" && notify-send "Copied selection"]]))
    hl.bind(mod .. " + M", hl.dsp.exec_cmd("mail-open"))

    hl.bind(mod .. " + SHIFT + Q", hy3_kill)
    hl.bind(mod .. " + F", hl.dsp.window.fullscreen())
    hl.bind(mod .. " + T", hl.dsp.window.float({ action = "toggle" }))
    hl.bind(mod .. " + escape", hl.dsp.exec_cmd("wayle-lock"))
    hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
    hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
    hl.bind(mod .. " + delete", hl.dsp.exit())

    local resize_step = { left = { -50, 0 }, right = { 50, 0 }, up = { 0, -50 }, down = { 0, 50 } }
    for key, d in pairs({ left = "l", right = "r", up = "u", down = "d" }) do
        hl.bind(mod .. " + " .. key, hy3_focus(d))
        hl.bind(mod .. " + SHIFT + " .. key, hy3_move(d))
        hl.bind(mod .. " + CTRL + " .. key, resize_active(resize_step[key][1], resize_step[key][2]))
    end

    for key, d in pairs({ mouse_down = "r", bracketright = "r", mouse_up = "l", bracketleft = "l" }) do
        hl.bind(mod .. " + " .. key, hy3_focus(d))
    end

    for combo, ws in pairs({
        ["SHIFT + mouse_down"] = "e+1",
        ["SHIFT + mouse_up"] = "e-1",
        ["SHIFT + bracketright"] = "e+1",
        ["SHIFT + bracketleft"] = "e-1",
        ["Tab"] = "e+1",
        ["SHIFT + Tab"] = "e-1",
    }) do
        hl.bind(mod .. " + " .. combo, hl.dsp.focus({ workspace = ws }))
    end

    for i = 1, 10 do
        local key = i % 10
        hl.bind(mod .. " + " .. key, hl.dsp.focus({ workspace = i }))
        hl.bind(mod .. " + SHIFT + " .. key, hy3_to_ws(i))
    end

    local submap_marker = '"$XDG_RUNTIME_DIR/wayle-submap"'
    local function enter_submap(name)
        return function()
            hl.dispatch(hl.dsp.exec_cmd("printf %s " .. name .. " > " .. submap_marker))
            hl.dispatch(hl.dsp.submap(name))
        end
    end
    local function exit_submap()
        hl.dispatch(hl.dsp.exec_cmd("rm -f " .. submap_marker))
        hl.dispatch(hl.dsp.submap("reset"))
    end
    hl.bind(mod .. " + R", enter_submap("resize_mode"))
    hl.define_submap("resize_mode", function()
        for key, step in pairs({ right = { 10, 0 }, left = { -10, 0 }, up = { 0, -10 }, down = { 0, 10 } }) do
            hl.bind(key, resize_active(step[1], step[2]), { repeating = true })
        end
        hl.bind("return", exit_submap)
        hl.bind("escape", exit_submap)
    end)

    for _, b in ipairs({
        { "XF86AudioPlay", "playerctl play-pause" },
        { "XF86AudioStop", "playerctl stop" },
        { "XF86AudioPrev", "playerctl previous" },
        { "XF86AudioNext", "playerctl next" },
        { "XF86AudioRaiseVolume", "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+" },
        { "XF86AudioLowerVolume", "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-" },
        { "XF86AudioMute", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle" },
        { "XF86AudioMicMute", "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle" },
        { "XF86MonBrightnessUp", scripts .. "/monitor.brightness.sh increase" },
        { "XF86MonBrightnessDown", scripts .. "/monitor.brightness.sh decrease" },
    }) do
        hl.bind(b[1], hl.dsp.exec_cmd(b[2]), { locked = true })
    end
end


local function setup_window_rules()
    hl.window_rule({ name = "steam-float", match = { class = "steam" }, float = true })
    hl.window_rule({ name = "steam-main-tile", match = { class = "steam", title = "^Steam$" }, tile = true })
    hl.window_rule({ name = "steam-friends-tile", match = { class = "steam", title = "^Friends List$" }, tile = true, size = "400 900" })
end

setup_env()
setup_monitors()
setup_config()
setup_plugins()
setup_device()
setup_autostart()
setup_window_events()
setup_keybinds()
setup_window_rules()
