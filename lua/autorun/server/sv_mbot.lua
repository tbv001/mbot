if game.SinglePlayer() or engine.ActiveGamemode() ~= "morbusgame" then return end

MBot = {}
include("mbot/database.lua")
include("mbot/states.lua")
include("mbot/cmd.lua")
include("mbot/func.lua")
include("mbot/main.lua")
