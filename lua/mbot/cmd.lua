--[[----------------------------------------
    Commands
----------------------------------------]]--

concommand.Add("morbus_bot_add", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end

    local name = #args > 0 and table.concat(args, " ") or nil
    MBot.AddBot(name)
end, nil, "Adds a bot, with custom name if provided")

concommand.Add("morbus_bot_kick", function (ply, cmd, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end

    local name = #args > 0 and table.concat(args, " ") or nil
    MBot.KickBot(name)
end, nil, "Kicks all bots, or kick only specific bot if name provided")
