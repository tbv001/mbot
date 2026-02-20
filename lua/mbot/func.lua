--[[----------------------------------------
    Functions
----------------------------------------]]--

function MBot.AddBot(cName, bIsQuota)
    if not navmesh.IsLoaded() then
        MsgN("[Morbus Bots] ERROR! No navmesh found!")
        return
    end

    if player.GetCount() == game.MaxPlayers() then
        MsgN("[Morbus Bots] ERROR! Server is full!")
        return
    end

    local name = cName or "Bot #" .. #player.GetBots() + 1

    local bot = player.CreateNextBot(name)
    if not bot then
        MsgN("[Morbus Bots] ERROR! Bot couldn't be created!")
        return
    end

    if not bIsQuota then
        GetConVar("morbus_bot_quota"):SetInt(#player.GetHumans() + #player.GetBots())
    end
end

function MBot.KickBot(cName)
    local bots = player.GetBots()
    if cName then
        for i = 1, #bots do
            if bots[i]:Name() == cName then
                bots[i]:Kick()
                GetConVar("morbus_bot_quota"):SetInt(#player.GetHumans() + #player.GetBots() - 1)
                break
            end
        end
        MsgN("[Morbus Bots] ERROR! No bot with the name " .. cName .. " found!")
    else
        for i = 1, #bots do
            bots[i]:Kick()
        end
        GetConVar("morbus_bot_quota"):SetInt(0)
    end
end

local stepHeight = 18
local jumpHeight = 58
local dropHeight = 128 -- This value is based on a random guess!

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
    if not IsValid(bot) then return false end
    if not bot:Alive() then return false end

    local fov = cFov or 100
	local diff = pos - bot:EyePos()
	local dot = bot:GetAimVector():Dot(diff)

	if dot < 0 then return false end

	local cosHalfFov = math.cos(math.rad(fov * 0.5))
	return (dot * dot) >= (cosHalfFov * cosHalfFov) * diff:LengthSqr()
end

function MBot.IsBotObserved(bot, observer)
    if not IsValid(bot) or not IsValid(observer) then return false end
    if not observer:Alive() then return false end

    local botEye = bot:EyePos()
    local botCenter = bot:WorldSpaceCenter()
    
    local inFOV = MBot.IsPosWithinFOV(observer, botEye, 160) or MBot.IsPosWithinFOV(observer, botCenter, 160)
    if not inFOV then return false end

    if observer.Mission_Doing then
        return false
    end

    if observer:VisibleVec(botEye) or observer:VisibleVec(botCenter) then
        return true
    end

    if observer:VisibleVec(bot:GetPos()) then
        return true
    end

    return false
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

local dirClearTrace = {mask = MASK_PLAYERSOLID_BRUSHONLY, mins = Vector(-13, -13, -13), maxs = Vector(13, 13, 13)}
local flrTrace = {mask = MASK_PLAYERSOLID_BRUSHONLY}

function MBot.IsDirClear(bot, dir)
    local origin = bot:WorldSpaceCenter()
    local scaledDir = dir * 100

    dirClearTrace.start = origin
    dirClearTrace.endpos = origin + scaledDir

    local trace = util.TraceHull(dirClearTrace)

    local vec = scaledDir * trace.Fraction
    flrTrace.start = origin + vec
    flrTrace.endpos = origin + vec + Vector(0, 0, -58)

    local trace2 = util.TraceLine(flrTrace)
    if not trace2.Hit then return 0 end

    return vec
end

local sleepClasses = {"need_bed", "need_bedroom"}
local eatClasses = {"need_food", "need_restaurant"}
local cleanClasses = {"need_wash", "need_shower"}
local bathroomClasses = {"need_piss", "need_toilet"}

local function addEntities(tbl, classes)
    for i = 1, #classes do
        local found = ents.FindByClass(classes[i])
        for j = 1, #found do
            local ent = found[j]
            if IsValid(ent) then
                tbl[#tbl + 1] = ent:GetPos()
            end
        end
    end
end

function MBot.PopulateNeedsPos(sleepTbl, eatTbl, cleanTbl, bathroomTbl)
    table.Empty(sleepTbl)
    table.Empty(eatTbl)
    table.Empty(cleanTbl)
    table.Empty(bathroomTbl)

    addEntities(sleepTbl, sleepClasses)
    addEntities(eatTbl, eatClasses)
    addEntities(cleanTbl, cleanClasses)
    addEntities(bathroomTbl, bathroomClasses)
end

function MBot.GetMeleeMovement(bot, state, botPos, target)
    if not IsValid(target) then return nil end

    local curTime = CurTime()
    local targetPos = target:GetPos()
    local distSq = botPos:DistToSqr(targetPos)
    local dirToTarget = (targetPos - botPos):GetNormalized()
    local ang = dirToTarget:Angle()
    ang.p = 0
    local rightDir = ang:Right()
    local leftDir = -rightDir

    local targetFwd = target:GetAimVector()
    targetFwd.z = 0
    targetFwd:Normalize() -- Needed because zeroing z breaks unit length

    local toBot = (botPos - targetPos):GetNormalized()
    toBot.z = 0
    toBot:Normalize()

    -- behindDot > 0: Bot is in front of target
    -- behindDot < 0: Bot is behind target (flanking)
    local behindDot = targetFwd:Dot(toBot)
    
    -- cross.z determines if bot is to the left or right of target's view
    local cross = targetFwd:Cross(toBot)
    local preferredDir = cross.z > 0 and 1 or -1

    if distSq <= 10000 then
        if behindDot < -0.3 then
            if state.meleeFlankRushTime < curTime then
                state.meleeFlankRushTime = curTime + math.Rand(0.4, 0.8)
            end
        end

        if state.meleeFlankRushTime > curTime then
            return {
                forwardSpeed = 9999,
                sideSpeed = state.meleeCircleDir * 9999,
                moveAngle = ang
            }
        end

        if state.meleeCircleTime < curTime then
            local leftClear = MBot.IsDirClear(bot, leftDir)
            local rightClear = MBot.IsDirClear(bot, rightDir)

            local leftDist = isvector(leftClear) and leftClear:LengthSqr() or 0
            local rightDist = isvector(rightClear) and rightClear:LengthSqr() or 0

            if preferredDir == 1 and rightDist > 900 then
                state.meleeCircleDir = 1
            elseif preferredDir == -1 and leftDist > 900 then
                state.meleeCircleDir = -1
            elseif leftDist > rightDist then
                state.meleeCircleDir = -1
            elseif rightDist > leftDist then
                state.meleeCircleDir = 1
            else
                state.meleeCircleDir = math.random(1, 2) == 1 and 1 or -1
            end
            state.meleeCircleTime = curTime + math.Rand(1.0, 2.0)
        end

        local moveDir = state.meleeCircleDir == 1 and rightDir or leftDir
        local clear = MBot.IsDirClear(bot, moveDir)
        local clearDist = isvector(clear) and clear:LengthSqr() or 0

        if clearDist <= 900 then
            state.meleeCircleDir = -state.meleeCircleDir
            moveDir = state.meleeCircleDir == 1 and rightDir or leftDir
            clear = MBot.IsDirClear(bot, moveDir)
            clearDist = isvector(clear) and clear:LengthSqr() or 0

            -- If both directions are not clear, just move forward
            if clearDist <= 900 then
                return {
                    forwardSpeed = 9999,
                    sideSpeed = 0,
                    moveAngle = ang
                }
            end
        end

        -- If bot is in front of the target (behindDot > 0.2), move forward to close distance
        -- Otherwise, just focus on side movement to stay on the target's flank
        local fwdMove = behindDot > 0.2 and 9999 or 0

        return {
            forwardSpeed = fwdMove,
            sideSpeed = state.meleeCircleDir * 9999,
            moveAngle = ang
        }
    end

    return nil
end

function MBot.UpdateInventory(bot)
    local state = bot.BotStates
    if not state then return end

    local bestWep = nil
    local bestPrio = 0
    local curWeapons = bot:GetWeapons()

    table.Empty(state.inventory)
    
    for i = 1, #curWeapons do
        local wep = curWeapons[i]
        if not IsValid(wep) then continue end
        
        local class = wep:GetClass()
        local prio = 0
        
        -- Rifle > SMG/Light > Pistol > Melee
        if MBot.Database.WEAPON_RIFLE[class] then
            prio = 4
        elseif MBot.Database.WEAPON_LIGHT[class] then
            prio = 3
        elseif MBot.Database.WEAPON_PISTOL[class] then
            prio = 2
        elseif MBot.Database.WEAPON_MELEE[class] then
            prio = 1
        end

        state.inventory[class] = wep

        if prio > bestPrio then
            bestPrio = prio
            bestWep = wep
        end
    end
    
    state.bestWeapon = bestWep
    
    -- Drop any other weapon except melee weapons
    for i = 1, #curWeapons do
        local wep = curWeapons[i]
        if not IsValid(wep) or wep == bestWep then continue end

        local class = wep:GetClass()
        if not MBot.Database.WEAPON_MELEE[class] then
            if WEPS and WEPS.DropNotifiedWeapon then
                WEPS.DropNotifiedWeapon(bot, wep)
            else
                bot:DropWeapon(wep)
            end
        end
    end
end
