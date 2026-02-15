--[[----------------------------------------
    Bot States
----------------------------------------]]--

MBot.DefaultBotStates = {
    -- Pathfinding
    goalPos = nil,
    pathSegment = 2,

    -- Stuck management
    lastPos = nil,
    nextStuckCheck = 0,
    stuckTime = 0,
    stuckStrafeDir = 0,
    stuckStrafeTime = 0,
    stuckBackTime = 0,

    -- Target
    curTarget = nil,
    forgetTargetTime = 0,
    targetVisibleTime = 0,
    targetVisiblePos = nil,

    -- Combat
    attack1Delay = 0,

    -- Movement
    jumpTime = 0,
    crouchTime = 0,

    -- Movement (Ladder)
    onLadder = false,
    prevOnLadder = false,
    timeOnLadder = 0,

    -- Game mode
    whatRole = 1, -- ROLE_HUMAN (1), ROLE_BROOD (2), ROLE_SWARM (3)

    -- Set by coroutines
    pendingTarget = nil,
    pendingProp = nil,

    -- Other timing stuff
    randomSpotTime = 0
}