-- ======================================================================
-- Copyright (c) 2012 RapidFire Studio Limited 
-- All Rights Reserved. 
-- http://www.rapidfirestudio.com

-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:

-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
-- IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
-- CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
-- TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
-- SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-- ======================================================================


--modified by Bruno https://discourse.stonehearth.net/users/BrunoSupremo
--original at https://github.com/lattejed/a-star-lua


local Astar = {}

----------------------------------------------------------------
-- local variables
----------------------------------------------------------------

local INF = 1/0
local cachedPaths = nil

----------------------------------------------------------------
-- local functions
----------------------------------------------------------------

function Astar.dist ( x1, y1, x2, y2 )
	
	return (x2 - x1)*(x2 - x1) + (y2 - y1)*(y2 - y1)
end

function Astar.dist_between ( nodeA, nodeB )

	return Astar.dist ( nodeA.x, nodeA.y, nodeB.x, nodeB.y )
end

function Astar.heuristic_cost_estimate ( nodeA, nodeB )

	return Astar.dist ( nodeA.x, nodeA.y, nodeB.x, nodeB.y ) * nodeA.noise
end

function Astar.lowest_f_score ( set, f_score )

	local lowest, bestNode = INF, nil
	for _, node in ipairs ( set ) do
		local score = f_score [ node ]
		if score < lowest then
			lowest, bestNode = score, node
		end
	end
	return bestNode
end

function Astar.neighbor_nodes ( theNode, nodes )

	local offset = (theNode.y-1)*nodes.width+theNode.x
	local neighbors = {}

	if theNode.x>1 and nodes[offset-1].plains then
		table.insert ( neighbors, nodes[offset-1] )
	end
	if theNode.x<nodes.width and nodes[offset+1].plains then
		table.insert ( neighbors, nodes[offset+1] )
	end
	if theNode.y>1 and nodes[offset-nodes.width].plains then
		table.insert ( neighbors, nodes[offset-nodes.width] )
	end
	if theNode.y<nodes.height and nodes[offset+nodes.width].plains then
		table.insert ( neighbors, nodes[offset+nodes.width] )
	end

	return neighbors
end

function Astar.not_in ( set, theNode )

	for _, node in ipairs ( set ) do
		if node == theNode then return false end
	end
	return true
end

function Astar.remove_node ( set, theNode )

	for i, node in ipairs ( set ) do
		if node == theNode then 
			set [ i ] = set [ #set ]
			set [ #set ] = nil
			break
		end
	end	
end

function Astar.unwind_path ( flat_path, map, current_node )

	if map [ current_node ] then
		table.insert ( flat_path, 1, map [ current_node ] ) 
		return Astar.unwind_path ( flat_path, map, map [ current_node ] )
	else
		return flat_path
	end
end

----------------------------------------------------------------
-- pathfinding functions
----------------------------------------------------------------

function Astar.a_star ( start, goal, nodes )

	local closedset = {}
	local openset = { start }
	local came_from = {}

	local g_score, f_score = {}, {}
	g_score [ start ] = 0
	f_score [ start ] = g_score [ start ] + Astar.heuristic_cost_estimate ( start, goal )

	local counter = 0
	while #openset > 0 do

		counter = counter+1
		if counter >10000 then
			break
		end
	
		local current = Astar.lowest_f_score ( openset, f_score )
		if current == goal then
			local path = Astar.unwind_path ( {}, came_from, goal )
			table.insert ( path, goal )
			return path
		end

		Astar.remove_node ( openset, current )		
		table.insert ( closedset, current )
		
		local neighbors = Astar.neighbor_nodes ( current, nodes )
		for _, neighbor in ipairs ( neighbors ) do 
			if Astar.not_in ( closedset, neighbor ) then
			
				local tentative_g_score = g_score [ current ] + Astar.dist_between ( current, neighbor )
				 
				if Astar.not_in ( openset, neighbor ) or tentative_g_score < g_score [ neighbor ] then 
					came_from 	[ neighbor ] = current
					g_score 	[ neighbor ] = tentative_g_score
					f_score 	[ neighbor ] = g_score [ neighbor ] + Astar.heuristic_cost_estimate ( neighbor, goal )
					if Astar.not_in ( openset, neighbor ) then
						table.insert ( openset, neighbor )
					end
				end
			end
		end
	end
	return nil -- no valid path
end

----------------------------------------------------------------
-- exposed functions
----------------------------------------------------------------

function Astar.clear_cached_paths ()

	cachedPaths = nil
end

function Astar.distance ( x1, y1, x2, y2 )
	
	return Astar.dist ( x1, y1, x2, y2 )
end

function Astar.path ( start, goal, nodes, ignore_cache )

	if not cachedPaths then cachedPaths = {} end
	if not cachedPaths [ start ] then
		cachedPaths [ start ] = {}
	elseif cachedPaths [ start ] [ goal ] and not ignore_cache then
		return cachedPaths [ start ] [ goal ]
	end
	
	return Astar.a_star ( start, goal, nodes )
end

return Astar