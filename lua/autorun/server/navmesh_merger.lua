

NAVOPTIMIZER_tbl = NAVOPTIMIZER_tbl or {}

NAVOPTIMIZER_tbl.interestingEntityClasses = {
    "prop_physics",
    "info_ladder_dismount",
    "prop_door_rotating",
    "func_button",

}

local spawnTypes = {
    "info_player_deathmatch",
    "info_player_combine",
    "info_player_rebel",
    "info_player_counterterrorist",
    "info_player_terrorist",
    "info_player_axis",
    "info_player_allies",
    "info_player_start",
    "info_player_teamspawn",
    "info_player_human",
    "info_player_undead",
    "info_player_zombie",
    "gmod_player_start",
}

local tpExits = {
    "info_teleport_destination",
}

table.Add( NAVOPTIMIZER_tbl.interestingEntityClasses, spawnTypes )
table.Add( NAVOPTIMIZER_tbl.interestingEntityClasses, tpExits )

local callerPersist = nil
local bigNegativeZ = Vector( 0, 0, -3000 )
local startOffset = Vector( 0, 0, 100 )
local blockPrintCenter = CreateConVar( "navoptimizer_blockprintcenters", 0, { FCVAR_ARCHIVE, FCVAR_CHEAT } )

function NAVOPTIMIZER_tbl.getFloorTr( pos )
    local traceDat = {
        mask = MASK_SOLID_BRUSHONLY,
        start = pos + startOffset,
        endpos = pos + bigNegativeZ
    }

    local trace = util.TraceLine( traceDat )
    return trace

end

local function snappedToFloor( pos )
    local traceDat = {
        mask = MASK_SOLID,
        start = pos,
        endpos = pos + bigNegativeZ
    }

    local trace = util.TraceLine( traceDat )
    if not trace.Hit then return nil, nil end

    local snapped = trace.HitPos
    if not util.IsInWorld( snapped ) then return nil, nil end

    return true, snapped, trace
end

local function posIsDisplacement( pos )
    local tr = NAVOPTIMIZER_tbl.getFloorTr( pos )
    if not tr then return end
    if tr.HitTexture ~= "**displacement**" then return end
    return true

end

-- COPIED FROM GLEE
local fiftyPowerOfTwo = 50^2
local vec12kZ = Vector( 0, 0, 12000 )
local vecNeg1K = Vector( 0, 0, -1000 )

local function IsUnderDisplacement( pos )

    -- get the sky
    local firstTraceDat = {
        start = pos,
        endpos = pos + vec12kZ,
        mask = MASK_SOLID_BRUSHONLY,
    }
    local firstTraceResult = util.TraceLine( firstTraceDat )

    -- go back down
    local secondTraceDat = {
        start = firstTraceResult.HitPos,
        endpos = pos,
        mask = MASK_SOLID_BRUSHONLY,
    }
    local secondTraceResult = util.TraceLine( secondTraceDat )
    if secondTraceResult.HitTexture ~= "**displacement**" then return nil, nil end

    -- final check to make sure
    local thirdTraceDat = {
        start = pos,
        endpos = pos + vecNeg1K,
        mask = MASK_SOLID_BRUSHONLY,
    }
    local thirdTraceResult = util.TraceLine( thirdTraceDat )
    local isANestedDisplacement = thirdTraceResult.HitTexture == "**displacement**" and secondTraceResult.HitPos:DistToSqr( thirdTraceResult.HitPos ) > fiftyPowerOfTwo

    if thirdTraceResult.Hit and thirdTraceResult.HitTexture ~= "TOOLS/TOOLSNODRAW" and not isANestedDisplacement then return nil, true end -- we are probably under a displacement

    -- we are DEFINITely under one
    return true, nil

end

local underDisplacementOffset = Vector()

-- check the actual pos + visible spots nearby to truly know if a point is under a displacement, expensive!
local function IsUnderDisplacementExtensive( pos )
    local underBasic, underNested = IsUnderDisplacement( pos )
    if underBasic or underNested then return true end

    local traceStruct = {
        mask = MASK_SOLID_BRUSHONLY,
        start = pos,
    }
    for index = 1, 100 do
        -- check next to the pos to see if there's any empty space next to it
        underDisplacementOffset.x = math.Rand( -1, 1 ) * ( index^1.5 )
        underDisplacementOffset.y = math.Rand( -1, 1 ) * ( index^1.5 )
        local checkingPos = pos + underDisplacementOffset
        if not util.IsInWorld( checkingPos ) then continue end

        traceStruct.endpos = checkingPos

        local seePosResult = util.TraceLine( traceStruct )
        -- this way goes into a wall
        if seePosResult.Hit then continue end

        local checkingIsUnder, checkingIsNested = IsUnderDisplacement( checkingPos )
        if checkingIsUnder or checkingIsNested then return true end

    end
    return false

end

local function areaIsEntirelyOverDisplacements( area )
    local positions = {
        area:GetCorner( 0 ),
        area:GetCorner( 1 ),
        area:GetCorner( 2 ),
        area:GetCorner( 3 ),

    }
    for _, position in ipairs( positions ) do
        -- if just 1 of these is not on a displacement, then return nil
        if not posIsDisplacement( position ) then return end
    end
    -- every corner passed the check
    return true

end

function NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( msg )
    if not IsValid( callerPersist ) then
        print( msg )

    elseif not blockPrintCenter:GetBool() then
        PrintMessage( HUD_PRINTCONSOLE, msg )

    end
end

local function printCenterTimed( msg, time )
    local timerName = "NAVOPTIMIZER_PRINTCENTER"
    if blockPrintCenter:GetBool() then return end
    timer.Remove( timerName )
    timer.Create( timerName, 1, time, function()
        if IsValid( callerPersist ) then
            callerPersist:PrintMessage( HUD_PRINTCENTER, msg )

        else
            PrintMessage( HUD_PRINTCENTER, msg )

        end
    end )
end

function NAVOPTIMIZER_tbl.printCenterAlias( msg, toPrint )
    if blockPrintCenter:GetBool() then return end
    if IsValid( toPrint ) then
        toPrint:PrintMessage( HUD_PRINTCENTER, msg )

    else
        PrintMessage( HUD_PRINTCENTER, msg )

    end
end


local function anyAreCloserThan( positions, checkPosition, closerThanDistance, zTolerance )
    for _, position in ipairs( positions ) do
        local tooClose = position:DistToSqr( checkPosition ) < closerThanDistance^2
        local zToleranceException = math.abs( position.z - checkPosition.z ) > zTolerance
        if tooClose and not zToleranceException then
            return true
        end
    end
end

local function doorIsUsable( door )
    local center = door:WorldSpaceCenter()
    local forward = door:GetForward()
    local starOffset = forward * 50
    local endOffset  = forward * 2

    local traceDatF = {
        mask = MASK_SOLID_BRUSHONLY,
        start = center + starOffset,
        endpos = center + endOffset
    }

    local traceDatB = {
        mask = MASK_SOLID_BRUSHONLY,
        start = center + -starOffset,
        endpos = center + -endOffset
    }

    local traceBack = util.TraceLine( traceDatB )
    local traceFront = util.TraceLine( traceDatF )

    local canSmash = not traceBack.Hit and not traceFront.Hit
    return canSmash

end

