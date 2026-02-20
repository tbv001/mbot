--[[----------------------------------------
    Quota Manager
----------------------------------------]]--

timer.Create("MBot_QuotaUpdate", 1, 0, function()
    local desired = math.max(0, MBot.CVars.quota - #player.GetHumans())
    local currentBots = #player.GetBots()

    if currentBots < desired then
        MBot.AddBot(nil, true)
    elseif currentBots > desired then
        local bots = player.GetBots()
        local botToKick = bots[#bots]
        if IsValid(botToKick) then
            botToKick:Kick()
        end
    end
end)
