
local grid_utils = {}


-- -------------------------------------------------------------------------
-- GRID HW IDENTIFICATION

grid_utils.nb_levels = function(g)
  if g.name == 'monome 64 m64-0536' then
    return 1
  else
    return 15
  end
end


-- -------------------------------------------------------------------------

return grid_utils