local function connectionData( currArea, otherArea )
    local currCenter = currArea:GetCenter()

    local nearestInitial = otherArea:GetClosestPointOnArea( currCenter )
    local nearestFinal   = currArea:GetClosestPointOnArea( nearestInitial )
    local height = -( nearestFinal.z - nearestInitial.z )

    nearestFinal.z = nearestInitial.z
    local distTo   = nearestInitial:DistToSqr( nearestFinal )

    return distTo, height

end

local function getShortestDistanceToNavSqr( checkNav, checkPos )
    return checkPos:DistToSqr( checkNav:GetClosestPointOnArea( checkPos ) )
end

local down = Vector( 0, 0, -1 )

function NAVOPTIMIZER_tbl.getNearestNav( pos, distance )
    if not pos then return NULL end
    local Dat = {
        start = pos,
        endpos = pos + down * distance,
        mask = MASK_SOLID_BRUSHONLY
    }
    local Trace = util.TraceLine( Dat )
    if not Trace.HitWorld then return NULL end
    local navArea = navmesh.GetNearestNavArea( Trace.HitPos, false, distance, false, true, -2 )
    if not navArea then return NULL end
    if not navArea:IsValid() then return NULL end
    return navArea

end

function NAVOPTIMIZER_tbl.getNearestNavMidair( pos, distance )
    if not pos then return NULL end
    local navArea = navmesh.GetNearestNavArea( pos, false, distance, false, true, -2 )
    if not navArea then return NULL end
    if not navArea:IsValid() then return NULL end
    return navArea

end

-- EXAMPLE HOOK USAGE
--[[
hook.Add( "navoptimizer_addclassesusuallyinsidethemap", "addplayerlol", function( theClasses )
    table.insert( theClasses, "player" )

end )

hook.Add( "navoptimizer_replaceclassesusuallyinsidethemap", "onlyplayer", function( theClasses )
    return true, { "player" }

end )
--]]
--[[
hook.Remove( "navoptimizer_addclassesusuallyinsidethemap", "addplayerlol" )
hook.Remove( "navoptimizer_replaceclassesusuallyinsidethemap", "onlyplayer" )
--]]

local function classesUsuallyInsideTheMap()
    local theClasses = table.Copy( NAVOPTIMIZER_tbl.interestingEntityClasses )

    ProtectedCall( function()
        hook.Run( "navoptimizer_addclassesusuallyinsidethemap", theClasses )

    end )

    ProtectedCall( function()
        local doReplace, theNewTable = hook.Run( "navoptimizer_replaceclassesusuallyinsidethemap", theClasses )
        if doReplace == true then
            theClasses = table.Copy( theNewTable )

        end
    end )

    return theClasses

end

-- goes thru all interesting ents and finds one with a navarea
local function navmeshCheck()
    local out = NULL
    local entsTypesLocal = classesUsuallyInsideTheMap()
    table.Shuffle( entsTypesLocal )

    for _, spawnClass in ipairs( entsTypesLocal ) do
        local theEnts = ents.FindByClass( spawnClass )
        table.Shuffle( theEnts )

        for _, theEnt in ipairs( theEnts ) do
            local area = NAVOPTIMIZER_tbl.getNearestNav( theEnt:GetPos(), 1000 )
            if not area then continue end
            if not area:IsValid() then continue end
            if table.Count( area:GetAdjacentAreas() ) < 2 then continue end

            out = area
            break

        end
        if out ~= NULL then
            break

        end
    end
    return out

end

-- takes 20 areas under interesting ents and checks if they have visibility data w/ their neighbors
function getNavmeshIsCheap()
    local isCheap = true
    for _ = 0, 20 do
        if isCheap ~= true then break end -- all done!

        local validNavarea = navmeshCheck()
        if not validNavarea then continue end
        if validNavarea == NULL then continue end

        for _, adjArea in ipairs( validNavarea:GetAdjacentAreas() ) do
            if adjArea:IsCompletelyVisible( validNavarea ) then
                isCheap = false
                break

            end
        end
    end
    return isCheap

end

local function navSurfaceArea( navArea )
    local area = navArea:GetSizeX() * navArea:GetSizeY()
    return area

end

local sv_cheats = GetConVar( "sv_cheats" )

function NAVOPTIMIZER_tbl.isNotCheats()
    if sv_cheats:GetBool() then return end
    local msg = "sv_cheats is 0!"
    NAVOPTIMIZER_tbl.printCenterAlias( msg )
    NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( msg )
    return true

end

local processed = {}
local editors = {}
local noConflict

local nav_edit = GetConVar( "nav_edit" )
cvars.AddChangeCallback( "nav_edit", function( _, _, new )
    if noConflict then return end
    local booled = tobool( new )
    for _, ply in player.Iterator() do
        editors[ply] = booled

    end
end, "navoptimizer_fixeditors" )

function NAVOPTIMIZER_tbl.enableNavEdit( caller )
    if not IsValid( caller ) then return end
    if not processed[caller] then
        processed[caller] = true
        if nav_edit:GetBool() then
            editors[caller] = true
        end
    end
    if not nav_edit:GetBool() then
        noConflict = true
        caller:ConCommand( "nav_edit 1" )

        timer.Simple( 1, function()
            noConflict = nil

        end )
    end
end

function NAVOPTIMIZER_tbl.disableNavEdit( caller )
    if not IsValid( caller ) then return end
    -- started with nav_edit already on? dont turn it off.
    if editors[caller] then return end

    noConflict = true
    caller:ConCommand( "nav_clear_selected_set" )
    caller:ConCommand( "nav_edit 0" )

    timer.Simple( 1, function()
        noConflict = nil

    end )
end

local cornerIndexes = { 0,1,2,3 }
local fiveSqared = 5^2

local function navAreaGetCloseCorners( pos, areaToCheck )

    if not areaToCheck then return end
    if not areaToCheck.isValid then return end
    if not areaToCheck:isValid() then return end
    local toReturn = nil
    local closeCorners = {}

    for _, biggestCornerIndex in ipairs( cornerIndexes ) do
        local biggestAreaCorner = areaToCheck:GetCorner( biggestCornerIndex )

        if pos:DistToSqr( biggestAreaCorner ) < fiveSqared then
            toReturn = true
            table.insert( closeCorners, biggestAreaCorner )

        end
    end

    return toReturn, closeCorners

end


