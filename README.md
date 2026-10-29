# navmesh_optimizer
Advanced toolset for building, modifying Source Navmeshes in Garry's Mod.  
Optimises navmeshes by finding and merging neighbouring areas, on big maps this can mean tens of thousands of areas merged.  
Using this tool on some maps can decrease pathing call costs by up to 50%, expect an area count reduction of 20-50%.  
Also includes a fast "nuclear option" navmesh generator, ladder builders, and a bunch of cleanup tools.

Designed to be added to live servers, won't run anything in the background.  
Every command requires `sv_cheats 1`.

See [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=2878197619) page for more info.  
Check [Hunter's Glee](https://github.com/StrawWagen/hunters_glee)
    (Gamemode that makes heavy use of this)

## Quick Start
Optimise a navmesh,
```
navmesh_globalmerge_auto
```
Merges every possible area, then runs a `nav_analyze` to rebuild the visibility data the merges threw away.  
When the analyze finishes, the navmesh saves and the session restarts. After that, it's ready to share.

Generate a navmesh from scratch,
```
nav_generate_cheap_expanded
```

## Commands
Most `nav_` commands have a `navmesh_` clone, eg `nav_generate_cheap` and `navmesh_generate_cheap`.
```

Merging
navmesh_globalmerge_auto "Merges every possible area, then nav_analyzes, saves, and restarts the session."
navmesh_globalmerge_auto_noanalyze "Same as above, but doesn't nav_analyze at the end."
navmesh_override_expensive "Toggle. Forces globalmerge_auto to do an expensive nav_analyze, even on cheap navmeshes."

Generation
nav_generate_cheap "Just nav_generate, places seeds first, skips the expensive visibility data. ~10mb navs vs ~300mb."
nav_generate_cheap_expanded "Incrementally generates a navmesh, dynamically placing seeds in walkable areas across the map. Covers everything, rooftops, inaccessible areas, sometimes the skybox. The 'nuclear option'."
nav_generate_cheap_plyseeds "Same as above, but initial seeds are only placed under players."
nav_generate_cheap_here <radius> "Cheap incremental generation around you, doesn't generate the entire map. Default radius 3000."
navmesh_ischeap "Was this navmesh generated without visibility data?"

Seeds
nav_mark_walkble_auto "Places seeds under every spawnpoint, door, ladder dismount point, prop_physics, and teleport exit."
nav_mark_walkble_allplayers "Places a seed under every player. nav_mark_walkable doesn't work on dedicated servers."

Trimming / Deleting
navmesh_trim_displacement_areas "Removes small, 'redundant' areas on displacements. Best used after globalmerge."
navmesh_trim_deepunderwater_areas "Removes areas under deep water. Default >350 units deep."
navmesh_delete_isolated_smallareas <N> "Deletes areas smaller than NxN (default 50) with zero connections."
navmesh_delete_areasonmat <substring> "Deletes areas resting entirely on textures containing the substring."
navmesh_delete_nodrawareas "Deletes areas resting entirely on toolsnodraw."
navmesh_delete_skyboxareas "Removes areas in the skybox, can be imperfect."
navmesh_delete_allareas "Removes ALL areas."

Corruption
navmesh_iscorrupt "Is the navmesh 'corrupt'? eg, generated on a different map that shares this one's name."
navmesh_delete_corruptareas <radius> "Removes corrupt areas closer than radius to you. 0 for mapwide, default 2000."
navmesh_highlight_corruptareas <radius> "Highlights corrupt areas, needs developer 1. 0 for mapwide, default 2000."
navmesh_teleportto_corruptarea "Teleports you to a random corrupt area."
navmesh_teleportto_blockedarea "Teleports you to a random blocked area."

Ladders, func_useableladder
navmesh_ladderusable_build "Creates a nav ladder on the nearest func_useableladder."
navmesh_ladderusable_buildmanual_snap "Same as above, but you place the top/bottom heights manually."
navmesh_ladderusable_showall "Highlights every func_useableladder, needs developer 1."
navmesh_ladderusable_tp "Teleports you to an un-navmeshed func_useableladder."

Ladders, func_ladder brushes
navmesh_ladderbrush_buildmanual_snap "Creates a nav ladder on the nearest func_ladder brush, on the side you're standing on. Place bottom, then top."
navmesh_ladderbrush_showall "Highlights every func_ladder brush, needs developer 1. Green = no nav ladder yet."
navmesh_ladderbrush_tp "Teleports you to an un-navmeshed func_ladder brush. Needs noclip."

Ladders, anywhere
navmesh_ladder_buildmanual "Creates a nav ladder anywhere, place bottom, then top."
```

## Convars
```
navoptimizer_blockprintcenters 0/1 "Block center-screen progress messages?"
navoptimizer_blockprintconsole 0/1 "Block console progress messages?"
```

## Lua API
Server only.
```lua
isCheap = getNavmeshIsCheap()
-- true if the navmesh was generated without visibility data

isCorrupt, corruptedRatio, corruptedAreas = navmeshIsCorrupted()
-- true if >15% of areas are outside the playable space, or high up off the ground

validMerge, mergedSurfaceArea, createdArea = navmeshAttemptMerge( area1, area2 )
-- can crash sessions if nextbots are pathing while this runs

validMerge, mergedSurfaceArea, createdArea = navmeshAutoAttemptMerge( navArea )
-- navmeshAttemptMerge between navArea and each of its neighbours
```

## Hooks
Ran when commands finish.
```
navoptimizer_done_globalmerge( type ) -- 1 = merged, 2 = already optimized
navoptimizer_done_gencheap
navoptimizer_done_gencheapexpanded( doneType )
navoptimizer_done_gencheaphere
navoptimizer_done_removingareas
navoptimizer_done_removingareasonmat
navoptimizer_done_removingnodrawareas
navoptimizer_done_removingskyboxareas
navoptimizer_done_removingcorruptareas
navoptimizer_done_removingisolatedsmallareas
```

Seed position hooks, for changing where generation starts.  
Examples are next to each hook in [navmesh_merger.lua](lua/autorun/server/navmesh_merger.lua).
```lua
-- add/replace the entity classes seeds are placed under
hook.Add( "navoptimizer_addclassesusuallyinsidethemap", "myaddon", function( theClasses )
    table.insert( theClasses, "player" )

end )

hook.Add( "navoptimizer_replaceclassesusuallyinsidethemap", "myaddon", function( theClasses )
    return true, { "player" }

end )

-- handle a seed entity yourself, return true, checkDist, zTolerance
navoptimizer_handlepotentialseedclass( seedEnt )

-- modify the final seed positions table
navoptimizer_comprehensiveseedpositions_postbuilt( donePositions )
```
