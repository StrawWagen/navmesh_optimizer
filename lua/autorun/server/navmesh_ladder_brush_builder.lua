
-- func_ladder brushes are compiled into the world as CONTENTS_LADDER brushes and don't exist as entities at runtime,
-- so we read them straight out of the map's .bsp

local noLadderMsg = "Map has no func_ladder brushes."
local noCallerMsg = "This command needs to be run by a player!"

local LUMP_PLANES = 1
local LUMP_BRUSHES = 18
local LUMP_BRUSHSIDES = 19

local brushSize = 12 -- int firstside, int numsides, int contents
local brushSideSize = 8 -- ushort planenum, short texinfo, short dispinfo, byte bevel, byte thin
local planeSize = 20 -- float normal[3], float dist, int type

local defaultWidth = 25
local mergeSlack = 1

local function readHeader( f )
    if f:Read( 4 ) ~= "VBSP" then return nil, "Map file isn't a VBSP." end
    f:ReadLong() -- version

    local lumps = {}
    for i = 0, 63 do
        local lump = {}
        lump.ofs = f:ReadLong()
        lump.len = f:ReadLong()
        lump.ver = f:ReadLong()
        lump.uncompressedLen = f:ReadLong()
        lumps[i] = lump

    end
    for _, idx in ipairs( { LUMP_PLANES, LUMP_BRUSHES, LUMP_BRUSHSIDES } ) do
        if lumps[idx].uncompressedLen ~= 0 then return nil, "Map's brush lumps are compressed, can't read them." end

    end
    return lumps

end

local function readBrushPlanes( f, lumps, firstSide, numSides )
    local planeNums = {}
    f:Seek( lumps[LUMP_BRUSHSIDES].ofs + firstSide * brushSideSize )
    for i = 1, numSides do
        planeNums[i] = f:ReadUShort()
        f:Skip( brushSideSize - 2 )

    end

    local planes = {}
    for i, planeNum in ipairs( planeNums ) do
        f:Seek( lumps[LUMP_PLANES].ofs + planeNum * planeSize )
        local x = f:ReadFloat()
        local y = f:ReadFloat()
        local z = f:ReadFloat()
        planes[i] = { normal = Vector( x, y, z ), dist = f:ReadFloat() }

    end
    return planes

end

-- vbsp gives every brush axial bevel planes, so the axial ones are always the brush's AABB
local function aabbFromPlanes( planes )
    local mins = Vector( math.huge, math.huge, math.huge )
    local maxs = Vector( -math.huge, -math.huge, -math.huge )
    for _, plane in ipairs( planes ) do
        local n = plane.normal
        for _, axis in ipairs( { "x", "y", "z" } ) do
            if n[axis] > 0.999 then
                maxs[axis] = plane.dist

            elseif n[axis] < -0.999 then
                mins[axis] = -plane.dist

            end
        end
    end
    for _, axis in ipairs( { "x", "y", "z" } ) do
        if mins[axis] == math.huge or maxs[axis] == -math.huge then return end

    end
    return mins, maxs

end

-- opposing horizontal plane pairs are the slab's extents, thinnest pair is the climbable axis, works for rotated ladders too
local function slabFromPlanes( planes )
    local pairsFound = {}
    for i, a in ipairs( planes ) do
        if math.abs( a.normal.z ) < 0.01 then
            for j = i + 1, #planes do
                local b = planes[j]
                if a.normal:Dot( b.normal ) < -0.999 then
                    table.insert( pairsFound, { normal = a.normal, extent = a.dist + b.dist } )

                end
            end
        end
    end

    local thinnest
    for _, pair in ipairs( pairsFound ) do
        if not thinnest or pair.extent < thinnest.extent then
            thinnest = pair

        end
    end
    if not thinnest then return end

    local width = defaultWidth
    for _, pair in ipairs( pairsFound ) do
        if math.abs( pair.normal:Dot( thinnest.normal ) ) < 0.01 then
            width = pair.extent
            break

        end
    end
    return thinnest.normal, thinnest.extent, width

