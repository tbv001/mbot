MBot.CVars = {}

--[[----------------------------------------
    Convars
----------------------------------------]]--

CreateConVar("morbus_bot_quota", 0, FCVAR_ARCHIVE, "Sets the bot quota")
MBot.CVars.quota = GetConVar("morbus_bot_quota"):GetInt()


--[[----------------------------------------
    Convar Callbacks
----------------------------------------]]--

cvars.AddChangeCallback("morbus_bot_quota", function(cvar, old, new)
    MBot.CVars.quota = tonumber(new)
end)