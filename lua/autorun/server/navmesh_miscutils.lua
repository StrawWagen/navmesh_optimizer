
local IsValid = IsValid

local math_min = math.min
local math_max = math.max

NAVOPTIMIZER_tbl = NAVOPTIMIZER_tbl or {}

function NAVOPTIMIZER_tbl.AreasHaveAnyOverlap( area1, area2 ) -- i love chatgpt functions
    -- Get corners of both areas
    local area1Corner1 = area1:GetCorner( 0 )
    local area1Corner2 = area1:GetCorner( 2 )
    local area2Corner1 = area2:GetCorner( 0 )
    local area2Corner2 = area2:GetCorner( 2 )

    -- Determine bounds of the areas
    local area1MinX = math_min( area1Corner1.x, area1Corner2.x )
    local area1MaxX = math_max( area1Corner1.x, area1Corner2.x )
    local area1MinY = math_min( area1Corner1.y, area1Corner2.y )
    local area1MaxY = math_max( area1Corner1.y, area1Corner2.y )

    local area2MinX = math_min( area2Corner1.x, area2Corner2.x )
    local area2MaxX = math_max( area2Corner1.x, area2Corner2.x )
    local area2MinY = math_min( area2Corner1.y, area2Corner2.y )
    local area2MaxY = math_max( area2Corner1.y, area2Corner2.y )

    -- Check for overlap on X or Y axis
    local xOverlap = ( area1MinX <= area2MaxX and area1MaxX >= area2MinX )
    local yOverlap = ( area1MinY <= area2MaxY and area1MaxY >= area2MinY )

    return xOverlap or yOverlap

end

-- find small areas that have connections on all 4 sides, that are on displacements
local function handlePotentialDisplacementArea( area )
    if not IsValid( area ) then return end

    if area:HasAttributes( NAV_MESH_CROUCH ) then return end
    if area:HasAttributes( NAV_MESH_STAIRS ) then return end
    if area:HasAttributes( NAV_MESH_NO_MERGE ) then return end
    if area:HasAttributes( NAV_MESH_TRANSIENT ) then return end
    if area:HasAttributes( NAV_MESH_OBSTACLE_TOP ) then return end

    local perfectlyFlat = true
    local lastZ
    for ind = 0, 3 do
        local currZ = area:GetCorner( ind ).z
        if currZ ~= lastZ then perfectlyFlat = false break end
        lastZ = currZ

    end

    -- even if it is on a displacement, perfectly flat displacements arent gonna make small areas
    if perfectlyFlat then return end

    local biggestLength = math.max( area:GetSizeX(), area:GetSizeY() )

    local bigLength = 55
    -- be more aggressive if area is a trash underwater one
    if area:IsUnderwater() then
        bigLength = 140

    end

    if biggestLength > bigLength then return end

    local adjAreas = area:GetAdjacentAreas()
    if #adjAreas <= 3 then return end

    if not NAVOPTIMIZER_tbl.areaIsEntirelyOverDisplacements( area ) then return end

    area:Remove()

    return true

end

local navmeshRemoveSmallAreasOnDisplacements = nil
local navmeshRemoveSmallAreasOnDisplacementsCor = nil

local function thinkHookDisplacementTrim()
    if not navmeshRemoveSmallAreasOnDisplacements then hook.Remove( "Tick", "navmeshRemoveSmallAreasOnDisplacements" ) return end
    if not navmeshRemoveSmallAreasOnDisplacementsCor then -- create coroutine
        local nextPrint = SysTime() + 5
        local lastPrintedCount = 0
        local theFunc = function()
            local removedCount = 0
            local allAreas = navmesh.GetAllNavAreas()
            local allAreaCount = #allAreas
            for progress, area in ipairs( allAreas ) do
                coroutine.yield()
                if nextPrint < SysTime() and lastPrintedCount ~= removedCount then
                    nextPrint = SysTime() + 5
                    lastPrintedCount = removedCount
                    NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Removed " .. removedCount .. "  areas so far.." )

                end

                NAVOPTIMIZER_tbl.printCenterAlias( "AREA " .. progress .. " / " .. allAreaCount .. "\n" .. removedCount .. " \"Redundant\" displacement areas removed so far..." )
                local removed = handlePotentialDisplacementArea( area )

                if removed then
                    removedCount = removedCount + 1

                end
            end
            NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "SUCCESS!\nRemoved " .. removedCount .. " small areas, with more than 3 neighbors, on displacements." )
            coroutine.yield( "done" )

        end

        navmeshRemoveSmallAreasOnDisplacementsCor = coroutine.create( theFunc )

    elseif navmeshRemoveSmallAreasOnDisplacementsCor then -- run
        local oldTime = SysTime()
        while math.abs( oldTime - SysTime() ) < 0.001 do
            local noErrors, result = coroutine.resume( navmeshRemoveSmallAreasOnDisplacementsCor )
            if noErrors == false then
                ErrorNoHaltWithStack( result )
                navmeshRemoveSmallAreasOnDisplacements = nil
                navmeshRemoveSmallAreasOnDisplacementsCor = nil
                NAVOPTIMIZER_tbl.isBusy = false
                break

            elseif result == "done" then
                navmeshRemoveSmallAreasOnDisplacements = nil
                navmeshRemoveSmallAreasOnDisplacementsCor = nil
                NAVOPTIMIZER_tbl.isBusy = false
                break

            end
        end
    end
