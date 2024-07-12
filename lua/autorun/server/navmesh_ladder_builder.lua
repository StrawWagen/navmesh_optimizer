
local noLadderMsg = "Map has no func_useableladders."
local noCallerMsg = "This command needs to be run by a player!"
local ladderedThisSession = ladderedThisSession or {}

local function roundedPosOf( ent )
    local pos = ent:GetPos()
    local roundedPos = Vector( 0, 0, 0 )
    roundedPos.x = math.Round( pos.x )
    roundedPos.y = math.Round( pos.y )
    roundedPos.z = math.Round( pos.z )

    return roundedPos

end

local function getLadderBotTop( ladder )
    local keys = ladder:GetKeyValues()
    local point0 = ladder:LocalToWorld( keys["point0"] )
    local point1 = ladder:LocalToWorld( keys["point1"] )

    local bottom = point0
    local top = point1
    -- find real top/bottom
    if bottom.z > top.z then
        bottom = point1
        top = point0

    end
    return bottom, top
end

local function getNearestLadder( pos )
    local ladders = ents.FindByClass( "func_useableladder" )
    local nearestDistSqr = math.huge

    local point0
    local point1
    local nearest
    for _, curr in ipairs( ladders ) do
        local keysCurr = curr:GetKeyValues()
        local point0Curr = curr:LocalToWorld( keysCurr["point0"] )
        local point1Curr = curr:LocalToWorld( keysCurr["point1"] )

        local currDist0 = point0Curr:DistToSqr( pos )
        local currDist1 = point1Curr:DistToSqr( pos )
        local bestDist = currDist0
        if currDist1 < bestDist then
            bestDist = currDist1

        end
        if bestDist < nearestDistSqr then
            nearest = curr
            nearestDistSqr = bestDist
            point0 = point0Curr
            point1 = point1Curr

        end
    end
    if not IsValid( nearest ) then return end

    local bottom = point0
    local top = point1
    -- find real top/bottom
    if bottom.z > top.z then
        bottom = point1
        top = point0

    end

    return bottom, top, nearest

end

local function ladderDir( bottom, top, ply )
    local plysForward = ply:EyeAngles()
    plysForward.p = 0
    plysForward.r = 0
    plysForward:SnapTo( "y", 90 )
    plysForward.y = plysForward.y + 90

    local laddersUp = bottom - top
    laddersUp:Normalize()

    local dir = plysForward:Forward():Cross( laddersUp )

    return dir

end


local offsetFromCenter = 15
local ladderWidth = 25
local ladderHull = Vector( ladderWidth / 2, ladderWidth / 2, ladderWidth / 2 )
local ang_zero = Angle( 0, 0, 0 )


local function patchLadderCommand( caller )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if not IsValid( caller ) then NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( noCallerMsg ) return end
    local pos = caller:GetEyeTrace().HitPos
    local bottom, top, ladder = getNearestLadder( pos )

    if not IsValid( ladder ) then NAVOPTIMIZER_tbl.printCenterAlias( noLadderMsg, caller ) return end

    local dir = ladderDir( bottom, top, caller )

    local tolerance = bottom:Distance( top )
    tolerance = math.Clamp( tolerance, 25, 100 )

    navmesh.CreateNavLadder( top + -dir * offsetFromCenter, bottom + -dir * offsetFromCenter, ladderWidth, dir, tolerance )
    ladderedThisSession[tostring( roundedPosOf( ladder ) )] = true

end
concommand.Add( "navmesh_ladderusable_build", patchLadderCommand, nil, "Create navladders on top of func_useableladder.", FCVAR_NONE )


local manualBTimer = "navmesh_ladderusable_manualbuild_"

