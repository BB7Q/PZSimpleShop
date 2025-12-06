require 'OptionScreens/MainOptions'
require 'keyBinding'

-- Taken from the Spraypaint mod --
local function addBind(name, key, displayName)--{{{
	local bind = {}
	bind.value = name
	bind.key = key
	bind.displayName = displayName or name
	table.insert(keyBinding, bind) -- global key bindings in zomboid/media/lua/shared/keyBindings.lua
end

table.insert(keyBinding, {value="[SimpleShop]"}) -- adds a section header to keys.ini and the options screen
addBind("OpenSimpleShop", Keyboard.KEY_O, "UI_optionscreen_binding_OpenSimpleShop");