end

local function navmeshStartDisplacementTrim( caller )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if NAVOPTIMIZER_tbl.isBusy then return end --don't interrupt!
    callerPersist = caller
    NAVOPTIMIZER_tbl.enableNavEdit( callerPersist )

    NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Removing small areas with more than 3 neighbors on displacements!" )
    NAVOPTIMIZER_tbl.isBusy = true
    navmeshRemoveSmallAreasOnDisplacements = true

    hook.Add( "Tick", "navmeshRemoveSmallAreasOnDisplacements", thinkHookDisplacementTrim )

end


local removedAreaSlowDown = 0

local function handlePotentialDeepUnderwaterArea( area, depth )
    if not IsValid( area ) then return end

    if not area:IsUnderwater() then return end

    local offsetVec = Vector( 0, 0, depth )
    local idealPos = area:GetCenter() + offsetVec
    local pos = area:GetClosestPointOnArea( idealPos )
    local wasDry
    for ind = 1, depth do
        offsetVec.z = ind
        if bit.band( util.PointContents( pos + offsetVec ), CONTENTS_WATER ) <= 0 then
            wasDry = true
            break

        end
    end

    if wasDry then return end

    area:Remove()
    removedAreaSlowDown = 10

    return true

end

local depth = nil
local navmeshRemoveAreasDeepUnderwater = nil
local navmeshRemoveAreasDeepUnderwaterCor = nil

local function thinkHookDeepWaterTrim()
    if not navmeshRemoveAreasDeepUnderwater then hook.Remove( "Tick", "navmeshRemoveAreasDeepUnderwater" ) return end
    if not navmeshRemoveAreasDeepUnderwaterCor then -- create coroutine
        local theFunc = function()
            local removedCount = 0
            local allAreas = navmesh.GetAllNavAreas()
            local allAreaCount = #allAreas
            for progress, area in ipairs( allAreas ) do
                coroutine.yield()

                NAVOPTIMIZER_tbl.printCenterAlias( "AREA " .. progress .. " / " .. allAreaCount .. "\n" .. "Removed " .. removedCount .. " areas in water " .. depth .. " units deep..." )
                local removed = handlePotentialDeepUnderwaterArea( area, depth )

                if removed then
                    removedCount = removedCount + 1

                end
            end
            NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "SUCCESS!\nRemoved " .. removedCount .. " areas in water " .. depth .. " units deep." )
            coroutine.yield( "done" )

        end

        navmeshRemoveAreasDeepUnderwaterCor = coroutine.create( theFunc )

    elseif navmeshRemoveAreasDeepUnderwaterCor then -- run
        local oldTime = SysTime()
        local check = 0.005
        if removedAreaSlowDown > 0 then -- strange lag from outside coroutine when area is removed
            check = 0.0001
            removedAreaSlowDown = removedAreaSlowDown + -1

        end
        while math.abs( oldTime - SysTime() ) < check do
            local noErrors, result = coroutine.resume( navmeshRemoveAreasDeepUnderwaterCor )
            if noErrors == false then
                ErrorNoHaltWithStack( result )
                navmeshRemoveAreasDeepUnderwater = nil
                navmeshRemoveAreasDeepUnderwaterCor = nil
                NAVOPTIMIZER_tbl.isBusy = false
                break

            elseif result == "done" then
                navmeshRemoveAreasDeepUnderwater = nil
                navmeshRemoveAreasDeepUnderwaterCor = nil
                NAVOPTIMIZER_tbl.isBusy = false
                break

            end
        end
    end
