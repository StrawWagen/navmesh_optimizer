
local upOffset = Vector( 0, 0, 4 )
local bigNegativeZ = Vector( 0, 0, -3000 )

-- helper: check if all 4 corners of an area hit a texture name containing `needleLower`
local function areaCornersAllHitTextureContains( area, needleLower )
    if not IsValid( area ) then return false end

    -- small upward offset to ensure we trace down onto the floor reliably
    for cornerId = 0, 3 do
        local corner = area:GetCorner( cornerId )
        if not corner then return false end

        local traceDat = {
            mask = bit.bor( MASK_SOLID, CONTENTS_MONSTERCLIP ),
            start = corner + upOffset,
            endpos = corner + bigNegativeZ
        }
        local tr = util.TraceLine( traceDat )
        if tr.StartSolid then continue end

        local hitTex = tr and tr.HitTexture or nil
        if not hitTex then return false end

        -- normalize to lowercase for robust matching
        local hitLower = string.lower( tostring( hitTex ) )
        if not string.find( hitLower, needleLower, 1, true ) then
            return false
        end
    end
    return true
end

local findAreasOnMatActive
local findAreasOnMatCor

-- start a gradual scan over all navareas; calls onDone(areasFound) when complete
local function startFindAreasOnMaterial( caller, materialSubstring, onDone )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if NAVOPTIMIZER_tbl.isBusy then return end

    local needle = tostring( materialSubstring or "" )
    needle = string.Trim( needle )
    if needle == "" then
        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Provide a material substring to match (example: toolsnodraw)." )
        return
    end

    local needleLower = string.lower( needle )

    -- enter busy and enable nav edit, like other long tasks
    NAVOPTIMIZER_tbl.isBusy = true
    callerPersist = caller
    NAVOPTIMIZER_tbl.enableNavEdit( callerPersist )

    local allAreas = navmesh.GetAllNavAreas()
    local total = #allAreas
    local found = {}

    NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Scanning " .. total .. " navareas for floor material containing '" .. needle .. "'..." )

    local nextProgress = SysTime() + 5
    local lastCount = 0

    local function runner()
        for idx, area in ipairs( allAreas ) do
            coroutine.yield()

            if areaCornersAllHitTextureContains( area, needleLower ) then
                found[#found + 1] = area
            end

            if SysTime() > nextProgress and #found ~= lastCount then
                nextProgress = SysTime() + 5
                lastCount = #found
                NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Matched " .. #found .. " areas so far (" .. idx .. " / " .. total .. ")" )
            end

            -- lightweight on-screen progress if available
            if NAVOPTIMIZER_tbl.printCenterAlias then
                NAVOPTIMIZER_tbl.printCenterAlias( "AREA " .. idx .. " / " .. total .. "\nMatches so far: " .. #found )
            end
        end

        -- finished
        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Done scanning. Found " .. #found .. " areas on '" .. needle .. "'." )
        coroutine.yield( "done" )
    end

    findAreasOnMatCor = coroutine.create( runner )
    findAreasOnMatActive = true

    hook.Add( "Tick", "navoptimizer_FindAreasOnMaterial", function()
        if not findAreasOnMatActive then hook.Remove( "Tick", "navoptimizer_FindAreasOnMaterial" ) return end
        if not findAreasOnMatCor then hook.Remove( "Tick", "navoptimizer_FindAreasOnMaterial" ) return end

        local start = SysTime()
        while math.abs( start - SysTime() ) < 0.005 do
            local ok, res = coroutine.resume( findAreasOnMatCor )
            if not ok then
                ErrorNoHaltWithStack( res )
                findAreasOnMatActive = nil
                findAreasOnMatCor = nil
                NAVOPTIMIZER_tbl.isBusy = false
                hook.Remove( "Tick", "navoptimizer_FindAreasOnMaterial" )
                return
            end

            if res == "done" then
                findAreasOnMatActive = nil
                findAreasOnMatCor = nil
                NAVOPTIMIZER_tbl.isBusy = false -- release busy so follow-up work (like deletion) can run
                hook.Remove( "Tick", "navoptimizer_FindAreasOnMaterial" )

                if isfunction( onDone ) then
                    onDone( found, needle )
                end
                return
            end
        end
    end )
end

-- command handlers
local function deleteAllAreasOnMat( caller, _, args )
    local needle = args and table.concat( args, " " ) or ""

    startFindAreasOnMaterial( caller, needle, function( areas, _needle )
        if #areas <= 0 then
            NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "No areas found on material containing '" .. _needle .. "'." )
            return
        end

        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Removing " .. #areas .. " areas on '" .. _needle .. "'..." )
        -- avoid touching ladders here
        navmeshDeleteAreas( areas, true, caller, "navoptimizer_done_removingareasonmat" )
    end )
end

local function deleteNodrawAreas( caller )
    startFindAreasOnMaterial( caller, "toolsnodraw", function( areas )
        if #areas <= 0 then
            NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "No areas found on top of toolsnodraw." )
            return
        end

        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Removing " .. #areas .. " areas on toolsnodraw..." )
        -- ditto
        navmeshDeleteAreas( areas, true, caller, "navoptimizer_done_removingnodrawareas" )
    end )
end

concommand.Add( "navmesh_delete_areasonmat", deleteAllAreasOnMat, nil, "Deletes areas who entirely rest on textures containing the given substring.", FCVAR_NONE )
concommand.Add( "navmesh_delete_nodrawareas", deleteNodrawAreas, nil, "Deletes areas resting entirely on toolsnodraw.", FCVAR_NONE )
