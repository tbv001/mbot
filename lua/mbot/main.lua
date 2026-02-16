--[[----------------------------------------
    Hook Functions
----------------------------------------]]--

local weaponCache = {}
local weaponCachePosLookup = {}

local function PlayerSpawn(bot)
    bot.BotStates = table.Copy(MBot.DefaultBotStates)
    bot.BotStates.goalPos = bot:GetPos()
    bot.Pathfinding = Path("Follow")
    bot.Pathfinding:SetGoalTolerance(20)
    bot.Pathfinding:SetMinLookAheadDistance(300)
    bot.Pathfinding:Compute(bot, bot.BotStates.goalPos, function(area, fromArea, ladder, elevator, length) return MBot.PathGenerator(false, area, fromArea, ladder, elevator, length) end)
end

-- This hook runs first before SetupMove
local function StartCommand(bot, ucmd)
    if not IsValid(bot.Pathfinding) then
        bot.BotStates = table.Copy(MBot.DefaultBotStates)
        bot.BotStates.goalPos = bot:GetPos()
        bot.Pathfinding = Path("Follow")
        bot.Pathfinding:SetGoalTolerance(20)
        bot.Pathfinding:SetMinLookAheadDistance(300)
        bot.Pathfinding:Compute(bot, bot.BotStates.goalPos, function(area, fromArea, ladder, elevator, length) return MBot.PathGenerator(false, area, fromArea, ladder, elevator, length) end)
    end

    local state = bot.BotStates
    local curTime = CurTime()
    local isTargetValid = false


    --[[----------------------------------------
        Update Bot States
    ----------------------------------------]]--

    -- Set target if pending
    if state.pendingTarget then
        state.curTarget = state.pendingTarget
        state.forgetTargetTime = curTime + 10
        state.pendingTarget = nil
    end

    -- Check if target is exists and visible
    if IsValid(state.curTarget) and state.curTarget:Alive() and state.forgetTargetTime > curTime then
        local visiblePos = MBot.IsTargetVisible(bot, state.curTarget)
        if visiblePos then
            state.targetVisibleTime = curTime + 2
            state.targetVisiblePos = visiblePos
            state.forgetTargetTime = curTime + 10
        else
            state.targetVisiblePos = nil
        end
        isTargetValid = true
    else
        state.curTarget = nil
        state.forgetTargetTime = 0
        state.targetVisibleTime = 0
        state.targetVisiblePos = nil
    end

    -- Update role
    if bot.GetRole then
        state.whatRole = bot:GetRole()
    end

    -- Update weapon info
    state.curWeapon = bot:GetActiveWeapon()
    if IsValid(state.curWeapon) then
        state.curWeaponClass = state.curWeapon:GetClass()
        state.isMelee = MBot.Database.WEAPON_MELEE[state.curWeaponClass] ~= nil
    else
        state.curWeaponClass = ""
        state.isMelee = false
    end

    -- Update movement info
    state.isCrouching = bot:Crouching()
    state.isOnGround = bot:IsOnGround()

    -- Update bot position
    state.botPos = bot:GetPos()

    -- Check if on ladder
    state.onLadder = bot:GetMoveType() == MOVETYPE_LADDER
    if state.prevOnLadder ~= state.onLadder then
        state.prevOnLadder = state.onLadder

        if state.onLadder then
            state.timeOnLadder = curTime + 10
        else
            state.timeOnLadder = 0
        end
    end


    --[[----------------------------------------
        Bot Actions/Buttons
    ----------------------------------------]]--

    local buttons = 0
    local targetVisible = isTargetValid and state.targetVisiblePos

    -- Jump
    if state.jumpTime > curTime then
        buttons = buttons + IN_JUMP
    end

    -- Crouch
    if not state.isOnGround or state.crouchTime > curTime then
        buttons = buttons + IN_DUCK
    end

    -- Change to weapon_mor_brood if the bot is a brood alien
    if state.whatRole == 2 and isTargetValid then
        local broodWep = bot:GetWeapon("weapon_mor_brood")
        if IsValid(broodWep) and state.curWeapon ~= broodWep and state.botPos:DistToSqr(state.curTarget:GetPos()) <= 90000 and bot.CanTransform then
            ucmd:SelectWeapon(broodWep)
        end
    end

    if state.whatRole ~= 3 then
        local bestWep = nil
        local bestPrio = 0
        local curWeapons = bot:GetWeapons()

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

            if prio > bestPrio then
                bestPrio = prio
                bestWep = wep
            end
        end

        if IsValid(bestWep) and state.curWeapon ~= bestWep and (state.whatRole ~= 2 or not isTargetValid or state.curWeaponClass ~= "weapon_mor_brood") then
            ucmd:SelectWeapon(bestWep)
        end

        -- Drop any other weapon except melee and misc weapons
        for i = 1, #curWeapons do
            local wep = curWeapons[i]
            if not IsValid(wep) or wep == bestWep then continue end

            local class = wep:GetClass()
            if not MBot.Database.WEAPON_MELEE[class] and not MBot.Database.WEAPON_MISC[class] then
                WEPS.DropNotifiedWeapon(bot, wep)
            end
        end
    end

    if IsValid(state.curWeapon) then
        -- Reload
        if state.curWeapon:Clip1() == 0 or (not isTargetValid and state.curWeapon:Clip1() < state.curWeapon:GetMaxClip1()) then
            buttons = buttons + IN_RELOAD
        end

        -- Attack
        local targetVisible = isTargetValid and state.targetVisiblePos
        local canAttack = targetVisible

        if state.isMelee or state.whatRole == 2 then
            canAttack = targetVisible and state.botPos:DistToSqr(state.curTarget:GetPos()) <= 10000
        end

        if canAttack and state.attack1Delay < curTime then
            buttons = buttons + IN_ATTACK
            state.attack1Delay = curTime + 0.05
        elseif not canAttack then
            buttons = buttons + IN_SPEED
        end
    end

    -- Forward when on ladder
    if state.onLadder then
        buttons = buttons + IN_FORWARD
    end

    -- Pickup weapons
    if state.whatRole ~= 3 and state.isMelee then
        for i = 1, #weaponCache do
            local wep = weaponCache[i]
            local wepPos = weaponCachePosLookup[wep]
            if IsValid(wep) and wepPos and state.botPos:DistToSqr(wepPos) <= 2500 then
                buttons = buttons + IN_USE
                break
            end
        end
    end

    ucmd:ClearMovement()
    ucmd:ClearButtons()
    ucmd:SetButtons(buttons)
