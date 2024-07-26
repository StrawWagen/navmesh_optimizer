-- find small areas that have connections on all 4 sides, that are on displacements
local function handlePotentialDisplacementArea( area )
    if not area or not area.IsValid or not area:IsValid() then return end

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

            elseif result == "done" then
                navmeshRemoveSmallAreasOnDisplacements = nil
                navmeshRemoveSmallAreasOnDisplacementsCor = nil
                NAVOPTIMIZER_tbl.canDoGlobalMerge = true
                break

            end
        end
    end
end

local function navmeshStartDisplacementTrim( caller )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if NAVOPTIMIZER_tbl.canDoGlobalMerge ~= true then return end --don't interrupt!
    callerPersist = caller
    NAVOPTIMIZER_tbl.enableNavEdit( callerPersist )

    NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Removing small areas with more than 3 neighbors on displacements!" )
    NAVOPTIMIZER_tbl.canDoGlobalMerge = false
    navmeshRemoveSmallAreasOnDisplacements = true

    hook.Add( "Tick", "navmeshRemoveSmallAreasOnDisplacements", thinkHookDisplacementTrim )

end

local function handlePotentialDeepUnderwaterArea( area, depth )
    if not area or not area.IsValid or not area:IsValid() then return end

    if not area:IsUnderwater() then return end

    local offsetVec = Vector( 0, 0, 0 )
    local pos = area:GetCenter()
    local wasDry
    -- 350 depth
    for ind = 1, depth do
        offsetVec.z = ind
        if bit.band( util.PointContents( pos + offsetVec ), CONTENTS_WATER ) <= 0 then 
            wasDry = true
            break

        end
    end

    if wasDry then return end

    area:Remove()

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
        while math.abs( oldTime - SysTime() ) < 0.0005 do
            local noErrors, result = coroutine.resume( navmeshRemoveAreasDeepUnderwaterCor )
            if noErrors == false then
                ErrorNoHaltWithStack( result )

            elseif result == "done" then
                navmeshRemoveAreasDeepUnderwater = nil
                navmeshRemoveAreasDeepUnderwaterCor = nil
                NAVOPTIMIZER_tbl.canDoGlobalMerge = true
                break

            end
        end
    end
end

local function beginDeepWaterTrim( caller, _, depthOverride )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if NAVOPTIMIZER_tbl.canDoGlobalMerge ~= true then return end --don't interrupt!
    callerPersist = caller
    NAVOPTIMIZER_tbl.enableNavEdit( callerPersist )

    local overrideAsNum = tonumber( depthOverride[1] )

    if not overrideAsNum or ( overrideAsNum and overrideAsNum <= 0 ) then
        depth = 350

    else
        depth = overrideAsNum

    end

    NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Removing areas in water more than " .. depth .. " units deep." )
    NAVOPTIMIZER_tbl.canDoGlobalMerge = false
    navmeshRemoveAreasDeepUnderwater = true

    hook.Add( "Tick", "navmeshRemoveAreasDeepUnderwater", thinkHookDeepWaterTrim )

end
local warned
local IsValid = IsValid

local function navmeshDeleteAllAreas( caller )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if NAVOPTIMIZER_tbl.canDoGlobalMerge ~= true then return end
    if not warned then
        warned = true
        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Are you sure you want to remove ALL navareas?\nRun this command again to proceed." )
        return

    end

    callerPersist = caller
    NAVOPTIMIZER_tbl.enableNavEdit( callerPersist )

    local removedAreas = 0
    local done = nil

    local blockSize = 500
    local areas = navmesh.GetAllNavAreas()
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
    for id = 1, 1000 do
        local ladder = navmesh.GetNavLadderByID( id )
        if IsValid( ladder ) then
            ladder:Remove()
            removedLadders = removedLadders + removedLadders

        end
    end

    timer.Create( "navmesh_remove_allareas", 0.5, 0, function()
        if not done then return end
        timer.Remove( "navmesh_remove_allareas" )
        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "DONE!" )

        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Removed " .. removedAreas .. " areas" )

        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Removed " .. removedLadders .. " navladders" )

        hook.Run( "navoptimizer_done_removingallareas" )
        NAVOPTIMIZER_tbl.nag( callerPersist )

    end )
end


concommand.Add( "navmesh_trim_displacement_areas", navmeshStartDisplacementTrim, nil, "Removes small, 'redundant' areas on top of displacements", FCVAR_NONE )
concommand.Add( "navmesh_trim_deepunderwater_areas", beginDeepWaterTrim, nil, "Removes areas under deep water. ( default >350 units deep )", FCVAR_NONE )

concommand.Add( "navmesh_delete_allareas", navmeshDeleteAllAreas, nil, "Removes ALL navareas.", FCVAR_NONE )