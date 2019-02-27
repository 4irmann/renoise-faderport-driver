--[[-------------------------------------------------------
  
  FaderPort helper functions
  
  Taken from GlobalMidiActions.lua, Author: taktik 
  
---------------------------------------------------------]]

function song()
  return renoise.song()
end

function clamp_value(value, min_value, max_value)
  return math.min(max_value, math.max(value, min_value))
end

function wrap_value(value, min_value, max_value)
  local range = max_value - min_value + 1
  assert(range > 0, "invalid range")

  while value < min_value do
    value = value + range
  end

  while value > max_value do
    value = value - range
  end

  return value
end

function quantize_value(value, quantum)
  if value >= 0 then
     value = value + quantum / 2
  else
     value = value - quantum / 2
  end

  return math.floor(value / quantum) * quantum
end