end

local function SetupMove(bot, mv)
    if not IsValid(bot.Pathfinding) then
        return
    end

    --bot.Pathfinding:Draw()

    local segments = bot.Pathfinding:GetAllSegments()
    if not segments then
        return
    end

    local state = bot.BotStates
    local curTime = CurTime()
    local maxSpeed = 9999
    local forwardSpeed = maxSpeed
    local sideSpeed = 0
    local lookAngle = angle_zero
    local moveAngle = angle_zero
    local botPos = state.botPos
    local reachedDest = false
    local curSegmentPos = nil
    local isOnLadder = state.onLadder
    local pathHasLadder = false
    local currentlyLookingForWeapons = false

    -- Move through path segments
    if segments[state.pathSegment] and segments[state.pathSegment].pos:DistToSqr(botPos) < 900 then
        state.pathSegment = state.pathSegment + 1
    end

    if segments[state.pathSegment] then
        curSegmentPos = segments[state.pathSegment].pos

        if segments[state.pathSegment].area:GetAttributes() == NAV_MESH_CROUCH then
            state.crouchTime = curTime + 0.1
        end

        lookAngle = ((curSegmentPos + bot:GetCurrentViewOffset()) - bot:GetShootPos()):Angle()
        moveAngle = lookAngle
    end

    if segments[state.pathSegment] and segments[state.pathSegment].ladder then
        pathHasLadder = true
    end

    -- We reached our goal, stop moving
    if botPos:DistToSqr(state.goalPos) < 900 then
        forwardSpeed = 0
        sideSpeed = 0
        reachedDest = true
    end

    -- Stuck detection
    if not isOnLadder and not pathHasLadder and not reachedDest then
        if state.nextStuckCheck < curTime then
            if state.lastPos and botPos:Distance2DSqr(state.lastPos) < 900 then
                state.stuckTime = state.stuckTime + 0.5
            else
                state.stuckTime = 0
            end

            state.lastPos = botPos
            state.nextStuckCheck = curTime + 0.5
        end

        if state.stuckTime > 0 then
            if not state.isCrouching then
                state.jumpTime = curTime + 0.1
            end

            if state.stuckStrafeTime < curTime then
                state.stuckStrafeDir = (state.stuckStrafeDir == 1) and -1 or 1
                state.stuckStrafeTime = curTime + math.Rand(1, 2)
            end

            -- Back off for a bit after 2 seconds, mostly for cases where there is an automatic door in front that can't be opened
            if state.stuckTime > 2 then
                if state.stuckBackTime < curTime then
                    state.stuckBackTime = curTime + math.Rand(2, 3)
                end
            end

            -- Teleport after 15 seconds it's kind of cheaty, but we don't want to be stuck here forever
            if state.stuckTime > 15 then
                local nextSegmentPos = segments[state.pathSegment + 1] and segments[state.pathSegment + 1].pos or state.goalPos

                bot:SetPos(nextSegmentPos)
                state.stuckTime = 0
            end
        else
            state.stuckStrafeDir = 0
            state.stuckBackTime = 0
        end

        if state.stuckStrafeDir ~= 0 then
            sideSpeed = state.stuckStrafeDir * maxSpeed
        end

        if state.stuckBackTime > curTime then
            forwardSpeed = -maxSpeed
        end
    end

    local isTargetValid = IsValid(state.curTarget)
    local targetVisible = isTargetValid and state.targetVisiblePos

    -- Target acquired, look at it and set it as goal position
    if isTargetValid then
        if targetVisible then
            lookAngle = (targetVisible - bot:GetShootPos()):Angle()

            if not state.isMelee and state.whatRole ~= 2 then
                forwardSpeed = 0
            end
        end

        if state.targetVisibleTime > curTime then
            state.goalPos = state.curTarget:GetPos()
        elseif state.targetVisibleTime < curTime and reachedDest then
            state.curTarget = nil
            state.forgetTargetTime = 0
            state.targetVisibleTime = 0
            state.targetVisiblePos = nil
        end
    end

    -- Look for weapons if we are melee and don't have a target
    if state.whatRole ~= 3 and #weaponCache > 0 and state.isMelee then
        currentlyLookingForWeapons = true
        
        if state.lookForWeaponsTime < curTime then
            local weaponPos = weaponCachePosLookup[weaponCache[math.random(#weaponCache)]]
            state.goalPos = weaponPos
            state.lookForWeaponsTime = curTime + 10
        end
    end

    -- Set goalPos to a weapon or random position every 10 seconds
    if state.randomSpotTime < curTime and not isTargetValid and not currentlyLookingForWeapons then
        state.goalPos = MBot.FindRandomSpot(bot)
        state.randomSpotTime = curTime + 10
    elseif isTargetValid or currentlyLookingForWeapons then
        state.randomSpotTime = 0
    end

    -- Handle ladders
    if state.onLadder and segments[state.pathSegment] and segments[state.pathSegment].ladder then
        local targetPos = segments[state.pathSegment].pos
        local nextSegmentPos = segments[state.pathSegment + 1] and segments[state.pathSegment + 1].pos or targetPos
        lookAngle = (targetPos - bot:GetShootPos()):Angle()
        lookAngle.y = lookAngle.y + 180

        if nextSegmentPos.z > botPos.z + 15 then
            lookAngle.p = -45
        elseif nextSegmentPos.z < botPos.z - 15 then
            lookAngle.p = 45
        end

        forwardSpeed = maxSpeed
        sideSpeed = 0
        moveAngle = lookAngle
    elseif state.onLadder then
        bot:ExitLadder()

        if state.timeOnLadder < curTime then
            state.jumpTime = curTime + 0.1
        end
    end

    -- Finally, set the bot's move angle, view angle, and movement speeds
    local AimLerp = 0.12 --0.015 * 8
    mv:SetForwardSpeed(forwardSpeed)
    mv:SetSideSpeed(sideSpeed)
    mv:SetMoveAngles(moveAngle)
    bot:SetEyeAngles(LerpAngle(AimLerp, bot:EyeAngles(), lookAngle))
end


--[[----------------------------------------
    Coroutine Functions
----------------------------------------]]--

local curProcessingAmnt = 0
local processingLimit = 100

-- Shared processing limiter, should be used in heavy coroutines that needs a lot of processing done per tick
local function ShouldYield()
    curProcessingAmnt = curProcessingAmnt + 1
    if curProcessingAmnt >= processingLimit then
        curProcessingAmnt = 0
        coroutine.yield()
    end
end

local function UpdateGeneral()
    while true do
        for _, bot in player.Iterator() do
            if not IsValid(bot) then continue end
            if not bot:IsBot() then continue end
            if not bot.IsGame or not bot:IsGame() then continue end

            if not bot:Alive() and bot.NextSpawnTime and bot.NextSpawnTime < CurTime() then
                bot:Spawn()
                continue
            end

            local state = bot.BotStates
            if not state then continue end

            -- Infinite ammo
            state.curWeapon = bot:GetActiveWeapon()
            if IsValid(state.curWeapon) then
                local ammoType = state.curWeapon:GetPrimaryAmmoType()
                if ammoType then
                    bot:SetAmmo(state.curWeapon:GetMaxClip1(), ammoType)
                end
            end

            coroutine.yield()
        end

        coroutine.yield()
    end
end

local function UpdatePath()
    while true do
        for _, bot in player.Iterator() do
            if not IsValid(bot) then continue end
            if not bot:IsBot() then continue end
            if not bot:Alive() then continue end

            if IsValid(bot.Pathfinding) then
                local isAlien = bot.BotStates.whatRole ~= 1
                bot.Pathfinding:Compute(bot, bot.BotStates.goalPos, function(area, fromArea, ladder, elevator, length) return MBot.PathGenerator(isAlien, area, fromArea, ladder, elevator, length) end)
                bot.BotStates.pathSegment = 2
            end

            coroutine.yield()
        end

        coroutine.yield()
    end
end

local targetCandidates = {}
local targetDistLookup = {}

local function UpdateTargets()
    while true do
        for _, bot in player.Iterator() do
            if not IsValid(bot) then continue end
            if not bot:IsBot() then continue end
            if not bot:Alive() then continue end

            targetCandidates = {}
            targetDistLookup = {}

            local botPos = bot:GetPos()

            -- Get all target candidates within 1500 units of the bot
            local botRole = bot.BotStates.whatRole
            for _, ply in player.Iterator() do
                if not IsValid(ply) then continue end
                if not ply:Alive() then continue end
                if ply == bot then continue end

                -- 1 = Human, 2 = Brood, 3 = Swarm
                local plyRole = ply.GetRole and ply:GetRole() or 1
                local isHostile = false

                if botRole == 1 then
                    if plyRole == 2 then
                        local activeWeapon = ply:GetActiveWeapon()
                        if IsValid(activeWeapon) and activeWeapon:GetClass() == "weapon_mor_brood" then
                            isHostile = true
                        end
                    elseif plyRole == 3 then
                        isHostile = true
                    end
                elseif (botRole == 2 or botRole == 3) and plyRole == 1 then
                    isHostile = true
                end

                if not isHostile then continue end

                local plyPos = ply:GetPos()
                if botPos:DistToSqr(plyPos) < 2250000 then
                    targetCandidates[#targetCandidates + 1] = ply
                    targetDistLookup[ply] = botPos:DistToSqr(plyPos)
                end

                ShouldYield()
            end

            -- Sort targets by distance, closest first
            table.sort(targetCandidates, function(a, b)
                return targetDistLookup[a] < targetDistLookup[b]
            end)

            -- Find the first visible target
            for i = 1, #targetCandidates do
                local target = targetCandidates[i]
                local visiblePos = MBot.IsTargetVisible(bot, target)
                if visiblePos then
                    bot.BotStates.pendingTarget = target
                    break
                end

                ShouldYield()
            end

            ShouldYield()
        end

        coroutine.yield()
    end
end

local function UpdateWeaponCache()
    while true do
        local newCache = {}
        local newPosLookup = {}

        for _, categoryTable in pairs(MBot.Database) do
            if type(categoryTable) ~= "table" then continue end

            for classname, _ in pairs(categoryTable) do
                local foundEnts = ents.FindByClass(classname)
                for i = 1, #foundEnts do
                    local ent = foundEnts[i]
                    if IsValid(ent) and not IsValid(ent:GetOwner()) then
                        newCache[#newCache + 1] = ent
                        newPosLookup[ent] = ent:GetPos()
                    end
                end
                ShouldYield()
            end
        end

        weaponCache = newCache
        weaponCachePosLookup = newPosLookup

        coroutine.yield()
    end
end


--[[----------------------------------------
    Hooks
----------------------------------------]]--

local generalCoroutine = coroutine.create(UpdateGeneral)
local pathCoroutine = coroutine.create(UpdatePath)
local targetCoroutine = coroutine.create(UpdateTargets)
local weaponCacheCoroutine = coroutine.create(UpdateWeaponCache)

hook.Add("PlayerSpawn", "MBot_PlayerSpawn", function(bot, trans)
    if not IsValid(bot) or not bot:IsBot() then return end

    PlayerSpawn(bot)
end)

hook.Add("StartCommand", "MBot_StartCommand", function(bot, ucmd)
    if not IsValid(bot) or not bot:IsBot() then return end
    if not bot:Alive() then return end

    StartCommand(bot, ucmd)
end)

hook.Add("SetupMove", "MBot_SetupMove", function(bot, mv, cmd)
    if not IsValid(bot) or not bot:IsBot() then return end
    if not bot:Alive() then return end

    SetupMove(bot, mv)
end)

hook.Add("Think", "MBot_Think", function()
    if coroutine.status(generalCoroutine) == "suspended" then
        coroutine.resume(generalCoroutine)
    end

    if coroutine.status(pathCoroutine) == "suspended" then
        coroutine.resume(pathCoroutine)
    end

    if coroutine.status(targetCoroutine) == "suspended" then
        coroutine.resume(targetCoroutine)
    end

    if coroutine.status(weaponCacheCoroutine) == "suspended" then
        coroutine.resume(weaponCacheCoroutine)
    end
end)