end

local function readLadderBrushes()
    local f = file.Open( "maps/" .. game.GetMap() .. ".bsp", "rb", "GAME" )
    if not f then return nil, "Couldn't open the map's .bsp." end

    local lumps, err = readHeader( f )
    if not lumps then f:Close() return nil, err end

    local brushesLump = lumps[LUMP_BRUSHES]
    local ladderBrushes = {}
    for i = 0, brushesLump.len / brushSize - 1 do
        f:Seek( brushesLump.ofs + i * brushSize )
        local firstSide = f:ReadLong()
        local numSides = f:ReadLong()
        local contents = f:ReadLong()

        if bit.band( contents, CONTENTS_LADDER ) ~= 0 then
            local planes = readBrushPlanes( f, lumps, firstSide, numSides )
            local mins, maxs = aabbFromPlanes( planes )
            local normal, thickness, width = slabFromPlanes( planes )
            if mins and normal then
                table.insert( ladderBrushes, { mins = mins, maxs = maxs, normal = normal, thickness = thickness, width = width } )

            end
        end
    end
    f:Close()
    return ladderBrushes

end

local function aabbsTouch( a, b )
    for _, axis in ipairs( { "x", "y", "z" } ) do
        if a.mins[axis] > b.maxs[axis] + mergeSlack or b.mins[axis] > a.maxs[axis] + mergeSlack then return false end

    end
    return true

end

local function projectedWidth( ladder )
    local right = ladder.normal:Cross( vector_up )
    local size = ladder.maxs - ladder.mins
    return math.abs( right.x ) * size.x + math.abs( right.y ) * size.y

end

-- mappers build one ladder out of several stacked/side by side brushes
local function mergeLadderBrushes( brushes )
    local merged = true
    while merged do
        merged = false
        for i = #brushes, 1, -1 do
            local a = brushes[i]
            for j = i - 1, 1, -1 do
                local b = brushes[j]
                if math.abs( a.normal:Dot( b.normal ) ) > 0.99 and aabbsTouch( a, b ) then
                    local mins = Vector( math.min( a.mins.x, b.mins.x ), math.min( a.mins.y, b.mins.y ), math.min( a.mins.z, b.mins.z ) )
                    local maxs = Vector( math.max( a.maxs.x, b.maxs.x ), math.max( a.maxs.y, b.maxs.y ), math.max( a.maxs.z, b.maxs.z ) )
                    b.mins = mins
                    b.maxs = maxs
                    b.thickness = math.max( a.thickness, b.thickness )
                    -- projection overestimates rotated ladders, the sum overestimates stacked ones
                    b.width = math.min( projectedWidth( b ), a.width + b.width )
                    table.remove( brushes, i )
                    merged = true
                    break

                end
            end
        end
    end
    return brushes

end

local cachedLadders
local cachedErr

-- returns a shared cache, copy before mutating
local function getBrushLadders()
    if cachedLadders or cachedErr then return cachedLadders, cachedErr end

    local brushes, err = readLadderBrushes()
    if not brushes then cachedErr = err return nil, err end

    cachedLadders = mergeLadderBrushes( brushes )
    for _, ladder in ipairs( cachedLadders ) do
        ladder.center = ( ladder.mins + ladder.maxs ) / 2

    end
    return cachedLadders

end

local function ladderFace( ladder, side )
    local face = ladder.center + side * ( ladder.thickness / 2 )
    local bottom = Vector( face.x, face.y, ladder.mins.z )
    local top = Vector( face.x, face.y, ladder.maxs.z )
    return bottom, top

end

local openHull = Vector( 8, 8, 8 )
local openCheckDist = 32

