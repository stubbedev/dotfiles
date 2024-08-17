local wezterm = require("wezterm")
local config = wezterm.config_builder()
local act = wezterm.action

config.color_scheme = "Catppuccin Mocha"
config.enable_tab_bar = false
config.use_resize_increments = true
config.disable_default_key_bindings = true
config.keys = {
	{
		key = "P",
		mods = "CTRL",
		action = wezterm.action.ActivateCommandPalette,
	},
	{ key = "V", mods = "CTRL | SHIFT", action = act.PasteFrom("Clipboard") },
	{ key = "V", mods = "CTRL | SHIFT", action = act.PasteFrom("PrimarySelection") },
}
config.window_close_confirmation = 'NeverPrompt'
config.window_padding = {
	left = 0,
	right = 0,
	top = 0,
	bottom = 0,
}

return config