end

local function beginDeepWaterTrim( caller, _, depthOverride )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if NAVOPTIMIZER_tbl.isBusy then return end --don't interrupt!
    callerPersist = caller
    NAVOPTIMIZER_tbl.enableNavEdit( callerPersist )

    local overrideAsNum = tonumber( depthOverride[1] )

    if not overrideAsNum or ( overrideAsNum and overrideAsNum <= 0 ) then
        depth = 350

    else
        depth = overrideAsNum

    end

    NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Removing areas in water more than " .. depth .. " units deep." )
    NAVOPTIMIZER_tbl.isBusy = true
    navmeshRemoveAreasDeepUnderwater = true

    hook.Add( "Tick", "navmeshRemoveAreasDeepUnderwater", thinkHookDeepWaterTrim )

end

local offset = Vector( 0, 0, 20 )
local function posIsBroke( pos )
    if not util.IsInWorld( pos ) then
        return true

    elseif NAVOPTIMIZER_tbl.getFloorTrSolid( pos ).HitPos:Distance( pos ) > 100 then
        return true

    end
end

NAVOPTIMIZER_tbl.isCorruptCache = NAVOPTIMIZER_tbl.isCorruptCache or nil
local corruptCacheCount = nil

function getCorruptAreas( areas )
    areas = areas or navmesh.GetAllNavAreas()

    local isCorruptCache = NAVOPTIMIZER_tbl.isCorruptCache
    local goodCache = isCorruptCache and corruptCacheCount and corruptCacheCount == navmesh.GetNavAreaCount()
    if not goodCache then
        corruptCacheCount = navmesh.GetNavAreaCount()
        NAVOPTIMIZER_tbl.isCorruptCache = {}
        isCorruptCache = NAVOPTIMIZER_tbl.isCorruptCache

    end

    local areaCount = #areas
    local corruptedAreas = {}
    local brokenCount = 0
    local normalCount = 0

    for _, area in ipairs( areas ) do
        if area:HasAttributes( NAV_MESH_TRANSIENT ) then continue end

        if isCorruptCache then
            local cached = isCorruptCache[area]
            if cached == true then
                table.insert( corruptedAreas, area )
                continue

            elseif cached == false then
                continue

            end
        end

        local smallArea = math.max( area:GetSizeX(), area:GetSizeY() ) < 35
        local cornersToBeBroken = 2

        local brokenCorners = 0
        if smallArea or area:IsBlocked() then
            cornersToBeBroken = 1
            if posIsBroke( area:GetCenter() + offset ) then
                brokenCorners = brokenCorners + 2

            end
        else
            if not util.IsInWorld( area:GetCenter() + offset ) then
                cornersToBeBroken = 1

            end
            for cornerId = 0, 3 do
                local offsettedCorner = area:GetCorner( cornerId ) + offset
                if posIsBroke( offsettedCorner ) then
                    brokenCorners = brokenCorners + 1

                end
            end
        end
        if brokenCorners > cornersToBeBroken then
            brokenCount = brokenCount + 1
            table.insert( corruptedAreas, area )
            isCorruptCache[area] = true

        else
            normalCount = normalCount + 1
            isCorruptCache[area] = false

        end

    end

    return corruptedAreas, brokenCount, areaCount

end

function navmeshIsCorrupted()
    local corruptedAreas, brokenCount, areaCount = getCorruptAreas()

    local brokenRatio = brokenCount / areaCount
    local likelyCorrupt = brokenRatio > 0.15

    return likelyCorrupt, brokenRatio, corruptedAreas

end

local function corruptedCommand()
    if navmesh.GetNavAreaCount() <= 0 then
        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "There is no navmesh..." )
        return

    end
    local corrupt, ratio = navmeshIsCorrupted()
    local ratioAsPercent = ratio * 100
    ratioAsPercent = math.Round( ratioAsPercent, 2 )

    if corrupt then
        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "CORRUPT!\n" .. ratioAsPercent .. "% of areas are either outside the world, or very high off the ground." )

    elseif ratioAsPercent <= 0 then
        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "NOT corrupt.\nAll areas are inside the world, on the ground" )

    else
        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Navmesh is MILDLY corrupt.\n" .. ratioAsPercent .. "% of areas are either outside the world, or very high off the ground." )

    end