local function sideOpenness( ladder, side )
    local face = ladder.center + side * ( ladder.thickness / 2 )
    local start = face + side * ( openHull.x + 2 )
    local tr = util.TraceHull( {
        start = start,
        endpos = start + side * openCheckDist,
        mins = -openHull,
        maxs = openHull,
        mask = MASK_PLAYERSOLID,
    } )
    if tr.StartSolid then return 0 end
    return tr.Fraction

end

local function openSide( ladder )
    local side = ladder.normal
    if sideOpenness( ladder, -side ) > sideOpenness( ladder, side ) then
        side = -side

    end
    return side

end

local function sideFacing( ladder, pos )
    local side = ladder.normal
    if ( pos - ladder.center ):Dot( side ) < 0 then
        side = -side

    end
    return side

end

-- nav ladders connected to no area are missed
local function getAllNavLadders()
    local navLadders = {}
    for _, area in ipairs( navmesh.GetAllNavAreas() ) do
        for _, navLadder in ipairs( area:GetLadders() ) do
            navLadders[navLadder:GetID()] = navLadder

        end
    end
    return navLadders

end

local navLadderSlack = Vector( 32, 32, 32 )

local function hasNavLadder( ladder, navLadders )
    local mins = ladder.mins - navLadderSlack
    local maxs = ladder.maxs + navLadderSlack
    for _, navLadder in pairs( navLadders ) do
        local mid = ( navLadder:GetBottom() + navLadder:GetTop() ) / 2
        if mid:WithinAABox( mins, maxs ) then return true end

    end
    return false

end

local function getLaddersOrComplain( caller )
    local ladders, err = getBrushLadders()
    if not ladders then
        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( err )
        return

    end
    if #ladders <= 0 then
        if IsValid( caller ) then
            NAVOPTIMIZER_tbl.printCenterAlias( noLadderMsg, caller )

        else
            NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( noLadderMsg )

        end
        return

    end
    return ladders

end

local function getNearestBrushLadder( ladders, pos )
    local nearestDist = math.huge
    local nearestIndex
    for i, ladder in ipairs( ladders ) do
        local bottom = Vector( ladder.center.x, ladder.center.y, ladder.mins.z )
        local top = Vector( ladder.center.x, ladder.center.y, ladder.maxs.z )
        local dist = util.DistanceToLine( bottom, top, pos )
        if dist < nearestDist then
            nearestDist = dist
            nearestIndex = i

        end
    end
    return nearestIndex, ladders[nearestIndex]

end


local manualTimer = "navmesh_ladderbrush_manualbuild_"
local manualHull = Vector( defaultWidth / 2, defaultWidth / 2, defaultWidth / 2 )
local ang_zero = Angle( 0, 0, 0 )

local function manualAimPos( caller )
    local eyetraceHitNpcClips = util.GetPlayerTrace( caller, caller:GetAimVector() )
    eyetraceHitNpcClips.mask = MASK_NPCSOLID
    return util.TraceLine( eyetraceHitNpcClips ).HitPos

end

-- extended so points above/below the brush don't get clamped to its ends
local function snapToFace( ladder, side, point0, point1 )
    local bottom, top = ladderFace( ladder, side )
    bottom = bottom + -vector_up * 3200
    top = top + vector_up * 3200
    local _, snapped0 = util.DistanceToLine( bottom, top, point0 )
    local _, snapped1 = util.DistanceToLine( bottom, top, point1 )
    if snapped0.z > snapped1.z then
        return snapped1, snapped0

    end
    return snapped0, snapped1

end

