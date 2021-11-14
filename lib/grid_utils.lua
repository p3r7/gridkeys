
local grid_utils = {}


-- -------------------------------------------------------------------------
-- GRID HW IDENTIFICATION

grid_utils.nb_levels = function(g)
  if util.string_starts(g.name, 'monome 64 m64')
    or util.string_starts(g.name, 'monome 128 m128')
    or util.string_starts(g.name, 'monome 256 m256') then
    return 1
  else
    return 15
  end
end


-- -------------------------------------------------------------------------

return grid_utils