end


function navmeshDeleteAreas( areasOverride, dontRemoveLadders, caller )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if NAVOPTIMIZER_tbl.isBusy then return end

    NAVOPTIMIZER_tbl.isBusy = true
    callerPersist = caller
    NAVOPTIMIZER_tbl.enableNavEdit( callerPersist )

    local removedAreas = 0
    local done = nil

    local blockSize = 500
    local areas = areasOverride or navmesh.GetAllNavAreas()
    local areaCount = #areas

    -- if less than 10k areas
    if areaCount < blockSize * 20 then
        for _, area in ipairs( areas ) do
            area:Remove()
            removedAreas = removedAreas + 1

        end
        done = true

    -- otherwise blocks
    else
        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "TOO MANY AREAS! ( " .. areaCount .. " areas! )\nRemoving in blocks!" )
        local blocks = math.ceil( areaCount / blockSize )
        local timeMul = 0.25

        for currBlock = 0, blocks do
            local time = currBlock * timeMul
            timer.Simple( time, function()
                local blockRemoved = 0
                local blockStart = currBlock * blockSize
                local blockEnd = ( currBlock + 1 ) * blockSize

                for id = blockStart, blockEnd do
                    local area = areas[id]

                    if IsValid( area ) then
                        area:Remove()
                        removedAreas = removedAreas + 1
                        blockRemoved = blockRemoved + 1

                    end
                end
                NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Removed a block of " .. blockRemoved .. " areas." )
            end )
        end
        timer.Simple( ( blocks * timeMul ) + timeMul, function()
            NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Finishing up..." )
            for _, area in ipairs( navmesh.GetAllNavAreas() ) do
                area:Remove()
                removedAreas = removedAreas + 1

            end
            done = true
        end )
    end

    local removedLadders = 0

    if not dontRemoveLadders then
        for id = 1, 1000 do
            local ladder = navmesh.GetNavLadderByID( id )
            if IsValid( ladder ) then
                ladder:Remove()
                removedLadders = removedLadders + removedLadders

            end
        end
    end

    timer.Create( "navmesh_remove_allareas", 0.5, 0, function()
        if not done then return end
        timer.Remove( "navmesh_remove_allareas" )
        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "DONE!" )

        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Removed " .. removedAreas .. " areas" )

        if not dontRemoveLadders then
            NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Removed " .. removedLadders .. " navladders" )

        end

        hook.Run( "navoptimizer_done_removingallareas" )
        NAVOPTIMIZER_tbl.isBusy = false
        NAVOPTIMIZER_tbl.nag( callerPersist )

    end )
end

local warned

local function navmeshDeleteAllAreasCmd( caller )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if NAVOPTIMIZER_tbl.isBusy then return end
    if not warned then -- start removing corrupt areas NOW!
        warned = true
        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Are you sure you want to remove ALL navareas?\nRun this command again now to proceed." )
        timer.Simple( 5, function()
            warned = nil

        end )
        return

    end
    navmeshDeleteAreas( nil, nil, caller )

end


local skyboxAreasLastCount = -1
local cachedAreasInSkybox = {}
local cachedAreasInSkyboxIndex = {}
local skyboxLastReturnReason = "n/a"