local function buildManualSnapCommand( caller )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if not IsValid( caller ) then NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( noCallerMsg ) return end

    local pos = manualAimPos( caller )
    local point0 = caller.navopti_brushladder_manual_point0

    -- place bottom
    if not point0 then
        local ladders = getLaddersOrComplain( caller )
        if not ladders then return end

        local _, ladder = getNearestBrushLadder( ladders, pos )
        caller.navopti_brushladder_manual_ladder = ladder
        caller.navopti_brushladder_manual_side = sideFacing( ladder, caller:GetPos() )
        caller.navopti_brushladder_manual_point0 = pos

    -- place top
    else
        local ladder = caller.navopti_brushladder_manual_ladder
        local side = caller.navopti_brushladder_manual_side
        local bottom, top = snapToFace( ladder, side, point0, pos )
        navmesh.CreateNavLadder( top, bottom, ladder.width, side, 25 )

        caller.navopti_brushladder_manual_ladder = nil
        caller.navopti_brushladder_manual_side = nil
        caller.navopti_brushladder_manual_point0 = nil
        return

    end

    local timerNameInt = manualTimer .. caller:GetCreationID()
    timer.Create( timerNameInt, 0.1, 0, function()
        if not IsValid( caller ) then timer.Remove( timerNameInt ) return end
        local point0Timer = caller.navopti_brushladder_manual_point0
        if not point0Timer then timer.Remove( timerNameInt ) return end

        local ladder = caller.navopti_brushladder_manual_ladder
        local side = caller.navopti_brushladder_manual_side
        local bottom, top = snapToFace( ladder, side, point0Timer, manualAimPos( caller ) )
        debugoverlay.SweptBox( bottom, top, -manualHull, manualHull, ang_zero, 0.11 )

    end )
end
concommand.Add( "navmesh_ladderbrush_buildmanual_snap", buildManualSnapCommand, nil, "Create navladders on func_ladder brushes, on the side you're standing on, allows for manual placement of top/bottom", FCVAR_NONE )


local isShowing
local timerName = "navmesh_ladderbrush_show"

local redDull = Color( 255, 0, 0, 150 )
local green = Color( 0, 255, 0, 50 )
local greenSolid = Color( 0, 255, 0 )

local function toggleShowLadders( caller )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if isShowing then
        isShowing = nil
        timer.Remove( timerName )
        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Highlighting stopped." )
        return

    end

    local ladders = getLaddersOrComplain( caller )
    if not ladders then return end

    isShowing = true
    timer.Create( timerName, 1, 0, function()
        local navLadders = getAllNavLadders()
        for _, ladder in ipairs( ladders ) do
            local navved = hasNavLadder( ladder, navLadders )
            local color = navved and redDull or green
            debugoverlay.Box( vector_origin, ladder.mins, ladder.maxs, 1.1, color )
            if not navved then
                local bottom, top = ladderFace( ladder, ladder.normal )
                debugoverlay.Line( bottom, top, 1.1, greenSolid, true )
                bottom, top = ladderFace( ladder, -ladder.normal )
                debugoverlay.Line( bottom, top, 1.1, greenSolid, true )

            end
        end
    end )
    NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Highlighting " .. #ladders .. " func_ladder brushes.\nRun developer 1 to see ladders." )

end
concommand.Add( "navmesh_ladderbrush_showall", toggleShowLadders, nil, "Show all func_ladder brushes on the map, Needs developer 1", FCVAR_NONE )

local function tpToLadder( caller )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if not IsValid( caller ) then NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( noCallerMsg ) return end
    if caller:GetMoveType() ~= MOVETYPE_NOCLIP then NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "You have to be in noclip to run this command." ) return end

    local ladders = getLaddersOrComplain( caller )
    if not ladders then return end

    local navLadders = getAllNavLadders()
    local lastIndex = caller.navopti_brushladder_tpindex or 0
    for offset = 1, #ladders do
        local i = ( lastIndex + offset - 1 ) % #ladders + 1
        local ladder = ladders[i]
        if not hasNavLadder( ladder, navLadders ) then
            local side = openSide( ladder )
            local bottom = ladderFace( ladder, side )
            caller:SetPos( bottom + side * 32 )
            caller.navopti_brushladder_tpindex = i
            return

        end
    end
    NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "No more ladders." )

end
concommand.Add( "navmesh_ladderbrush_tp", tpToLadder, nil, "Teleports the caller to an un-navmeshed func_ladder brush", FCVAR_NONE )
