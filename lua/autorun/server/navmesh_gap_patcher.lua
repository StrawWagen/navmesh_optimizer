
-- experimental

local vertOffset = Vector( 0, 0, 25 )
local vector_up = Vector( 0, 0, 1 )
local hullMax = Vector( 10, 10, 2 )
local hullMin = -hullMax

local function getAreasToPatchBetween( pathwayPos, dirOffset )
    local area1Pos = pathwayPos + -dirOffset
    local area2Pos = pathwayPos + dirOffset

    debugoverlay.Line( pathwayPos + vertOffset, area1Pos + vertOffset, 0.25, color_white, true )
    debugoverlay.Line( pathwayPos + vertOffset, area2Pos + vertOffset, 0.25, color_white, true )

    local area1 = NAVOPTIMIZER_tbl.getNearestNav( area1Pos, 1000 )
    local area2 = NAVOPTIMIZER_tbl.getNearestNav( area2Pos, 1000 )

    if not ( area1 and area1.IsValid and area1:IsValid() ) or not ( area2 and area2.IsValid and area2:IsValid() ) then return end
    if area1 == area2 then return end

    local area1sCenter = area1:GetCenter()
    local area2sNearest = area2:GetClosestPointOnArea( area1sCenter )
    local area1sNearest = area1:GetClosestPointOnArea( area2sNearest )
    area2sNearest = area2:GetClosestPointOnArea( area1sNearest )

    local bestZ = math.max( area1sNearest.z, area2sNearest.z )

    area1sNearest.z = bestZ
    area2sNearest.z = bestZ

    local subtProduct = area1sNearest - area2sNearest
    local onX = math.abs( subtProduct.x ) > math.abs( subtProduct.y )
    local onY = math.abs( subtProduct.x ) < math.abs( subtProduct.y )

    local averagePos = ( area1sNearest + area2sNearest ) / 2

    local dirOffsetButLeft = dirOffset:Cross( vector_up )
    local dirOffsetButRight = dirOffset:Cross( -vector_up )

    local dist = area1sNearest:Distance( area2sNearest )

    local sizeMax = Vector( dist / 2, dist / 2, 0 )
    local sizeMin = -sizeMax

    averagePos.z = pathwayPos.z

    if onX then
        averagePos.y = pathwayPos.y

    elseif onY then
        averagePos.x = pathwayPos.x

    end

    local traceStructLeft = {
        start = averagePos + vertOffset,
        endpos = averagePos + vertOffset + dirOffsetButLeft * 100,
        mins = hullMin,
        maxs = hullMax,
        mask = MASK_SOLID_BRUSHONLY,
    }
    local traceLeft = util.TraceHull( traceStructLeft )

    local traceStructRight = {
        start = averagePos + vertOffset,
        endpos = averagePos + vertOffset + dirOffsetButRight * 100,
        mins = hullMin,
        maxs = hullMax,
        mask = MASK_SOLID_BRUSHONLY,
    }
    local traceRight = util.TraceHull( traceStructRight )

    debugoverlay.Line( traceStructLeft.start, traceLeft.HitPos, 1, color_white, true )
    debugoverlay.Line( traceStructRight.start, traceRight.HitPos, 1, color_white, true )


    local yMax = math.huge
    local yMin = -math.huge

    local xMax = math.huge
    local xMin = -math.huge

    if onX then
        yMax = math.max( traceLeft.HitPos.y, traceRight.HitPos.y )
        yMin = math.min( traceLeft.HitPos.y, traceRight.HitPos.y )

    elseif onY then
        xMax = math.max( traceLeft.HitPos.x, traceRight.HitPos.x )
        xMin = math.min( traceLeft.HitPos.x, traceRight.HitPos.x )

    end

    local corner1 = averagePos + sizeMin
    local corner2 = averagePos + sizeMax

    debugoverlay.Cross( corner1, 4, 0.25, color_white, true )
    debugoverlay.Cross( corner2, 4, 0.25, color_white, true )

    corner1.x = math.Clamp( corner1.x, xMin, xMax )
    corner1.y = math.Clamp( corner1.y, yMin, yMax )

    corner2.x = math.Clamp( corner2.x, xMin, xMax )
    corner2.y = math.Clamp( corner2.y, yMin, yMax )

    debugoverlay.Cross( corner1, 8, 0.25, color_white, true )
    debugoverlay.Cross( corner2, 8, 0.25, color_white, true )

    debugoverlay.Line( area1sNearest, area2sNearest, 0.25, color_white, true )

    if math.abs( corner1.x - corner2.x ) < 5 then return end
    if math.abs( corner1.y - corner2.y ) < 5 then return end

    return true, corner1, corner2, area1, area2

end

local function patchBetweenAreas( pathwayPos, dirOffset )
    local valid, corner1, corner2, area1, area2 = getAreasToPatchBetween( pathwayPos, dirOffset )

    if not valid then return end

    local newArea = navmesh.CreateNavArea( corner1, corner2 )

    print( newArea, corner1, corner2 )

    newArea:ConnectTo( area1 )
    newArea:ConnectTo( area2 )
    area1:ConnectTo( newArea )
    area2:ConnectTo( newArea )

    local areasHull = Vector( newArea:GetSizeX() / 2, newArea:GetSizeY() / 2, 0.5 )

    local shouldCrouchTr = {
        start = newArea:GetCenter() + vector_up * 8,
        endpos = newArea:GetCenter() + vector_up * 68,
        mins = -areasHull,
        maxs = areasHull,
        mask = MASK_NPCSOLID_BRUSHONLY,
    }

    local result = util.TraceHull( shouldCrouchTr )

    if result.Hit then newArea:SetAttributes( NAV_MESH_CROUCH ) end

    return true

end

local function patchGapCommand( caller )
    if NAVOPTIMIZER_tbl.isNotCheats() then return end
    local timerName = "navopti_gappatch_" .. caller:GetCreationID()
    if not caller.navopti_DoingGapPatch then
        caller.navopti_DoingGapPatch = true
        caller.patchingOriginPos = caller:GetEyeTrace().HitPos
        timer.Create( timerName, 0, 0, function()
            local currAimPos = caller:GetEyeTrace().HitPos
            currAimPos.z = caller.patchingOriginPos.z
            local subtractionProduct = currAimPos - caller.patchingOriginPos
            local dir = subtractionProduct:GetNormalized()
            local dist = subtractionProduct:Length()
            if dist < 5 then return end
            local valid = getAreasToPatchBetween( caller.patchingOriginPos, dir * dist )

            if not valid then return end

            local patched = patchBetweenAreas( caller.patchingOriginPos, dir * dist )
            if not patched then return end

            caller.navopti_DoingGapPatch = nil
            timer.Remove( timerName )

        end )
    else
        caller.navopti_DoingGapPatch = nil
        timer.Remove( timerName )

    end
end

concommand.Add( "navmesh_patch_gap", patchGapCommand, nil, "Create navareas that dynamically patch gaps.", FCVAR_NONE )