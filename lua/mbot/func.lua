--[[----------------------------------------
    Functions
----------------------------------------]]--

local stepHeight = 18
local jumpHeight = 58
local dropHeight = 128 -- This value is based on a random guess!

function MBot.AddBot(cName)
    if not navmesh.IsLoaded() then
        MsgN("[MorBots] ERROR! No navmesh found!")
        return
    end

    if player.GetCount() == game.MaxPlayers() then
        MsgN("[MorBots] ERROR! Server is full!")
        return
    end

    local name = cName or "Bot #" .. #player.GetBots() + 1

    local bot = player.CreateNextBot(name)
    if not bot then
        MsgN("[MorBots] ERROR! Bot couldn't be created!")
        return
    end
end

function MBot.KickBot(cName)
    local bots = player.GetBots()
    if cName then
        for i = 1, #bots do
            if bots[i]:Name() == cName then
                bots[i]:Kick()
                return
            end
        end
        MsgN("[MorBots] ERROR! No bot with the name " .. cName .. " found!")
    else
        for i = 1, #bots do
            bots[i]:Kick()
        end
    end
end

function MBot.PathGenerator(isAlien, area, fromArea, ladder, elevator, length)
    if not IsValid(fromArea) then
		return 0
	else
		local dist = 0

		if IsValid(ladder) then
			dist = ladder:GetLength()
		elseif length > 0 then
			dist = length
		else
			dist = (area:GetCenter() - fromArea:GetCenter()):GetLength()
		end

		local cost = dist + fromArea:GetCostSoFar()

        if not IsValid(ladder) then
            local deltaZ = fromArea:ComputeAdjacentConnectionHeightChange(area)
            if deltaZ >= stepHeight then
                if deltaZ >= jumpHeight then
                    return -1
                end

                cost = cost + 5 * dist
            elseif not isAlien and deltaZ < -dropHeight then
                return -1
            end
        end

		return cost
	end
end

function MBot.FindRandomSpot(bot)
    if not IsValid(bot) then return end

    local areaTbl = navmesh.Find(bot:GetPos(), 99999, 18, 300)
    if #areaTbl == 0 then return end

    local area = areaTbl[math.random(#areaTbl)]
    if not IsValid(area) then return end

    local pos = area:GetRandomPoint()
    if not pos then return end

    return pos
end

function MBot.IsPosWithinFOV(bot, pos, cFov)
    local fov = cFov or 100
	local diff = pos - bot:EyePos()
	local dot = bot:GetAimVector():Dot(diff)

	if dot < 0 then return false end

	local cosHalfFov = math.cos(math.rad(fov * 0.5))
	return (dot * dot) >= (cosHalfFov * cosHalfFov) * diff:LengthSqr()
end

local propTrace = {mask = MASK_SHOT}

function MBot.IsTargetVisible(bot, target)
    if not bot.BotStates then return nil end

    if not target:IsPlayer() then
        local propCenter = target:WorldSpaceCenter()

        propTrace.start = bot:EyePos()
        propTrace.endpos = propCenter

        local trace = util.TraceLine(propTrace)
        if trace.Hit and trace.Entity == target then
            return propCenter
        end

        return nil
    end

    local targetEyePos = target:EyePos()

    if bot.BotStates.whatRole ~= 2 then
        if not MBot.IsPosWithinFOV(bot, targetEyePos) then
            return nil
        end
    end

    if bot:VisibleVec(targetEyePos) then
        return targetEyePos
    end

    local targetBodyPos = target:WorldSpaceCenter()
    if bot:VisibleVec(targetBodyPos) then
        return targetBodyPos
    end

    local targetFeetPos = target:GetPos()
    if bot:VisibleVec(targetFeetPos) then
        return targetFeetPos
    end

    return nil
end
