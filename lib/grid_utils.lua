
local grid_utils = {}


-- -------------------------------------------------------------------------
-- valid

function grid_utils.valid(g)
  return ( g and g.name ~= 'none' )
end


-- -------------------------------------------------------------------------
-- grid hw identification

function grid_utils.shortname(g)
  if not g.name then
    return 'nil'
  end

  if util.string_starts(g.name, 'monome ') then
    return (g.name):sub(#'monome ' + 1)
  elseif util.string_starts(g.name, 'neo-monome ') then
    return 'neo ' .. (g.name):sub(#'neo-monome ' + 1)
  else
    return g.name
  end
end

function grid_utils.nb_levels(g)
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