function navAreasCanMerge( start, next )

    if not ( start and next ) then return false, 0, NULL end

    --SUPER fast
    local isStairs = start:HasAttributes( NAV_MESH_STAIRS ) or next:HasAttributes( NAV_MESH_STAIRS )
    local probablyBreakingStairs
    if isStairs then
        -- DONT MESS WITH STAIRS!
        probablyBreakingStairs = true
        -- ok these are coplanar, and they're both stairs... i'll let this slide....
        if start:IsCoplanar( next ) and start:HasAttributes( NAV_MESH_STAIRS ) and next:HasAttributes( NAV_MESH_STAIRS ) then
            bothstairs = true
            probablyBreakingStairs = nil

        end
    end

    local noMerge = start:HasAttributes( NAV_MESH_NO_MERGE ) or next:HasAttributes( NAV_MESH_NO_MERGE ) -- probably has this for a reason huh... 
    local doingAnObstacle = start:HasAttributes( NAV_MESH_OBSTACLE_TOP ) and next:HasAttributes( NAV_MESH_OBSTACLE_TOP )
    local noMergeAndNotObstacle = noMerge and not doingAnObstacle

    local transient = start:HasAttributes( NAV_MESH_TRANSIENT ) or next:HasAttributes( NAV_MESH_TRANSIENT )

    local startCrouch = start:HasAttributes( NAV_MESH_CROUCH )
    local nextCrouch = next:HasAttributes( NAV_MESH_CROUCH )
    local leavingCrouch = startCrouch and not nextCrouch
    local enteringCrouch = nextCrouch and not startCrouch

    local probablyBreakingCrouch = leavingCrouch or enteringCrouch -- don't make a little bit of crouch area way too big

    local startBlock = start:HasAttributes( NAV_MESH_NAV_BLOCKER )
    local nextBlock = next:HasAttributes( NAV_MESH_NAV_BLOCKER )
    local leavingBlock = startBlock and not nextBlock
    local enteringBlock = nextBlock and not startBlock

    local probablyBreakingSelectiveBlock = leavingBlock or enteringBlock

    if probablyBreakingStairs or noMergeAndNotObstacle or transient or probablyBreakingCrouch or probablyBreakingSelectiveBlock then return false, 0, NULL end

    local ladders = table.Add( start:GetLadders(), next:GetLadders() )

    if #ladders > 0 then return false, 0, NULL end -- dont break the ladders!

    -- fast
    local distance, height = connectionData( start, next )
    local nextToEachtoher = distance < 15^2
    local heightGood = math.abs( height ) < 20
    if not nextToEachtoher then return false, 0, NULL end
    if not heightGood then return false, 0, NULL end


    --fast
    local center1 = start:GetCenter()
    local center2 = next:GetCenter()
    local sameX = center1.x == center2.x
    local sameY = center1.y == center2.y

    local sameSomething = sameX or sameY
    if not sameSomething then return false, 0, NULL end --if we can, throw these away as early as possible

    -- fast
    local startSizeX = start:GetSizeX()
    local nextSizeX = next:GetSizeX()
    local startSizeY = start:GetSizeY()
    local nextSizeY = next:GetSizeY()

    local sameXSize = startSizeX == nextSizeX
    local sameYSize = startSizeY == nextSizeY

    local mergable = ( sameX and sameXSize ) or ( sameY and sameYSize )
    if not mergable then return false, 0, NULL end


    -- this is fast
    local maxLong = 800 -- default 700
    local tooLong = ( startSizeX + nextSizeX ) > maxLong or ( startSizeY + nextSizeY ) > maxLong

    local mySurfaceArea = navSurfaceArea( start )
    local nextAreaSurfaceArea = navSurfaceArea( next )

    local newSurfaceArea = mySurfaceArea + nextAreaSurfaceArea
    local wouldBeTooBig = newSurfaceArea > 300000 or tooLong
    if wouldBeTooBig then return false, 0, NULL end

    local coplanar = start:IsCoplanar( next )

    -- ok this merge is gonna cause artifacts!
    if not coplanar then
        local zDifference = math.abs( center1.z - center2.z )
        -- areas are far apart in height, the artifact will be big
        if zDifference > 10 then
            -- if they're both on displacements then we can let it slide
            local startIsOnDisplacement = areaIsEntirelyOverDisplacements( start )
            if not startIsOnDisplacement then return false, 0, NULL end

            local nextIsOnDisplacement = areaIsEntirelyOverDisplacements( next )
            if not nextIsOnDisplacement then return false, 0, NULL end

        end
    end

    return true, newSurfaceArea

end