local function patchLadderCommandManual( caller, doSnap )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if not IsValid( caller ) then NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( noCallerMsg ) return end

    local timerNameInt = manualBTimer .. caller:GetCreationID()
    local eyetraceHitNpcClips = util.GetPlayerTrace( caller, caller:GetAimVector() )
    eyetraceHitNpcClips.mask = MASK_NPCSOLID

    local pos = util.TraceLine( eyetraceHitNpcClips ).HitPos
    local currPatchin = caller.navopti_manualpatch_ladder
    local point0 = caller.navopti_manualpatch_point0

    -- place bottom
    if not point0 then
        local _, _, ladder = getNearestLadder( pos )
        if not IsValid( ladder ) and doSnap then NAVOPTIMIZER_tbl.printCenterAlias( noLadderMsg, caller ) return end

        caller.navopti_manualpatch_ladder = ladder
        caller.navopti_manualpatch_point0 = pos

    -- place top
    else
        local point1 = Vector( point0.x, point0.y, pos.z )
        if doSnap then
            local bottom, top = getLadderBotTop( currPatchin )
            local laddersUp = ( top - bottom ):GetNormalized()
            top = top + laddersUp * 3200
            bottom = bottom + -laddersUp * 3200
            _, point0 = util.DistanceToLine( bottom, top, caller.navopti_manualpatch_point0 )
            _, point1 = util.DistanceToLine( bottom, top, pos )

        end

        local patchBottom = point0
        local patchTop = point1

        if patchBottom.z > patchTop.z then
            patchBottom = point1
            patchTop = point0

        end
        local dir = ladderDir( patchBottom, patchTop, caller )

        local ladderTop = patchTop + -dir * offsetFromCenter
        local ladderBottom = patchBottom + -dir * offsetFromCenter

        --debugoverlay.Cross( ladderTop, 10, 5, color_white, true )
        --debugoverlay.Cross( ladderBottom, 10, 5, color_white, true )

        navmesh.CreateNavLadder( ladderTop, ladderBottom, ladderWidth, dir, 25 )
        if doSnap then
            ladderedThisSession[tostring( roundedPosOf( currPatchin ) )] = true

        end

        caller.navopti_manualpatch_ladder = nil
        caller.navopti_manualpatch_point0 = nil

    end

    -- display
    timer.Create( timerNameInt, 0.1, 0, function()
        if not IsValid( caller ) then timer.Remove( timerNameInt ) return end
        local point0Timer = caller.navopti_manualpatch_point0
        if not point0Timer then timer.Remove( timerNameInt ) return end
        local currPatchinTimer = caller.navopti_manualpatch_ladder
        if doSnap and not IsValid( currPatchinTimer ) then timer.Remove( timerNameInt ) return end

        local eyetraceHitNpcClipsTimer = util.GetPlayerTrace( caller, caller:GetAimVector() )
        eyetraceHitNpcClipsTimer.mask = MASK_NPCSOLID

        local posTimer = util.TraceLine( eyetraceHitNpcClipsTimer ).HitPos

        local point1 = Vector( point0Timer.x, point0Timer.y, posTimer.z )
        if doSnap then
            local bottom, top = getLadderBotTop( currPatchinTimer )
            local laddersUp = ( top - bottom ):GetNormalized()
            top = top + laddersUp * 3200
            bottom = bottom + -laddersUp * 3200
            _, point0Timer = util.DistanceToLine( bottom, top, caller.navopti_manualpatch_point0 )
            _, point1 = util.DistanceToLine( bottom, top, posTimer )

        end

        local patchBottom = point0Timer
        local patchTop = point1

        if patchBottom.z > patchTop.z then
            patchBottom = point1
            patchTop = point0Timer

        end

        debugoverlay.SweptBox( patchBottom, patchTop, -ladderHull, ladderHull, ang_zero, 0.11 )

    end )
end
concommand.Add( "navmesh_ladder_buildmanual", function( caller ) patchLadderCommandManual( caller ) end, nil, "Create navladders, allows for manual placement of top/bottom", FCVAR_NONE )

concommand.Add( "navmesh_ladderusable_buildmanual_snap", function( caller ) patchLadderCommandManual( caller, true ) end, nil, "Create navladders on top of func_useableladder, allows for manual placement of top/bottom", FCVAR_NONE )


local isShowing
local timerName = "navmesh_ladderusable_show_func_useableladder"

local redDull = Color( 255, 0, 0, 150 )
local green = Color( 0, 255, 0 )

local function toggleShowLadders()
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if not isShowing then
        local laddersCheck = ents.FindByClass( "func_useableladder" )
        if #laddersCheck <= 0 then
            NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( noLadderMsg )
            return

        end
        isShowing = true
        timer.Create( timerName, 1, 0, function()
            local ladders = ents.FindByClass( "func_useableladder" )
            for _, curr in ipairs( ladders ) do
                local keys = curr:GetKeyValues()
                local point0 = curr:LocalToWorld( keys["point0"] )
                local point1 = curr:LocalToWorld( keys["point1"] )

                local color = green
                local sizeMul = 4

                if ladderedThisSession[tostring( roundedPosOf( curr ) )] then
                    color = redDull
                    sizeMul = 0.5

                end

                debugoverlay.Cross( point0, 10 * sizeMul, 1.1, color, true )
                debugoverlay.Line( point0, point1, 1.1, color, true )
                debugoverlay.Cross( point1, 10 * sizeMul, 1.1, color, true )

            end
        end )
        local msg = "Highlighting all func_useableladder on the map.\nRun developer 1 to see ladders."
        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( msg )

    else
        isShowing = nil
        timer.Remove( timerName )
        local msg = "Highlighting stopped."
        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( msg )

    end
end

concommand.Add( "navmesh_ladderusable_showall", toggleShowLadders, nil, "Show all func_useableladders on the map, Needs developer 1", FCVAR_NONE )

local function tpToLadder( caller )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if not IsValid( caller ) then NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( noCallerMsg ) return end
    if caller:GetMoveType() ~= MOVETYPE_NOCLIP then NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "You have to be in noclip to run this command." ) end

    local ladders = ents.FindByClass( "func_useableladder" )
    for _, curr in ipairs( ladders ) do
        local posOf = roundedPosOf( curr )
        if not ladderedThisSession[tostring( posOf )] then
            caller:SetPos( posOf )
            return

        end
    end
    local msg = "No more ladders."
    NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( msg )
end

concommand.Add( "navmesh_ladderusable_tp", tpToLadder, nil, "Teleports the caller to an un-navmeshed, usableladder", FCVAR_NONE )