local function navareasInSkybox()
    local currCount = navmesh.GetNavAreaCount()
    if currCount == skyboxAreasLastCount and #cachedAreasInSkybox == currCount then
        return cachedAreasInSkybox, cachedAreasInSkyboxIndex, skyboxLastReturnReason

    end

    skyboxAreasLastCount = currCount

    local queue = {}
    local skyCameras = ents.FindByClass( "sky_camera" )
    if #skyCameras <= 0 then
        skyboxLastReturnReason = "no sky_cameras"
        return cachedAreasInSkybox, cachedAreasInSkyboxIndex, skyboxLastReturnReason

    end

    for _, camera in ipairs( skyCameras ) do
        local inSkyboxArea = navmesh.GetNearestNavArea( camera:GetPos(), nil, 2000, true, nil )
        if IsValid( inSkyboxArea ) then
            table.insert( queue, inSkyboxArea )

        end
    end

    if #queue <= 0 then
        skyboxLastReturnReason = "couldn't find navareas in the skybox"
        return cachedAreasInSkybox, cachedAreasInSkyboxIndex, skyboxLastReturnReason

    end

    local _, spawnpointAreas = NAVOPTIMIZER_tbl.AreasUnderCommonSpawnTypes()

    local areasInSkybox = {}
    local areasInSkyboxIndex = {}

    local visited = {}

    -- flood fill the skybox, find every connecting area
    while #queue > 0 do
        local currentNavArea = table.remove( queue, 1 )
        if not IsValid( currentNavArea ) then continue end

        if spawnpointAreas[ currentNavArea ] then -- sanity check
            skyboxLastReturnReason = "navareas in the skybox somehow connect back to player spawnpoints, please fix this!"
            return cachedAreasInSkybox, cachedAreasInSkyboxIndex, skyboxLastReturnReason

        end

        table.insert( areasInSkybox, currentNavArea )
        areasInSkyboxIndex[ currentNavArea ] = true

        for _, connectedNavArea in ipairs( currentNavArea:GetAdjacentAreas() ) do
            if visited[connectedNavArea] then continue end

            local connectedBothWays = connectedNavArea:IsConnected( currentNavArea ) and currentNavArea:IsConnected( connectedNavArea )
            if not connectedBothWays then continue end

            -- mark the connected navarea as visited
            visited[connectedNavArea] = true -- mark as visited after we check connections, so it doesnt break
            -- add the connected navarea to the queue to be processed
            table.insert( queue, connectedNavArea )

        end
    end

    cachedAreasInSkybox = areasInSkybox
    cachedAreasInSkyboxIndex = areasInSkyboxIndex

    return areasInSkybox, areasInSkyboxIndex, "all is well"

end

local notSkyboxAreasLastCount = -1
local cachedAreasNotInSkybox = {}
local cachedAreasNotInSkyboxIndex = {}

function navareasNotInSkybox()
    local currCount = navmesh.GetNavAreaCount()
    if currCount == notSkyboxAreasLastCount then
        return cachedAreasNotInSkybox, cachedAreasNotInSkyboxIndex

    end
    notSkyboxAreasLastCount = currCount

    local areas = navmesh.GetAllNavAreas()
    local _, areasInSkyboxIndex = navareasInSkybox()

    local notInTheSkybox = {}
    local notInTheSkyboxIndex = {}

    for _, area in ipairs( areas ) do
        if not areasInSkyboxIndex[ area ] then
            table.insert( notInTheSkybox, area )
            notInTheSkyboxIndex[ area ] = true

        end
    end

    cachedAreasNotInSkybox = notInTheSkybox
    cachedAreasNotInSkyboxIndex = notInTheSkyboxIndex

    return notInTheSkybox, notInTheSkyboxIndex

end


local function navmeshDeleteSkyboxAreasCmd( caller )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if NAVOPTIMIZER_tbl.isBusy then return end

    local areasInSkybox, _, returnReason = navareasInSkybox()
    if #areasInSkybox <= 0 then
        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Something went wrong!\nReason: " .. returnReason )
        return

    end
    NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Removing " .. #areasInSkybox .. " navareas from this map's skybox" )
    navmeshDeleteAreas( areasInSkybox, true, caller )

end

local transparentWhite = Color( 255, 255, 255, 10 )
local red = Color( 255, 0, 0 )
local deleteHighlighOffset = Vector( 0, 0, 15 )

local function navmeshDeleteCorruptAreasInRadiusCmd( caller, _, args )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if NAVOPTIMIZER_tbl.isBusy then return end

    local corruptAreas

    local rad = tonumber( args[1] ) or 2000
    if IsValid( caller ) and rad and rad >= 1 then
        local center = caller:GetPos()
        local maxs = Vector( rad, rad, rad ) * 2
        local initialInRadius = navmesh.FindInBox( center + maxs, center + -maxs )

        debugoverlay.Sphere( center, rad, 10, transparentWhite, true )

        local inRadius = {}
        local radSqr = rad^2
        for _, area in ipairs( initialInRadius ) do
            if area:GetCenter():DistToSqr( center ) < radSqr then
                table.insert( inRadius, area )

            end
        end

        corruptAreas = getCorruptAreas( inRadius )

        if #corruptAreas <= 0 then
            NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "No corrupt areas in a radius of " .. rad .. " around the caller. 0 radius for mapwide." )
            return

        end

        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Removing " .. #corruptAreas .. " corrupt navareas closer than " .. rad .. "u to the caller." )

    else
        corruptAreas = getCorruptAreas()

        if #corruptAreas <= 0 then
            NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "No corrupt areas!" )
            return

        end
        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Removing " .. #corruptAreas .. " corrupt navareas..." )
    end

    for _, area in ipairs( corruptAreas ) do
        debugoverlay.Cross( area:GetCenter() + deleteHighlighOffset, 55, 60, red, true )

    end
    navmeshDeleteAreas( corruptAreas, true, caller )