function navmeshAttemptMerge( start, next )

    local canMerge, newSurfaceArea = navAreasCanMerge( start, next )

    if canMerge ~= true then return false, 0, NULL end

    --sloooow
    local connectionsFromStart = start:GetAdjacentAreas()
    local connectionsFromNext = next:GetAdjacentAreas()

    local connectionsToStart = start:GetIncomingConnections()
    local connectionsToNext = next:GetIncomingConnections()

    local connectionsFrom       = table.Add( connectionsFromStart, connectionsFromNext )
    local oneWayConnectionsTo   = table.Add( connectionsToStart, connectionsToNext )
    local twoWayConnections     = {}

    for key, twoWayArea in ipairs( connectionsFrom ) do
        if not start or not start.IsValid or not start:IsValid() then continue end
        if not next or not next.IsValid or not next:IsValid() then continue end
        if not twoWayArea or not twoWayArea.IsValid or not twoWayArea:IsValid() then continue end

        if ( start:IsConnected( twoWayArea ) or next:IsConnected( twoWayArea ) ) or ( twoWayArea:IsConnected( start ) or twoWayArea:IsConnected( next ) ) then
            table.insert( twoWayConnections, #twoWayConnections + 1, twoWayArea )
            connectionsFrom[ key ] = nil
        end
    end

    -- get biggest neighbor, we dont want fuck up a later merge with them if possible
    local largestSurfaceArea = 0
    local biggestArea = NULL

    for _, potentiallyBiggestArea in ipairs( twoWayConnections ) do
        local surfaceArea = navSurfaceArea( potentiallyBiggestArea )
        if surfaceArea > largestSurfaceArea then
            largestSurfaceArea = surfaceArea
            biggestArea = potentiallyBiggestArea
        end
    end

    -- make sure this doesnt break anythin
    if biggestArea ~= next then

        local sameCornerAsBiggestArea = nil
        local offendingCorners = {}
        local newOffendingCorners = {}

        for _, startCornerIndex in ipairs( cornerIndexes ) do
            local currStartCorner = start:GetCorner( startCornerIndex )

            sameCornerAsBiggestArea, newOffendingCorners = navAreaGetCloseCorners( currStartCorner, biggestArea )

            offendingCorners = table.Add( offendingCorners, newOffendingCorners )

        end

        -- start the cancelling checks when we could potentially merge with a way bigger neighbor
        if sameCornerAsBiggestArea then

            -- are we out of options?
            local mergingOptions = 0
            for _, mergableOption in ipairs( connectionsFromStart ) do
                if navAreasCanMerge( start, mergableOption ) and mergableOption ~= next then
                    mergingOptions = mergingOptions + 1
                end
            end

            -- allow blocking when there's more than 1 option, and we're not the smaller area
            if mergingOptions > 1 and navSurfaceArea( start ) > navSurfaceArea( next ) then
                -- cancel the merge if it will delete the corner we have in common with the biggest area
                for _, theOffendingCorner in ipairs( offendingCorners ) do
                    local startAreaEncapsulatesCorner = getShortestDistanceToNavSqr( start, theOffendingCorner )
                    local nextAreaEncapsulatesCorner = getShortestDistanceToNavSqr( next, theOffendingCorner )

                    if nextAreaEncapsulatesCorner and startAreaEncapsulatesCorner then
                        --debugoverlay.Cross( theOffendingCorner, 5, 5 )
                        --debugoverlay.Line( start:GetCenter() + Vector( 0,0,20 ), next:GetCenter(), 5, 20 )
                        return false, 0, NULL end
                end
            end
        end
    end

    -- north westy
    local NWCorner1 = start:GetCorner( 0 )
    local NWCorner2 = next:GetCorner( 0 )

    local NWCorner = NWCorner1
    if NWCorner2.y < NWCorner.y then
        NWCorner.y = NWCorner2.y
        NWCorner.z = NWCorner2.z
    end
    if NWCorner2.x < NWCorner.x then
        NWCorner.x = NWCorner2.x
        NWCorner.z = NWCorner2.z
    end

    -- find most north easty corner
    local NECorner1 = start:GetCorner( 1 )
    local NECorner2 = next:GetCorner( 1 )

    local NECorner = NECorner1
    if NECorner2.y < NECorner.y then
        NECorner.y = NECorner2.y
        NECorner.z = NECorner2.z
    end
    if NECorner2.x > NECorner.x then
        NECorner.x = NECorner2.x
        NECorner.z = NECorner2.z
    end

    -- find most south westy corner
    local SWCorner1 = start:GetCorner( 3 )
    local SWCorner2 = next:GetCorner( 3 )

    local SWCorner = SWCorner1
    if SWCorner2.y > SWCorner.y then
        SWCorner.y = SWCorner2.y
        SWCorner.z = SWCorner2.z
    end
    if SWCorner2.x < SWCorner.x then
        SWCorner.x = SWCorner2.x
        SWCorner.z = SWCorner2.z
    end

    -- find most south easty corner
    local SECorner1 = start:GetCorner( 2 )
    local SECorner2 = next:GetCorner( 2 )

    local SECorner = SECorner1
    if SECorner2.y > SECorner.y then
        SECorner.y = SECorner2.y
        SECorner.z = SECorner2.z
    end
    if SECorner2.x > SECorner.x then
        SECorner.x = SECorner2.x
        SECorner.z = SECorner2.z
    end

    local obstacle = start:HasAttributes( NAV_MESH_OBSTACLE_TOP ) or next:HasAttributes( NAV_MESH_OBSTACLE_TOP )
    local crouch = start:HasAttributes( NAV_MESH_CROUCH ) or next:HasAttributes( NAV_MESH_CROUCH )
    local stairs = start:HasAttributes( NAV_MESH_STAIRS ) or next:HasAttributes( NAV_MESH_STAIRS )

    local newArea = navmesh.CreateNavArea( NECorner, SWCorner )
    if not newArea or not newArea.IsValid or not newArea:IsValid() then return false, 0, NULL end -- this failed, dont delete the old areas

    start:Remove()
    next:Remove()

    if obstacle then
        newArea:SetAttributes( NAV_MESH_OBSTACLE_TOP )
    end

    if crouch then
        newArea:SetAttributes( NAV_MESH_CROUCH )
    end

    if stairs then
        newArea:SetAttributes( NAV_MESH_STAIRS )
    end

    for _, fromArea in pairs( connectionsFrom ) do
        if not fromArea or not fromArea.IsValid or not fromArea:IsValid() then continue end
        newArea:ConnectTo( fromArea )
    end
    for _, toArea in pairs( oneWayConnectionsTo ) do
        if not toArea or not toArea.IsValid or not toArea:IsValid() then continue end
        toArea:ConnectTo( newArea )
    end
    for _, twoWayArea in pairs( twoWayConnections ) do
        if not twoWayArea or not twoWayArea.IsValid or not twoWayArea:IsValid() then continue end
        newArea:ConnectTo( twoWayArea )
        twoWayArea:ConnectTo( newArea )
    end

    newArea:SetCorner( 0, NWCorner )
    newArea:SetCorner( 2, SECorner )

    --debugoverlay.Line( center1, center2, 3, Color( 255, 255, 255 ), true )

    return true, newSurfaceArea, newArea
end

-- 'directions' to check in, check halves too
local obstacleCheckVars = {
    Vector( 1.5,0,0 ),
    Vector( -1.5,0,0 ),
    Vector( 0,1.5,0 ),
    Vector( 0,-1.5,0 ),
    Vector( 1,0,0 ),
    Vector( -1,0,0 ),
    Vector( 0,1,0 ),
    Vector( 0,-1,0 )
}

function navmeshAutoAttemptMerge( navArea )
    local connecting = navArea:GetAdjacentAreas()

    if navArea:HasAttributes( NAV_MESH_OBSTACLE_TOP ) then -- detect pesky fencetop areas
        local doneObstacles = {} --obstacles that are done
        local center = navArea:GetCenter()
        local sizeY = navArea:GetSizeY()
        local maxSize = navArea:GetSizeX()

        if sizeY > maxSize then
            maxSize = sizeY
        end

        for _, obstacleCheck in ipairs( obstacleCheckVars ) do
            local checkPos = center + ( obstacleCheck * ( maxSize * 0.5 ) )
            local probableNav = NAVOPTIMIZER_tbl.getNearestNavMidair( checkPos, 500 )

            if not probableNav or not probableNav:IsValid() then continue end

            local probableId = probableNav:GetID()

            if not probableNav:HasAttributes( NAV_MESH_OBSTACLE_TOP ) then continue end
            if probableNav == navArea then continue end
            if doneObstacles[probableId] then continue end

            doneObstacles[probableId] = true

            table.insert( connecting, #connecting + 1, probableNav )

        end
    end

    table.Shuffle( connecting )

    for _, connectingArea in ipairs( connecting ) do
        local merged, mergedSurfaceArea = navmeshAttemptMerge( navArea, connectingArea )

        if merged == true then return true, mergedSurfaceArea, newMergedArea end

    end
    return false, 0, NULL

end

local forceExpensiveMerge = false
local generateCheapNavmesh = false

local canDoGlobalMerge = true
local doingGlobalMerge = false
local areasToMerge = {}
local areasToMergeCount = 0
local mergeIndex = 0

local operationsWithoutMerges = 0

local initialRepeatCount = 0

local doneMergedCount = 0
local doneMergedArea = 0

local repeatMergedCount = 0
local repeatMergedArea = 0

local doMessageThink = nil
local congragulated = nil
local globalMergeResultTime = 0
local doingRepeatMergedMessage = 0
local blockFinalAnalyze = nil
local analyzing = nil

-- "expensive" visibility dist, we are overriding the default of 6000 which is near half of a massive map like gm_novenka 
local expensiveVisDist = 3500

--[[
-- this example is untested
hook.Add( "navoptimizer_handlepotentialseedclass", "allowplayerseedstobe_CLOSE", function( seedEnt )
    if seedEnt:GetClass() ~= "player" then return end
    -- only block this seed from being placed if it's witin a weird sphere of 50 radius and squashed on top and bottom with planes to be 20 units high
    -- stops seeds from being packed, but allows them to be packed vertically, so floors of a building can all get their own seeds.
    return true, 50, 10

end )

--]]

local vec_up = Vector( 0, 0, 1 )

local function getComprehensiveSeedPositions( justReturn )
    local seedsAdded = 0
    local donePositions = {}
    local seedTypesLocal = classesUsuallyInsideTheMap()

    table.Shuffle( seedTypesLocal )

    for _, seedClass in ipairs( seedTypesLocal ) do
        local seeds = ents.FindByClass( seedClass )
        table.Shuffle( seeds )

        for _, seedEnt in ipairs( seeds ) do
            local zTolerance = 500
            local checkDist = 150
            local seedEntPos = seedEnt:GetPos()

            local hookHandledIt, hookCheckDist, hookZTolerance = nil, nil, nil

            ProtectedCall( function()
                hookHandledIt, hookCheckDist, hookZTolerance  = hook.Run( "navoptimizer_handlepotentialseedclass", seedEnt )

            end )

            if hookHandledIt and hookZTolerance and hookCheckDist then
                checkDist = hookCheckDist
                zTolerance = hookZTolerance

            elseif seedClass == "prop_door_rotating" then
                if not doorIsUsable( seedEnt ) then continue end
                seedEntPos = seedEnt:WorldSpaceCenter()
                local valid, floorPos = snappedToFloor( seedEntPos )
                if not valid then continue end
                seedEntPos = floorPos
                checkDist = 150
                zTolerance = 25

            elseif seedClass == "info_ladder_dismount" then
                seedEntPos = seedEnt:WorldSpaceCenter()
                local valid, floorPos = snappedToFloor( seedEntPos )
                if not valid then continue end
                seedEntPos = floorPos
                checkDist = 250
                zTolerance = 10

            elseif seedClass == "prop_physics" then
                seedEntPos = seedEnt:WorldSpaceCenter()
                local valid, floorPos = snappedToFloor( seedEntPos )
                if not valid then continue end
                seedEntPos = floorPos
                checkDist = 300
                zTolerance = 50

            end

            if anyAreCloserThan( donePositions, seedEntPos, checkDist, zTolerance ) == true then continue end

            if not justReturn then
                local nearNav = NAVOPTIMIZER_tbl.getNearestNav( seedEntPos, 1000 )

                if nearNav and nearNav.IsValid and nearNav:IsValid() then
                    local closestToPos = nearNav:GetClosestPointOnArea( seedEntPos )
                    closestToPos.z = seedEntPos.z
                    if seedEntPos:Distance( closestToPos ) < 50 then continue end

                end
            end

            table.insert( donePositions, seedEntPos )

            seedsAdded = seedsAdded + 1

        end
    end

    ProtectedCall( function()
        hook.Run( "navoptimizer_comprehensiveseedpositions_postbuilt", donePositions )

    end )


    -- place real walkable seeds for the generator?
    if not justReturn then
        for _, currentSeed in ipairs( donePositions ) do
            navmesh.AddWalkableSeed( currentSeed, vec_up )

        end
    end

    return donePositions

end

local function navAddSeedsUnderPlayers( justReturn )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if canDoGlobalMerge ~= true then return end --don't interrupt!

    local plys = player.GetAll()
    local extraSeeds = {}

    for _, ply in ipairs( plys ) do
        local valid, plyPos = snappedToFloor( ply:WorldSpaceCenter() )
        if valid == true then
            table.insert( extraSeeds, plyPos )

        end
    end

    if justReturn then
        return extraSeeds

    end

    for _, currentSeed in ipairs( extraSeeds ) do
        navmesh.AddWalkableSeed( currentSeed, vec_up )

    end

    local msg = "Placed " .. #extraSeeds .. " extra seeds under players."
    NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( msg )

    return extraSeeds

end

local function navAddEasyNavmeshSeeds()
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if canDoGlobalMerge ~= true then return end --don't interrupt!

    -- add seed positions for every spawnpoint
    local extraSeeds = #getComprehensiveSeedPositions()
    local msg = "Placed " .. extraSeeds .. " seed locations on unmeshed doors, teleport exits, ladder dismount points, prop_physics, and spawnpoints..."
    NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( msg )

end

local cachedPos = Vector( 0,0,0 )
local cachedContents = nil

local function posHasContent( pos, toCheck )
    local contents
    if pos == cachedPos then
        contents = cachedContents

    else
        cachedPos = pos
        contents = util.PointContents( pos )
        cachedContents = contents

    end
    local is = bit.band( contents, toCheck ) == toCheck
    return is == true

end

local slopeLimit = 0.55
local slopeLimitSeed = slopeLimit * 1.5
local incrementalRange = 6000

-- top 10 function names
local function addTrimmedSeedsAroundPointsInTableToOtherTable( seedSourceTable, tableToAddTo )
    local newSeedsAdded = 0
    local forwardAng = Angle( 0, 0, 0 )
    local checkOffsets = {}
    local countWeAddAroundAll = 35
    local angleBetweenAdded = 360 / countWeAddAroundAll

    -- spam a bunch of points around each seed
    for _ = 1, countWeAddAroundAll do
        forwardAng:RotateAroundAxis( vec_up, angleBetweenAdded )
        local rotatedDir = forwardAng:Forward()
        for index = -2, 2 do
            local dirOffsetted = rotatedDir + Vector( 0, 0, index / 5 )
            -- do seeds "far away" first, leads to less borders w/ dense areas, between generated circles
            table.insert( checkOffsets, dirOffsetted * math.Rand( 1.2, 1.5 ) )
            table.insert( checkOffsets, dirOffsetted * math.Rand( 0.45, 1.2 ) )
            table.insert( checkOffsets, dirOffsetted * math.Rand( 1, 1.2 ) )

        end
    end

    -- do the cheap filtering early
    for _, extraSeed in ipairs( seedSourceTable ) do
        for _, offset in ipairs( checkOffsets ) do
            local offsetScaled = offset * incrementalRange
            local seedPosOffsetted = extraSeed + offsetScaled
            if not util.IsInWorld( seedPosOffsetted ) then continue end
            if posHasContent( seedPosOffsetted, CONTENTS_SOLID ) then continue end
            if posHasContent( seedPosOffsetted, CONTENTS_WINDOW ) then continue end
            if posHasContent( seedPosOffsetted, CONTENTS_MONSTERCLIP ) then continue end

            local valid, seedPosFloored, tr = snappedToFloor( seedPosOffsetted )
            if not valid then continue end
            if tr.HitSky then continue end
            if tr.HitTexture == "TOOLS/TOOLSNODRAW" then continue end
            if tr.HitNormal.z < slopeLimitSeed then continue end

            local nearNav = navmesh.GetNearestNavArea( seedPosFloored, false, 1000, false, true, -2 )
            if nearNav and nearNav.IsValid and nearNav:IsValid() then
                local closestToPos = nearNav:GetClosestPointOnArea( seedPosFloored )
                closestToPos.z = seedPosFloored.z
                if seedPosFloored:Distance( closestToPos ) < 150 then continue end

            end

            if anyAreCloserThan( tableToAddTo, seedPosFloored, 150, 75 ) == true then continue end

            newSeedsAdded = newSeedsAdded + 1
            table.insert( tableToAddTo, seedPosFloored )

        end
    end

    return newSeedsAdded

end

local function doIncrementalCheapGeneration( batchSeedsPlaced, seedProgress, realSeedsCount )
    local msgGenerationProgress = "Generating batch of... " .. batchSeedsPlaced .. " seeds at SEED... " .. seedProgress .. " / " .. realSeedsCount
    NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( msgGenerationProgress )

    RunConsoleCommand( "nav_max_view_distance", "1" )
    RunConsoleCommand( "nav_generate_incremental_range", tostring( incrementalRange ) )
    RunConsoleCommand( "nav_generate_incremental" )

end

local timerName = "navoptimizer_true_incremental_generation"

local CurTime = CurTime

function superIncrementalGeneration( caller, doWorldSeeds, doPlySeeds )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end

    if canDoGlobalMerge ~= true then return end --don't interrupt!
    callerPersist = caller
    NAVOPTIMIZER_tbl.enableNavEdit( callerPersist )

    local doneSeeds = {}
    local realSeedsCount = 0
    local realSeeds = {}

    local msg = "Placing Initial Seeds..."
    NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( msg )

    if doWorldSeeds then
        -- add seed positions for every spawnpoint, door, etc
        table.Add( realSeeds, getComprehensiveSeedPositions( true ) )

    end

    if doPlySeeds then
        table.Add( realSeeds, navAddSeedsUnderPlayers( true ) )

    end

    local potentialRealSeeds = {}

    if #realSeeds > 0 then

        if IsValid( caller ) then
            -- this stops crashes!
            caller:ConCommand( "nav_draw_limit 1" )
            caller:ConCommand( "nav_quicksave 2" )
            -- this makes stairs generate better!
            caller:ConCommand( "nav_slope_limit " .. tostring( slopeLimit ) )

        else
            RunConsoleCommand( "nav_draw_limit", "1" )
            RunConsoleCommand( "nav_quicksave", "2" )
            RunConsoleCommand( "nav_slope_limit", tostring( slopeLimit ) )

        end

        msg = "Placing Extra Seeds..."
        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( msg )
        -- spam even more seeds around current seeds
        addTrimmedSeedsAroundPointsInTableToOtherTable( realSeeds, potentialRealSeeds )

    end

    msg = "Generating 'in session' with " .. realSeedsCount .. " normal seed locations, and " .. #potentialRealSeeds  .. " extras likely to be skipped...\nMesh generation is CHEAP..."
    NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( msg )

    realSeeds = table.Add( realSeeds, potentialRealSeeds )
    realSeedsCount = #realSeeds

    local startingNavareaCount = #navmesh.GetAllNavAreas()
    local generationCount = 0
    local batchSeedsPlaced = 0
    local seedProgress = 0
    local purgeSelectedSet = nil
    local blockTimerRun = 0

    timer.Create( timerName, 0.015, 0, function()
        if blockTimerRun > CurTime() then return end
        -- we are done!
        if #realSeeds <= 0 then
            -- yeet the timer
            timer.Remove( timerName )
            local msgDone = "ERROR"
            local doneType
            if seedProgress == 0 then
                msgDone = "Couldn't find any extra seed positions, looks like you're gonna have to place them!"
                doneType = 1

            elseif generationCount == 0 then
                msgDone = "DONE: All of the seeds already had navareas!"
                doneType = 2

            -- the good one
            elseif generationCount > 0 then
                local newNavAreas = math.abs( startingNavareaCount - #navmesh.GetAllNavAreas() )
                msgDone = "DONE:\nLooped over " .. seedProgress .. " seed positions.\nIncrementally generated " .. generationCount .. " of the seeds that ended up ahead of the navareas.\nWhich created " .. newNavAreas .. " new navareas!!"
                doneType = 3

                if IsValid( callerPersist ) then
                    callerPersist:EmitSound( "garrysmod/save_load4.wav" )

                end
            end
            NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( msgDone )
            printCenterTimed( msgDone, 30 )
            if IsValid( callerPersist ) then
                -- fix the command after!
                -- dont think dedicated servers need these restored
                callerPersist:ConCommand( "nav_clear_selected_set" )
                callerPersist:ConCommand( "nav_draw_limit 500" )
                callerPersist:ConCommand( "nav_quicksave 2" )

            end

            hook.Run( "navoptimizer_done_gencheapexpanded", doneType )

            return

        end

        NAVOPTIMIZER_tbl.printCenterAlias( "SEED " .. seedProgress .. " / " .. realSeedsCount )

        if navmesh.IsGenerating() then
            blockTimerRun = CurTime() + 0.1
            return

        end

        if IsValid( callerPersist ) and purgeSelectedSet then
            purgeSelectedSet = nil
            callerPersist:ConCommand( "nav_clear_selected_set" )

        end

        -- just generate the last seeds
        if batchSeedsPlaced >= 1 and #realSeeds <= 10 then
            batchSeedsPlaced = 0
            doIncrementalCheapGeneration( batchSeedsPlaced, seedProgress, realSeedsCount )
            blockTimerRun = CurTime() + 0.1
            return

        end

        local seedPos = table.remove( realSeeds, 1 )

        seedProgress = seedProgress + 1

        local tooCloseXY = 75
        local tooCloseZ = 35
        -- never, ever do spots twice!
        if anyAreCloserThan( doneSeeds, seedPos, tooCloseXY, tooCloseZ ) == true then return end

        if not util.IsInWorld( seedPos ) then return end
        if posHasContent( seedPos, CONTENTS_SOLID ) then return end
        if posHasContent( seedPos, CONTENTS_WINDOW ) then return end
        if posHasContent( seedPos, CONTENTS_MONSTERCLIP ) then return end

        local seedPosUp25 = seedPos + vec_up * 25

        local under = IsUnderDisplacementExtensive( seedPos )
        if under then return end

        local downTr = NAVOPTIMIZER_tbl.getFloorTr( seedPos )
        if downTr.HitNormal.z < slopeLimitSeed then return end

        local nearNav = navmesh.GetNearestNavArea( seedPosUp25, true, 50, true, true, -2 )
        if nearNav and nearNav.IsValid and nearNav:IsValid() then return end

        local nearNavLooseCriteria = navmesh.GetNearestNavArea( seedPosUp25, true, 150, false, false, -2 )

        -- ok so there's an area nearby
        if nearNavLooseCriteria and nearNavLooseCriteria.IsValid and nearNavLooseCriteria:IsValid() then
            local canSeeStrictDat = {
                mask = MASK_SOLID_BRUSHONLY,
                start = seedPosUp25,
                endpos = nearNavLooseCriteria:GetCenter() + ( vec_up * 25 )
            }

            local canSeeStrict = util.TraceLine( canSeeStrictDat )
            -- we can see the area! don't have to generate here.
            if not canSeeStrict.Hit then return end

        end

        -- add MORE seed positions!
        local added = addTrimmedSeedsAroundPointsInTableToOtherTable( { seedPos }, realSeeds )
        realSeedsCount = realSeedsCount + added
        local msgAdded = "Found ... " .. added .. " new SEEDS around seed ... " .. seedProgress
        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( msgAdded )

        generationCount = generationCount + 1
        local msgProgress = "Placing SEED... " .. seedProgress .. " / " .. realSeedsCount .. " for BATCH generation"
        NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( msgProgress )

        debugoverlay.Cross( seedPos, 150, 45, Color( 0,255,255 ), true )

        navmesh.AddWalkableSeed( seedPos, vec_up )
        batchSeedsPlaced = batchSeedsPlaced + 1

        -- gen 1 seed at a time when we're just starting out
        local threshSlow = ( realSeedsCount / 4 )
        -- when closer to the end, generate more seeds in one go
        local threshMedium = ( realSeedsCount / 2 )
        local batchMax = 10
        if seedProgress < threshSlow then
            batchMax = 1

        elseif seedProgress < threshMedium then
            batchMax = 4

        end

        local seedsNeededToBatch = math.Clamp( realSeedsCount / 150, 1, batchMax )
        if batchSeedsPlaced >= seedsNeededToBatch then
            doIncrementalCheapGeneration( batchSeedsPlaced, seedProgress, realSeedsCount )
            purgeSelectedSet = true
            batchSeedsPlaced = 0
            blockTimerRun = CurTime() + 0.1

        end

        table.insert( doneSeeds, seedPos )

    end )
end

-- for editing the file!
timer.Remove( timerName )

local function navGenerateCheapExpanded( caller )
    superIncrementalGeneration( caller, true, true )

end

local function navGenerateCheapPlyseeds( caller )
    superIncrementalGeneration( caller, false, true )

end


local function navMeshGlobalMerge( caller )
    if canDoGlobalMerge ~= true then return end
    callerPersist = caller
    NAVOPTIMIZER_tbl.enableNavEdit( callerPersist )
    canDoGlobalMerge = false
    doingGlobalMerge = true
    hook.Add( "Tick", "navmeshGlobalMergeStaggeredThink", NAVOPTIMIZER_tbl.navMeshGlobalMergeThink )

    mergeIndex = 0
    areasToMerge = navmesh.GetAllNavAreas()
    table.Shuffle( areasToMerge )
    areasToMergeCount = #areasToMerge

    if IsValid( callerPersist ) then
        callerPersist:ConCommand( "nav_clear_selected_set" )

    else
        RunConsoleCommand( "nav_clear_selected_set" )

    end

    globalMergeResultTime = 0
    doneMergedCount = 0
    doneMergedArea = 0

end

-- old command
local function navMeshGlobalMergeSingular( caller )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if canDoGlobalMerge ~= true then return end
    navMeshGlobalMerge( caller )
    globalMergeRepeat = false

end

-- main command
local function navMeshGlobalMergeAuto( caller )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if canDoGlobalMerge ~= true then return end
    if blockFinalAnalyze ~= true then
        local wasOriginallyCheap = getNavmeshIsCheap()
        if wasOriginallyCheap and forceExpensiveMerge == false then -- force a cheap nav_analyze?
            generateCheapNavmesh = true
            NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Originally cheap navmesh detected. Will nav_analyze cheap... \nnavmesh_override_expensive to override." )
        elseif wasOriginallyCheap and forceExpensiveMerge == true then
            NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Forcing expensive nav_analyze..." )
        end
    end
    navMeshGlobalMerge( caller )
    globalMergeRepeat = true
    initialRepeatCount = #navmesh.GetAllNavAreas()
end

local function navMeshGlobalMergeAutoNoAnalyze( caller )
    blockFinalAnalyze = true
    navMeshGlobalMergeAuto( caller )
end


local function navmeshExpensiveToggle()
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    forceExpensiveMerge = not forceExpensiveMerge
    local msg = ""
    if forceExpensiveMerge == true then
        msg = "navmesh_globalmerge_auto will now force an expensive nav_analyze"
    elseif forceExpensiveMerge == false then
        msg = "navmesh_globalmerge_auto will NOT force an expensive nav_analyze"
    end
    NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( msg )

end

local function navmeshIsCheapCommand()
    local isCheap = getNavmeshIsCheap()
    local message = ""
    if isCheap == true then
        message = "This navmesh is cheap!"
    elseif isCheap == false then
        message = "This navmesh is expensive!"
    end
    NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( message )
end

-- fixes some extreme lag?
local nextPrint = 0

local function navMeshGlobalMergePrintResults()
    -- spaghetti

    if not doMessageThink then hook.Remove( "Tick", "navmeshGlobalMergePrintResults" ) return end

    if nextPrint > CurTime() then return end
    nextPrint = CurTime() + 0.1

    if doingRepeatMergedMessage > CurTime() then
        local time = math.abs( doingRepeatMergedMessage - CurTime() )
        time = math.Round( time, 1 )
        local analyzeWarning = ""
        if not blockFinalAnalyze then
            if generateCheapNavmesh == true and forceExpensiveMerge == false then
                analyzeWarning = "\nA final, CHEAP nav_analyze to save the optimisations, fix the hiding spots, crouch areas, etc. Will begin in " .. time .. "\nnavmesh_override_expensive to force an expensive nav_analyze"
            else
                analyzeWarning = "\nA final nav_analyze to save the optimisations, fix the hiding spots, crouch areas, visibility checks, etc. Will begin in " .. time
            end
        else
            analyzeWarning = "\nConsider nav_save(ing) your progress?"
        end
        NAVOPTIMIZER_tbl.printCenterAlias( "Completed " .. repeatMergedCount .. " merges\nThe navarea count has gone from " .. initialRepeatCount .. " to " .. #navmesh.GetAllNavAreas() .. analyzeWarning )

    elseif analyzing then
        local DOTS = {}
        for ind = 1, math.random( 1, 4 ) do
            DOTS[ind] = "."
        end
        NAVOPTIMIZER_tbl.printCenterAlias( "The navmesh is being analyzed" .. table.concat( DOTS, "" ) )

        return
    end

    if not doingGlobalMerge and globalMergeResultTime > CurTime() then -- mt everest
        local CONGRATS = ""
        if doneMergedCount == 0 then
            CONGRATS = "Your navmesh is optimized, Congragulations"
            if not congragulated then
                for _, ply in ipairs( player.GetAll() ) do
                    ply:EmitSound( "garrysmod/save_load4.wav" )
                    congragulated = true

                end
            end
        end
        local message = "Merged " .. doneMergedCount .. " areas.\nTotal merged surface area: " .. math.Round( doneMergedArea ) .. " square hu\n" .. CONGRATS
        NAVOPTIMIZER_tbl.printCenterAlias( message )

    end
end

local function finishGlobalMerge( type )
    hook.Run( "navoptimizer_done_globalmerge", type )
    hook.Add( "Tick", "navmeshGlobalMergePrintResults", navMeshGlobalMergePrintResults )
    hook.Remove( "Tick", "navmeshGlobalMergeStaggeredThink" )

end

-- this function is so spaghetti that an italian would think it is above spaghetti, beyond spaghetti, something, something else....
function NAVOPTIMIZER_tbl.navMeshGlobalMergeThink()
    if not SERVER then return end
    if doingGlobalMerge ~= true then return end
    local done = nil

    -- go through the list faster when we're not merging anything
    local operationsCount = 6
    if operationsWithoutMerges >= 20 then
        -- lags the editor when you merge fast on big maps 
        operationsCount = math.Round( math.Clamp( #areasToMerge / 50, 100, 1000 ) )
    elseif operationsWithoutMerges >= 10 then
        operationsCount = 200
    elseif operationsWithoutMerges >= 4 then
        operationsCount = 80
    elseif operationsWithoutMerges >= 2 then
        operationsCount = 25
    end
    operationsWithoutMerges = operationsWithoutMerges + 1

    -- no coroutine????
    for areaIndex = mergeIndex, mergeIndex + operationsCount do
        local curr = areasToMerge[areaIndex]
        if areaIndex > #areasToMerge then
            done = true
            break
        elseif curr and curr:IsValid() then
            local validMerge, newSurfaceArea, _ = navmeshAutoAttemptMerge( curr )
            if validMerge == true then
                doneMergedCount = doneMergedCount + 1
                doneMergedArea = doneMergedArea + newSurfaceArea
                operationsWithoutMerges = 0
            end
        end
    end
    if not done then
        NAVOPTIMIZER_tbl.printCenterAlias( mergeIndex .. " / " .. areasToMergeCount )
        mergeIndex = mergeIndex + operationsCount

    elseif done then
        canDoGlobalMerge = true
        doingGlobalMerge = false
        if IsValid( callerPersist ) then
            callerPersist:ConCommand( "nav_compress_id" )
            callerPersist:ConCommand( "nav_check_stairs" )

        else
            RunConsoleCommand( "nav_compress_id" )
            RunConsoleCommand( "nav_check_stairs" )

        end

        -- doing a repeating one
        if globalMergeRepeat == true then
            -- merge was done this loop, keep merging
            if doneMergedCount > 0 then
                repeatMergedCount = repeatMergedCount + doneMergedCount
                repeatMergedArea = repeatMergedArea + doneMergedArea
                navMeshGlobalMerge( callerPersist )
            -- no merges were done this loop, and we're not on the first loop, call it validated as done!
            elseif repeatMergedCount > 0 then
                if IsValid( callerPersist ) then
                    callerPersist:EmitSound( "garrysmod/save_load4.wav" )

                end
                doingRepeatMergedMessage = CurTime() + 15
                doMessageThink = true
                if not blockFinalAnalyze then
                    analyzing = true
                    timer.Simple( 15, function()
                        if IsValid( callerPersist ) then
                            --don't ask people to do vis calculations on maps that didn't have them in the first place!
                            if generateCheapNavmesh == true and forceExpensiveMerge == false then
                                NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Analyzing cheap!" )
                                callerPersist:ConCommand( "nav_max_view_distance 1" )
                            else
                                callerPersist:ConCommand( "nav_max_view_distance " .. tostring( expensiveVisDist ) ) --cheat a bit to make this faster
                            end
                            callerPersist:ConCommand( "nav_analyze" )
                            timer.Simple( 0, function()
                                NAVOPTIMIZER_tbl.disableNavEdit( callerPersist )
                            end )
                        elseif game.IsDedicated() then
                            if generateCheapNavmesh == true and forceExpensiveMerge == false then
                                NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Analyzing cheap!" )
                                RunConsoleCommand( "nav_max_view_distance", "1" )
                            else
                                RunConsoleCommand( "nav_max_view_distance", tostring( expensiveVisDist ) )
                            end
                            RunConsoleCommand( "nav_analyze" )
                            timer.Simple( 0, function()
                                NAVOPTIMIZER_tbl.disableNavEdit( callerPersist )
                            end )
                        end
                        doingRepeatMergedMessage = 0
                    end )
                else
                    NAVOPTIMIZER_tbl.disableNavEdit( callerPersist )
                end
                finishGlobalMerge( 1 )
            -- 0 total merged areas, command did nothing.
            elseif repeatMergedCount == 0 then
                doMessageThink = true
                congragulated = true
                globalMergeResultTime = CurTime() + 15
                NAVOPTIMIZER_tbl.disableNavEdit( callerPersist )
                finishGlobalMerge( 2 )
            end
        -- one-loop merge, will probably deprecate this
        else
            doMessageThink = true
            congragulated = nil
            globalMergeResultTime = CurTime() + 15
            NAVOPTIMIZER_tbl.disableNavEdit( callerPersist )
            finishGlobalMerge( 3 )

        end
    end
end

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

    local bigLength = 80
    -- be more aggressive if area is a trash underwater one
    if area:IsUnderwater() then
        bigLength = 140

    end

    if biggestLength > bigLength then return end

    local adjAreas = area:GetAdjacentAreas()
    if #adjAreas <= 3 then return end

    if not areaIsEntirelyOverDisplacements( area ) then return end

    area:Remove()

    return true

end

local navmeshRemoveSmallAreasOnDisplacements = nil
local navmeshRemoveSmallAreasOnDisplacementsCor = nil

local function navmeshStartDisplacementTrim( caller )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    if canDoGlobalMerge ~= true then return end --don't interrupt!
    callerPersist = caller
    NAVOPTIMIZER_tbl.enableNavEdit( callerPersist )

    NAVOPTIMIZER_tbl.sendAsNavmeshOptimizer( "Removing small areas with more than 3 neighbors on displacements!" )
    canDoGlobalMerge = false
    navmeshRemoveSmallAreasOnDisplacements = true

end

local function thinkHookNavmeshTrim()
    if not navmeshRemoveSmallAreasOnDisplacements then return end
    if not navmeshRemoveSmallAreasOnDisplacementsCor then -- create coroutine
        local theFunc = function()
            local removedCount = 0
            local allAreas = navmesh.GetAllNavAreas()
            local allAreaCount = #allAreas
            for progress, area in ipairs( allAreas ) do
                coroutine.yield()

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
        while math.abs( oldTime - SysTime() ) < 0.0005 do
            local noErrors, result = coroutine.resume( navmeshRemoveSmallAreasOnDisplacementsCor )
            if noErrors == false then
                ErrorNoHaltWithStack( result )

            elseif result == "done" then
                navmeshRemoveSmallAreasOnDisplacements = nil
                navmeshRemoveSmallAreasOnDisplacementsCor = nil
                canDoGlobalMerge = true
                break

            end
        end
    end
end

hook.Add( "Tick", "navmeshRemoveSmallAreasOnDisplacements", thinkHookNavmeshTrim )


concommand.Add( "nav_mark_walkble_auto", navAddEasyNavmeshSeeds, nil, "Clone of navmesh_mark_walkble_auto. Uses every player spawnpoint, door, ladder dismount point, prop_physics, and teleport exit on the map as a navmesh seed.", FCVAR_NONE )
concommand.Add( "navmesh_mark_walkble_auto", navAddEasyNavmeshSeeds, nil, "Uses every player spawnpoint, door, ladder dismount point, prop_physics, and teleport exit on the map as a navmesh seed.", FCVAR_NONE )

concommand.Add( "nav_mark_walkble_allplayers", function() navAddSeedsUnderPlayers() end, nil, "Clone of navmesh_mark_walkble_allplayers. Places a navmesh seed under every player. For doing custom navmesh seeds on dedicated servers.", FCVAR_NONE )
concommand.Add( "navmesh_mark_walkble_allplayers", function() navAddSeedsUnderPlayers() end, nil, "Places a navmesh seed under every player. For doing custom navmesh seeds on dedicated servers.", FCVAR_NONE )

-- same but it generates at 1 visibilty distance, 10mb nav filesize vs 300mb....
-- wow the nav_analyze at the end doesn't restart the session!!?!?!
concommand.Add( "nav_generate_cheap_expanded", navGenerateCheapExpanded, nil, "Incrementally generates a navmesh, dynamically places seed locations in walkable areas across the map. Navareas will cover the entire map, skybox, rooftops, inacessible areas, basically a 'nuclear option'.", FCVAR_NONE )
concommand.Add( "navmesh_generate_cheap_expanded", navGenerateCheapExpanded, nil, "Clone of nav_generate_cheap_expanded.", FCVAR_NONE )

concommand.Add( "nav_generate_cheap_plyseeds", navGenerateCheapPlyseeds, nil, "Clone of nav_generate_cheap_expanded. Inital seeds are only placed under players.", FCVAR_NONE )
concommand.Add( "navmesh_generate_cheap_plyseeds", navGenerateCheapPlyseeds, nil, "Clone of nav_generate_cheap_plyseeds.", FCVAR_NONE )


concommand.Add( "navmesh_trim_displacement_areas", navmeshStartDisplacementTrim, nil, "Removes small, 'redundant' areas on top of displacements", FCVAR_NONE )

concommand.Add( "navmesh_ischeap", navmeshIsCheapCommand, nil, "Was this navmesh generated without visibility data?", FCVAR_NONE )

concommand.Add( "navmesh_globalmerge_auto", navMeshGlobalMergeAuto, nil, "Automatically merges every possible area, then rebuilds the visibility/hiding spot stuff.", FCVAR_NONE )
concommand.Add( "navmesh_globalmerge_auto_noanalyze", navMeshGlobalMergeAutoNoAnalyze, nil, "Doesn't nav_analyze at the end.", FCVAR_NONE )
concommand.Add( "navmesh_override_expensive", navmeshExpensiveToggle, nil, "Toggle forced expensive nav_analyze", FCVAR_NONE )

concommand.Add( "navmesh_globalmerge_singular", navMeshGlobalMergeSingular, nil, "Performs a singular merging pass.", FCVAR_NONE )