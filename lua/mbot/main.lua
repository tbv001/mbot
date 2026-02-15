--[[----------------------------------------
    Hook Functions
----------------------------------------]]--

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
    if not IsValid(bot.Pathfinding) then return end

    local state = bot.BotStates
    local curTime = CurTime()
    local isTargetValid = false

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

    local buttons = 0
    local curWeapon = bot:GetActiveWeapon()
    local curWeaponValid = IsValid(curWeapon)
    local targetVisible = isTargetValid and state.targetVisiblePos

    -- Jump
    if state.jumpTime > curTime then
        buttons = buttons + IN_JUMP
    end

    -- Crouch
    if not bot:IsOnGround() or state.crouchTime > curTime then
        buttons = buttons + IN_DUCK
    end

    -- Change to weapon_mor_brood if the bot is a brood alien
    if state.whatRole == 2 then
        local broodWep = bot:GetWeapon("weapon_mor_brood")
        if IsValid(broodWep) and curWeapon ~= broodWep then
            ucmd:SelectWeapon(broodWep)
        end
    end

    -- Attack
    if curWeaponValid then
        if targetVisible and state.attack1Delay < curTime then
            buttons = buttons + IN_ATTACK
            state.attack1Delay = curTime + 0.05
        end
    end

    -- Forward when on ladder
    if state.onLadder then
        buttons = buttons + IN_FORWARD
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
    local botPos = bot:GetPos()
    local reachedDest = false
    local curSegmentPos = nil
    local isOnLadder = state.onLadder
    local pathHasLadder = false

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
            if not bot:Crouching() then
                state.jumpTime = curTime + 0.1
            end

            if state.stuckStrafeTime < curTime then
                state.stuckStrafeDir = (state.stuckStrafeDir == 1) and -1 or 1
                state.stuckStrafeTime = curTime + math.Rand(1, 2)
            end

            -- Back off for a bit after 2 seconds, mostly for cases where there is an automatic door in front that can't be opened
            if state.stuckTime > 2 then
                if state.stuckBackTime < curTime then
                    state.stuckBackTime = curTime + math.Rand(1, 2)
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

    -- Set goalPos to a random position every 10 seconds
    if state.randomSpotTime < curTime and not isTargetValid then
        state.goalPos = MBot.FindRandomSpot(bot)
        state.randomSpotTime = curTime + 10
    elseif isTargetValid then
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

                -- Role-based hostility: 1 = Human, 2 = Brood, 3 = Swarm
                local plyRole = ply.GetRole and ply:GetRole() or 1
                local isHostile = false

                if botRole == 1 then -- Human hostile to Brood (if active) and Swarm
                    if plyRole == 2 then -- Brood
                        local activeWeapon = ply:GetActiveWeapon()
                        if IsValid(activeWeapon) and activeWeapon:GetClass() == "weapon_mor_brood" then
                            isHostile = true
                        end
                    elseif plyRole == 3 then -- Swarm
                        isHostile = true
                    end
                elseif (botRole == 2 or botRole == 3) and plyRole == 1 then -- Alien hostile to Humans
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


--[[----------------------------------------
    Hooks
----------------------------------------]]--

local generalCoroutine = coroutine.create(UpdateGeneral)
local pathCoroutine = coroutine.create(UpdatePath)
local targetCoroutine = coroutine.create(UpdateTargets)

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
end)