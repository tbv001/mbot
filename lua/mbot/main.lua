--[[----------------------------------------
    Hook Functions
----------------------------------------]]--

local weaponCache = {}
local weaponCachePosLookup = {}
local friendliesCounts = {}
local alienEnemyCache = {}

-- Missions
local sleepPos = {}
local eatPos = {}
local cleanPos = {}
local bathroomPos = {}

local function PlayerSpawn(bot)
    bot.BotStates = table.Copy(MBot.DefaultBotStates)
    bot.BotStates.goalPos = bot:GetPos()
    bot.Pathfinding = Path("Follow")
    bot.Pathfinding:SetGoalTolerance(20)
    bot.Pathfinding:SetMinLookAheadDistance(300)
    bot.Pathfinding:Compute(bot, bot.BotStates.goalPos, function(area, fromArea, ladder, elevator, length) return MBot.PathGenerator(false, area, fromArea, ladder, elevator, length) end)

    if #sleepPos == 0 then
        MBot.PopulateNeedsPos(sleepPos, eatPos, cleanPos, bathroomPos)
    end
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
    if state.pendingTarget and (state.whatRole ~= 2 or (bot.CanTransform or state.broodExposed)) then
        state.curTarget = state.pendingTarget
        state.forgetTargetTime = curTime + 10
        state.pendingTarget = nil
        state.targetIsProp = false
    end

    -- Set prop target if pending
    if state.pendingProp then
        state.propTarget = state.pendingProp
    else
        state.propTarget = nil
    end

    -- Update role
    if bot.GetRole then
        state.whatRole = bot:GetRole()
    else
        state.whatRole = 1
    end

    -- Update bot position
    state.botPos = bot:GetPos()

    -- Check if target is exists and visible
    local targetRole = IsValid(state.curTarget) and (state.curTarget.GetRole and state.curTarget:GetRole() or 1) or 1
    local isLonely = (friendliesCounts[state.curTarget] or 0) == 0
    local isObserved = IsValid(state.curTarget) and MBot.IsBotObserved(bot, state.curTarget) or false
    if IsValid(state.curTarget) and state.curTarget:Alive() and (state.whatRole == 1 or targetRole == 1) and state.forgetTargetTime > curTime and (state.whatRole ~= 2 or state.broodExposed or (isLonely and not isObserved)) then
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

    -- Update mission
    if state.whatRole == 1 and bot.Mission then
        state.curMission = bot.Mission
        if state.prevMission ~= state.curMission then
            state.prevMission = state.curMission
            if state.curMission == 1 and #sleepPos > 0 then
                state.missionPos = sleepPos[math.random(#sleepPos)]
            elseif state.curMission == 2 and #eatPos > 0 then
                state.missionPos = eatPos[math.random(#eatPos)]
            elseif state.curMission == 3 and #cleanPos > 0 then
                state.missionPos = cleanPos[math.random(#cleanPos)]
            elseif state.curMission == 4 and #bathroomPos > 0 then
                state.missionPos = bathroomPos[math.random(#bathroomPos)]
            else
                state.missionPos = nil
            end
        end
    elseif state.whatRole ~= 1 then
        state.curMission = 0
        state.prevMission = 0
        state.missionPos = nil
    end

    -- Upgrade Brood bots
    if state.whatRole == 2 and bot.Evo_Points > 0 and state.upgradeCheckTime < curTime and not state.maxedOutUpgrades then
        state.upgradeCheckTime = curTime + 1
        
        local treePriority = {TREE_DEFENSE, TREE_OFFENSE, TREE_UTILITY}
        local loopCount = 0
        
        while bot.Evo_Points > 0 do
            loopCount = loopCount + 1
            local pointSpentThisLoop = false
            
            for i = 1, #treePriority do
                local tree = treePriority[i]
                local tier1Points = 0
                for j = 1, #UPGRADES do
                    if UPGRADES[j].Tree == tree and UPGRADES[j].Tier == 1 then
                        tier1Points = tier1Points + (bot.Upgrades[j] or 0)
                    end
                end
                
                local availableUpgrades = {}
                for j = 1, #UPGRADES do
                    if UPGRADES[j].Tree == tree then
                        local currentLevel = bot.Upgrades[j] or 0
                        local maxLevel = UPGRADES[j].MaxLevel or 0
                        if currentLevel < maxLevel then
                            if UPGRADES[j].Tier == 1 or (UPGRADES[j].Tier == 2 and tier1Points >= 3) then
                                availableUpgrades[#availableUpgrades + 1] = j
                            end
                        end
                    end
                end
                
                if #availableUpgrades > 0 then
                    local chosenIdx = availableUpgrades[math.random(1, #availableUpgrades)]
                    bot.Upgrades[chosenIdx] = (bot.Upgrades[chosenIdx] or 0) + 1
                    bot.Evo_Points = bot.Evo_Points - 1
                    pointSpentThisLoop = true
                    break
                end
            end
            
            if not pointSpentThisLoop then
                state.maxedOutUpgrades = true
                break
            end
        end
    end


    --[[----------------------------------------
        Bot Actions/Buttons
    ----------------------------------------]]--

    if bot.Mission_Doing and state.whatRole == 1 then
        return
    end

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
        if IsValid(broodWep) and state.curWeapon ~= broodWep and (state.broodExposed or (state.botPos:DistToSqr(state.curTarget:GetPos()) <= 14400 and bot.CanTransform)) then
            ucmd:SelectWeapon(broodWep)
            state.broodExposed = true
        end
    end

    if state.whatRole ~= 3 then
        if (state.nextWeaponCheck or 0) < curTime then
            MBot.UpdateInventory(bot)
            state.nextWeaponCheck = curTime + 1
        end

        local bestWep = state.bestWeapon

        if IsValid(bestWep) and state.curWeapon ~= bestWep and (state.whatRole ~= 2 or not isTargetValid and state.changeWepDelay < curTime) then
            ucmd:SelectWeapon(bestWep)
            state.broodExposed = false
        end
    end

    if IsValid(state.curWeapon) then
        -- Reload
        if state.curWeapon:Clip1() == 0 or (not isTargetValid and not IsValid(state.propTarget) and state.curWeapon:Clip1() < state.curWeapon:GetMaxClip1()) then
            buttons = buttons + IN_RELOAD
        end

        -- Attack
        local targetVisible = isTargetValid and state.targetVisiblePos
        local canAttack = targetVisible

        if state.isMelee or state.whatRole == 2 then
            canAttack = targetVisible and state.botPos:DistToSqr(state.curTarget:GetPos()) <= 10000
        end

        if (canAttack or state.forceAttack1Time > curTime) and state.attack1Delay < curTime then
            buttons = buttons + IN_ATTACK
            state.attack1Delay = curTime + 0.05
        end

        if targetVisible and state.whatRole == 3 and state.attack2CD < curTime then
            buttons = buttons + IN_ATTACK2
            state.attack2CD = curTime + math.random(3, 5)
        end
    end

    -- Forward when on ladder
    if state.onLadder then
        buttons = buttons + IN_FORWARD
    end

    -- Pickup weapons
    if state.whatRole ~= 3 and state.isMelee then
        if IsValid(state.closestWep) and state.closestWepDist and state.closestWepDist <= 2500 then
            buttons = buttons + IN_USE
        end
    end

    ucmd:ClearMovement()
    ucmd:ClearButtons()
    ucmd:SetButtons(buttons)
end

local function PlayerHurt(bot, attacker)
    if not bot.BotStates then return end
    if not IsValid(attacker) or not attacker:Alive() then return end

    local curTime = CurTime()
    local state = bot.BotStates
    local attackerRole = attacker.GetRole and attacker:GetRole() or 1

    if state.whatRole == 2 and attackerRole == 1 then
        state.broodExposed = true
        state.curTarget = attacker
        state.forgetTargetTime = curTime + 10
        state.lookAtPos = attacker:EyePos()
        state.lookAtTime = curTime + 2
    elseif not IsValid(state.curTarget) and state.whatRole == 3 and attackerRole == 1 then
        state.curTarget = attacker
        state.forgetTargetTime = curTime + 10
        state.lookAtPos = attacker:EyePos()
        state.lookAtTime = curTime + 2
    elseif not IsValid(state.curTarget) and state.whatRole == 1 then
        if attackerRole == 3 then
            state.curTarget = attacker
            state.forgetTargetTime = curTime + 10
        end

        state.lookAtPos = attacker:EyePos()
        state.lookAtTime = curTime + 2
    elseif IsValid(state.curTarget) and state.curTarget == attacker then
        state.forgetTargetTime = curTime + 10
        state.lookAtPos = attacker:EyePos()
        state.lookAtTime = curTime + 2
    end
end

local function SetupMove(bot, mv)
    if not IsValid(bot.Pathfinding) then
        return
    end

    local segments = bot.Pathfinding:GetAllSegments()
    if not segments then
        return
    end

    local state = bot.BotStates

    if bot.Mission_Doing and state.whatRole == 1 then
        return
    end

    local curTime = CurTime()
    local maxSpeed = 9999
    local forwardSpeed = maxSpeed
    local sideSpeed = 0
    local lookAngle = angle_zero
    local moveAngle = angle_zero
    local botPos = state.botPos or bot:GetPos()
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

    if segments[state.pathSegment] and segments[state.pathSegment].type ~= 0 and not pathHasLadder then
        state.jumpTime = curTime + 0.1
    end

    -- Path to mission position if exists
    local pathToMission = false
    if state.whatRole == 1 and state.curMission > 0 and state.missionPos then
        state.goalPos = state.missionPos
        pathToMission = true

        if botPos:DistToSqr(state.missionPos) < 900 and not bot.Mission_Doing then
            DoMission(bot)
        end
    end

    -- We reached our goal, stop moving
    if state.goalPos and botPos:DistToSqr(state.goalPos) < 900 and not pathToMission then
        forwardSpeed = 0
        sideSpeed = 0
        reachedDest = true
    end

    local isTargetValid = IsValid(state.curTarget)
    local isPropTargetValid = IsValid(state.propTarget)
    local targetVisible = isTargetValid and state.targetVisiblePos

    -- Stuck detection
    if not isOnLadder and not pathHasLadder and not reachedDest then
        if state.nextStuckCheck < curTime then
            if state.lastPos and (not targetVisible and botPos:Distance2DSqr(state.lastPos) < 900 or botPos:DistToSqr(state.lastPos) < 900) then
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

            -- CHEAT: Teleport after 15 seconds
            if state.stuckTime > 15 then
                local nextSegmentPos = segments[state.pathSegment + 1] and segments[state.pathSegment + 1].pos or state.goalPos

                bot:SetPos(nextSegmentPos)
                state.stuckTime = 0
            end
        else
            state.stuckStrafeDir = 0
            state.stuckBackTime = 0
        end

        if state.stuckStrafeDir ~= 0 and not targetVisible and not isPropTargetValid then
            sideSpeed = state.stuckStrafeDir * maxSpeed
        end

        if state.stuckBackTime > curTime and not targetVisible and not isPropTargetValid then
            forwardSpeed = -maxSpeed
        end
    end

    -- Check if we have a better weapon in inventory (non-melee)
    local hasGun = false
    if IsValid(state.bestWeapon) then
        local bestClass = state.bestWeapon:GetClass()
        if not MBot.Database.WEAPON_MELEE[bestClass] then
            hasGun = true
        end
    end

    -- Look for weapons if we don't have a gun
    if state.whatRole ~= 3 and #weaponCache > 0 and not hasGun and not isTargetValid and not pathToMission then
        currentlyLookingForWeapons = true
        
        local targetWep = IsValid(state.closestWep) and state.closestWep or nil

        if targetWep and targetWep ~= state.targetWep then
            state.targetWep = targetWep
            state.goalPos = weaponCachePosLookup[targetWep] or targetWep:GetPos()
            state.lookForWeaponsTime = curTime + 10
        elseif not targetWep and state.lookForWeaponsTime < curTime then
            local wep = weaponCache[math.random(#weaponCache)]
            state.targetWep = wep
            state.goalPos = weaponCachePosLookup[wep]
            state.lookForWeaponsTime = curTime + 10
        end
    end

    -- Set goalPos to a random position every 10 seconds
    if (state.randomSpotTime < curTime or reachedDest) and not isTargetValid and not currentlyLookingForWeapons and not pathToMission then
        state.goalPos = MBot.FindRandomSpot(bot)
        state.randomSpotTime = curTime + 10
    elseif isTargetValid or currentlyLookingForWeapons or pathToMission then
        state.randomSpotTime = 0
    end

    -- Target acquired, look at it and set it as goal position
    if isTargetValid then
        if targetVisible then
            lookAngle = (targetVisible - bot:GetShootPos()):Angle()

            -- Aim spread
            if state.whatRole == 1 then
                lookAngle = lookAngle + AngleRand(-5, 5)
            end

            if not state.isMelee and state.whatRole ~= 2 then
                if botPos:DistToSqr(state.curTarget:GetPos()) < 90000 then
                    forwardSpeed = -maxSpeed
                elseif botPos:DistToSqr(state.curTarget:GetPos()) < 250000 then
                    forwardSpeed = 0
                end
            end

            -- Melee movement override (strafe / circle)
            if state.whatRole ~= 1 and state.isMelee and isTargetValid and targetVisible then
                local meleeResult = MBot.GetMeleeMovement(bot, state, botPos, state.curTarget)
                if meleeResult then
                    forwardSpeed = meleeResult.forwardSpeed
                    sideSpeed = meleeResult.sideSpeed
                    moveAngle = meleeResult.moveAngle
                end
            end
        elseif state.lookAtTime > curTime then
            lookAngle = (state.lookAtPos - bot:GetShootPos()):Angle()
        end

        if state.targetVisibleTime > curTime or state.whatRole == 3 then
            local curTargetPos = state.curTarget:GetPos()

            state.goalPos = curTargetPos
            state.changeWepDelay = curTime + 1

            if not targetVisible and state.targetVisibleTime > curTime then
                lookAngle = (curTargetPos - bot:GetShootPos()):Angle()
            end
        elseif state.targetVisibleTime < curTime and reachedDest then
            state.curTarget = nil
            state.forgetTargetTime = 0
            state.targetVisibleTime = 0
            state.targetVisiblePos = nil
        end
    elseif state.lookAtTime > curTime then
        lookAngle = (state.lookAtPos - bot:GetShootPos()):Angle()
    end

    -- Attack prop target
    if not targetVisible and IsValid(state.propTarget) then
        lookAngle = (state.propTarget:WorldSpaceCenter() - bot:GetShootPos()):Angle()

        if state.isMelee then
            moveAngle = lookAngle

            if bot:GetShootPos().z > state.propTarget:GetPos().z then
                state.crouchTime = curTime + 0.1
            else
                state.crouchTime = 0
            end
        end

        state.forceAttack1Time = curTime + 1
    end

    -- Handle doors
    if state.doorCheckTime < curTime then
        local doorTrace = util.QuickTrace(bot:EyePos(), bot:GetForward() * 50, bot)
        local doorEnt = IsValid(doorTrace.Entity) and doorTrace.Entity or nil

        if doorEnt then
            local doorEntClass = doorEnt:GetClass()

            if doorEntClass == "prop_door_rotating" then
                doorEnt:Fire("OpenAwayFrom", bot, 0)
            elseif doorEntClass == "func_door" then
                doorEnt:Fire("Open")
            end
        end

        state.doorCheckTime = curTime + 1
    end

    -- Handle ladders
    if state.onLadder and pathHasLadder then
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

    local AimLerp = 0.12 -- 0.015 * 8

    -- Finally, set the bot's move angle, view angle, and movement speeds
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

            -- CHEAT: Infinite ammo
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

            local state = bot.BotStates
            if not state then continue end

            local botRole = state.whatRole

            if botRole == 3 then
                local closestEnemy = alienEnemyCache[bot]
                if IsValid(closestEnemy) and closestEnemy:Alive() then
                    state.pendingTarget = closestEnemy
                end
                
                ShouldYield()
            else
                targetCandidates = {}
                targetDistLookup = {}

                local botPos = bot:GetPos()

                -- Get all target candidates within 1500 units of the bot
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
                    elseif botRole == 2 then
                        if plyRole == 1 then
                            isHostile = true
                        end
                    elseif botRole == 3 then
                        if plyRole == 1 then
                            isHostile = true
                        end
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
                        state.pendingTarget = target
                        break
                    end

                    ShouldYield()
                end
            end

            ShouldYield()
        end

        coroutine.yield()
    end
end

local function UpdateAlienXray()
    while true do
        for _, bot in player.Iterator() do
            if not IsValid(bot) then continue end
            if not bot:IsBot() then continue end
            if not bot:Alive() then continue end

            local state = bot.BotStates
            if not state then continue end

            local botRole = state.whatRole
            if botRole == 1 then continue end

            local botPos = bot:GetPos()
            local closestEnemy = nil
            local closestDist = math.huge

            for _, ply in player.Iterator() do
                if not IsValid(ply) then continue end
                if not ply:Alive() then continue end
                if ply == bot then continue end

                local plyRole = ply.GetRole and ply:GetRole() or 1
                if plyRole == 1 then
                    local dist = botPos:DistToSqr(ply:GetPos())
                    if dist < closestDist then
                        closestDist = dist
                        closestEnemy = ply
                    end
                end

                coroutine.yield()
            end

            alienEnemyCache[bot] = closestEnemy
            coroutine.yield()
        end

        coroutine.yield()
    end
end

local function UpdateWeaponCache()
    while true do
        local newCache = {}
        local newPosLookup = {}

        for k, categoryTable in pairs(MBot.Database) do
            if k == "WEAPON_MELEE" or k == "WEAPON_MISC" then continue end
            for classname, _ in pairs(categoryTable) do
                local foundEnts = ents.FindByClass(classname)
                for i = 1, #foundEnts do
                    local ent = foundEnts[i]
                    if IsValid(ent) then
                        newCache[#newCache + 1] = ent
                        newPosLookup[ent] = ent:GetPos()
                    end
                end

                coroutine.yield()
            end

            coroutine.yield()
        end

        weaponCache = newCache
        weaponCachePosLookup = newPosLookup

        coroutine.yield()
    end
end

local function UpdateClosestWep()
    while true do
        for _, bot in player.Iterator() do
            if not bot.BotStates then continue end
            if not bot:Alive() then continue end

            local botPos = bot:GetPos()
            local closestDist = math.huge
            local closestWep = nil

            for i = 1, #weaponCache do
                local wep = weaponCache[i]
                local wepPos = weaponCachePosLookup[wep]
                if IsValid(wep) and wepPos and not IsValid(wep:GetOwner()) then
                    local dist = botPos:DistToSqr(wepPos)
                    if dist < closestDist and bot:VisibleVec(wepPos) then
                        closestDist = dist
                        closestWep = wep
                    end
                end
            end

            bot.BotStates.closestWep = closestWep
            bot.BotStates.closestWepDist = closestDist

            coroutine.yield()
        end

        coroutine.yield()
    end
end

local function UpdateFriendlies()
    while true do
        local counts = {}

        for _, ply in player.Iterator() do
            if not IsValid(ply) then continue end
            if not ply:Alive() then continue end

            local role = ply.GetRole and ply:GetRole() or 1

            if role == 1 then
                local myPos = ply:GetPos()
                local count = 0
                
                for _, other in player.Iterator() do
                    if ply == other then continue end
                    if not IsValid(other) or not other:Alive() then continue end
                    
                    local otherRole = other.GetRole and other:GetRole() or 1
                    
                    if role == otherRole then
                        if myPos:DistToSqr(other:GetPos()) <= 250000 or ply:VisibleVec(other:EyePos()) then
                            count = count + 1
                        end
                    end

                    ShouldYield()
                end
                counts[ply] = count
            end

            ShouldYield()
        end

        friendliesCounts = counts
        coroutine.yield()
    end
end

local function UpdateBreakables()
    while true do
        for _, bot in player.Iterator() do
            if not IsValid(bot) then continue end
            if not bot:IsBot() then continue end
            if not bot:Alive() then continue end

            local state = bot.BotStates
            if not state then continue end

            local botPos = bot:GetPos()
            local closestEnt = nil
            local closestDist = math.huge

            local nearby = ents.FindInSphere(botPos, 100)
            for i = 1, #nearby do
                local ent = nearby[i]
                if not IsValid(ent) then continue end

                local class = ent:GetClass()
                local isBreakable = false

                if string.sub(class, 1, 5) == "prop_" then
                    isBreakable = true
                end

                if class == "func_breakable" then
                    isBreakable = true
                end

                if not isBreakable then continue end

                if ent:Health() <= 0 or ent:Health() > 1000 then continue end

                local dist = botPos:DistToSqr(ent:GetPos())
                if dist < closestDist and MBot.IsTargetVisible(bot, ent) then
                    closestDist = dist
                    closestEnt = ent
                end

                ShouldYield()
            end

            state.pendingProp = closestEnt

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
local weaponCacheCoroutine = coroutine.create(UpdateWeaponCache)
local closestWeaponCoroutine = coroutine.create(UpdateClosestWep)
local friendliesCoroutine = coroutine.create(UpdateFriendlies)
local breakablesCoroutine = coroutine.create(UpdateBreakables)
local alienXrayCoroutine = coroutine.create(UpdateAlienXray)

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

hook.Add("PlayerHurt", "MBot_PlayerHurt", function(bot, attacker, healthRemaining, damageTaken)
    if not IsValid(bot) or not bot:IsBot() then return end
    if not bot:Alive() then return end

    PlayerHurt(bot, attacker)
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

    if coroutine.status(closestWeaponCoroutine) == "suspended" then
        coroutine.resume(closestWeaponCoroutine)
    end

    if coroutine.status(friendliesCoroutine) == "suspended" then
        coroutine.resume(friendliesCoroutine)
    end

    if coroutine.status(breakablesCoroutine) == "suspended" then
        coroutine.resume(breakablesCoroutine)
    end

    if coroutine.status(alienXrayCoroutine) == "suspended" then
        coroutine.resume(alienXrayCoroutine)
    end
end)