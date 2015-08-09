require "config"

local nixie_map = {}
local mod_version="0.1.0"

---[[
local function print(...)
  return game.player.print(...)
end
--]]

--swap comment to toggle debug prints
--local function debug() end
local debug = print

function trace_nixies()
  debug("tracing nixie positions")
  for k,v in pairs(nixie_map) do
    str=k.." = { "
    for k2,v2 in pairs(v) do
      str=str..k2
    end
    str=str.."}"
    debug(str)
  end
end

local function getDescAtPos(pos)
  local res=nil
  debug("checking for dude at "..pos.x..","..pos.y)
  if nixie_map[pos.y] then
    res=nixie_map[pos.y][pos.x]
  end
  return res
end

local function removeSpriteObj(nixie_desc)
  if nixie_desc and nixie_desc.spriteobj and nixie_desc.spriteobj.valid then
    nixie_desc.spriteobj.clear_items_inside()
    nixie_desc.spriteobj.destroy()
  end
end

--12 frames for the light, so a step is 1/12...
local step=1/12
--build LuT to convert states into orientation values.
local stateOrientMap = {
  ["off"]=step*0,
  ["0"]=step*1,
  ["1"]=step*2,
  ["2"]=step*3,
  ["3"]=step*4,
  ["4"]=step*5,
  ["5"]=step*6,
  ["6"]=step*7,
  ["7"]=step*8,
  ["8"]=step*9,
  ["9"]=step*10,
  ["all"]=step*11,
}

--sets the state, for now destroying and replacing the spriteobj if necessary
local function setState(nixie_desc,newstate)
  if newstate==nixie_desc.state then
    return
  end

  nixie_desc.spriteobj.orientation=stateOrientMap[newstate]

  debug("state changed to "..newstate)
  debug("and nixie is "..(nixie_desc.spriteobj==nil and "nil" or "NOT nill"))
  nixie_desc.state=newstate
end

local function deduceSignalValue(entity)
  local t=2^31
  local v=0

  local condition=entity.get_circuit_condition(1)
  if condition.condition.first_signal.name==nil then
    --no signal selected, so can't do anything
    return nil
  end
  if condition.condition.comparator=="=" and condition.fulfilled then
    --we leave the condition set to "= constant" where the constant is the deduced value; if
    --it's still so set, and still true, we can just return the constant.
    return condition.condition.constant
  end
  condition.condition.comparator="<"
  while t~=1 do
    condition.condition.constant=v
    entity.set_circuit_condition(1,condition)
    t=t/2
    if entity.get_circuit_condition(1).fulfilled==true then
      v=v-t
    else
      v=v+t
    end
  end
  condition.condition.constant=v
  entity.set_circuit_condition(1,condition)
  if entity.get_circuit_condition(1).fulfilled then
    --is still true, so value is still 1 less than v
    v=v-1
  end
  --set the state to = v, so we can quickly test out true if it hasn't changed
  condition.condition.constant=v
  condition.condition.comparator="="
  entity.set_circuit_condition(1,condition)
  return v
end

function onSave()
  global.nixie_tubes={nixies=nixie_map, version=mod_version}
  --copy and clean up the table, removing empty rows
end



function onLoad()

  if not global.nixie_tubes then
    global.nixie_tubes={
        nixies={},
        version=mod_version,
      }
  end

  nixie_map=global.nixie_tubes.nixies
end

local function onPlaceEntity(event)
  local entity=event.created_entity
  if entity.name=="nixie-tube-sprite" then
    local desc={}
    debug("placing")
    entity.insert({name="coal",count=1})
    --place the /real/ thing at same spot
    local pos=entity.position
    local nixie=game.surfaces.nauvis.create_entity({name="nixie-tube",position=pos,force=game.forces.neutral})
    --set me to look up the current entity from the interactive one
    if not nixie_map[nixie.position.y] then
      nixie_map[nixie.position.y]={}
    end
    debug("sprite pos = "..pos.x..","..pos.y)
    debug("nixie pos = "..nixie.position.x..","..nixie.position.y)
    local desc={
          pos=nixie.position,
          state="off",
          entity=nixie,
          spriteobj=entity,
       }
    trace_nixies()

    --check for a neighbor on the right - he will be my master!
    desc.master=getDescAtPos{x=pos.x+1,y=pos.y}
    if desc.master then
      debug("slaving to dude at "..(pos.x+1)..","..pos.y)
      desc.master.slave=desc
    end
    --and the left, he will be our slave!
    desc.slave=getDescAtPos{x=pos.x-1,y=pos.y}
    if desc.slave then
      debug("enslaving dude at "..(pos.x-1)..","..pos.y)
      desc.slave.master=desc
    end

    nixie_map[nixie.position.y][nixie.position.x] = desc
  end
end

local function onRemoveEntity(entity)
  if entity.name=="nixie-tube" then
    local pos=entity.position
    local nixie_desc=nixie_map[pos.y] and nixie_map[pos.y][pos.x]
    if nixie_desc then
      removeSpriteObj(nixie_desc)
      nixie_map[pos.y][pos.x]=nil
    end
  end
end

local function onTick(event)
  --only update five times a second, rather than *every* tick.
  --7th of 12 picked at random.
  if event.tick%12 == 7 then
    for y,row in pairs(nixie_map) do
      for x,desc in pairs(row) do
        if desc.entity.valid then
          if desc.master==nil then
            local v=deduceSignalValue(desc.entity)
            local state="off"
            if v then
              if v<0 then v=-v end
              local d=desc
              repeat
                local m=v%10
                v=(v-m)/10
                state = tostring(m)
                setState(d,state)
                d=d.slave
              until d==nil or v==0
              while d do
                setState(d,"off")
                d=d.slave
              end
            end
          end
        else
          onRemoveEntity(desc.entity)
        end
      end
    end
  end
end



game.on_init(onLoad)
game.on_load(onLoad)

game.on_save(onSave)

game.on_event(defines.events.on_tick,function() end)

game.on_event(defines.events.on_built_entity,onPlaceEntity)
game.on_event(defines.events.on_robot_built_entity,onPlaceEntity)

game.on_event(defines.events.on_preplayer_mined_item, function(event) onRemoveEntity(event.entity) end)
game.on_event(defines.events.on_robot_pre_mined, function(event) onRemoveEntity(event.entity) end)
game.on_event(defines.events.on_entity_died, function(event) onRemoveEntity(event.entity) end)

game.on_event(defines.events.on_tick, onTick)

game.on_event(defines.events.on_player_driving_changed_state,
    function(event)
      local player=game.players[event.player_index]
      if player.vehicle and player.vehicle.name=="spintest" then
        player.vehicle.passenger=nil
      end
    end
  )