end

local yellow = Color( 255, 255, 0 )

local function navmeshHighlightCorruptAreasCmd( caller, _, args )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if NAVOPTIMIZER_tbl.isBusy then return end

    local toHighlight

    local rad = tonumber( args[1] ) or 2000
    if IsValid( caller ) and rad and rad >= 1 then
        local center = caller:GetPos()
        local maxs = Vector( rad, rad, rad ) * 2
        local areasFound = navmesh.FindInBox( center + maxs, center + -maxs )

        local corruptAreas = getCorruptAreas( areasFound )
        toHighlight = {}

        debugoverlay.Sphere( center, rad, 10, transparentWhite, true )

        local radSqr = rad^2
        for _, area in ipairs( corruptAreas ) do
            if area:GetCenter():DistToSqr( center ) < radSqr then
                table.insert( toHighlight, area )

            end
        end
        if #toHighlight <= 0 then
            NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "No corrupt areas to highlight in a radius of " .. rad .. " around the caller. 0 radius for mapwide" )
            return

        else
            NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Highlighting clipped to radius of " .. rad .. "..." )

        end

    else
        toHighlight = getCorruptAreas()

        if #toHighlight <= 0 then
            NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "No corrupt areas to highlight." )
            return

        end
    end

    for _, area in ipairs( toHighlight ) do
        debugoverlay.Cross( area:GetCenter(), 50, 60, yellow, true )

    end
    NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Highlighted " .. #toHighlight .. " corrupt navareas with developer 1 visualizers..." )

end
local function navmeshTpToCorruptArea( caller )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if NAVOPTIMIZER_tbl.isBusy then return end
    if not IsValid( caller ) then NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Need valid caller, spawn into the game!" ) return end

    local corruptAreas, corruptCount = getCorruptAreas()
    if #corruptAreas <= 0 then
        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "No corrupt areas." )
        return

    end

    local index = math.random( 1, #corruptAreas )

    NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Teleported " .. caller:GetName() .. " to corrupt area #" .. index .. " / " .. corruptCount )
    caller:SetPos( corruptAreas[index]:GetCenter() )

end

concommand.Add( "navmesh_trim_displacement_areas", navmeshStartDisplacementTrim, nil, "Removes small, 'redundant' areas on top of displacements", FCVAR_NONE )
concommand.Add( "navmesh_trim_deepunderwater_areas", beginDeepWaterTrim, nil, "Removes areas under deep water. ( default >350 units deep )", FCVAR_NONE )

concommand.Add( "navmesh_iscorrupt", corruptedCommand, nil, "Tells you if the navmesh is \"corrupt\", for example if the navmesh was generated on a different map that so happens to share names with the current one.", FCVAR_NONE )

concommand.Add( "navmesh_delete_allareas", navmeshDeleteAllAreasCmd, nil, "Removes ALL navareas.", FCVAR_NONE )
concommand.Add( "navmesh_delete_skyboxareas", navmeshDeleteSkyboxAreasCmd, nil, "Removes navareas in the skybox, can be imperfect", FCVAR_NONE )
concommand.Add( "navmesh_delete_corruptareas", navmeshDeleteCorruptAreasInRadiusCmd, nil, "Removes \"corrupt\" navareas, closer than 'radius' to the caller. 0 radius for mapwide, default 2000.", FCVAR_NONE )

concommand.Add( "navmesh_highlight_corruptareas", navmeshHighlightCorruptAreasCmd, nil, "Places \"developer 1\" crosses on \"corrupt\" navareas. 0 radius for mapwide, default 2000.", FCVAR_NONE )
concommand.Add( "navmesh_teleportto_corruptarea", navmeshTpToCorruptArea, nil, "Teleports caller to a random corrupt area on the map", FCVAR_NONE )