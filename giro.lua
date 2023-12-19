-- Giro
-- v1.1 @JulesV
-- https://llllllll.co/t/giro/
-- 
-- (a)sync looping
-- performance
-- instrument
--
--    ▼ instructions below ▼
--
-- E1 select loop
-- K2 rec/ovr/play
-- K3 stop
-- K1+K2 group play on/off
-- K1+K3 clear loop
-- E2 loop level
-- K1+E2 loop pan
-- E3 loop group rate
-- K1+E3 loop rate
--

--
-- VARIABLES
--
PATH = _path.audio.."giro/"
MAX_LOOP_LENGTH = 80  -- max loop length 80 sec
CLOCK_INTERVAL = 0.01
shifted = false
loop = {}
selected_loop = 1
screen_refresh = true
grid_dirty = true
rates = {-2.0,-1.0,-0.5,0.5,1.0,2.0}
sync_modes = {"free","clocked"}
sync_mode = 1
time_denominators = {1,2,4,8,16}
transport = 0
bar = 1
beat = 1
ui_radius = 12
group_play = true
backup = 0
event_queue = {}

g = grid.connect()

--
-- INIT FUNCTIONS
--
function init_loop_variables()
  print("init loop variables")
  for i=1,6 do
    loop[i] = {}
    loop[i].rec = 0   -- 0=disabled 1=armed 2=enabled
    loop[i].play = 0  -- 0=disabled 1=armed 2=enabled
    loop[i].ovr = 0   -- 0=disabled 1=armed 2=enabled
    loop[i].stop = 2  -- 0=disabled 1=armed 2=enabled
    loop[i].length = MAX_LOOP_LENGTH
    loop[i].length_in_beats = 0
    loop[i].next_restart = 0
    loop[i].content = false
    loop[i].position = 0.00
  end
  
  loop[1].loop_start = 1
  loop[2].loop_start = 1 + MAX_LOOP_LENGTH
  loop[3].loop_start = 1 + 2 * MAX_LOOP_LENGTH
  loop[4].loop_start = 1
  loop[5].loop_start = 1 + MAX_LOOP_LENGTH
  loop[6].loop_start = 1 + 2 * MAX_LOOP_LENGTH
  
  loop[1].loop_end = 1 + MAX_LOOP_LENGTH
  loop[2].loop_end = 1 + 2 * MAX_LOOP_LENGTH
  loop[3].loop_end = 1 + 3 * MAX_LOOP_LENGTH
  loop[4].loop_end = 1 + MAX_LOOP_LENGTH
  loop[5].loop_end = 1 + 2 * MAX_LOOP_LENGTH
  loop[6].loop_end = 1 + 3 * MAX_LOOP_LENGTH
  
  loop[1].buffer = 1
  loop[2].buffer = 1
  loop[3].buffer = 1
  loop[4].buffer = 2
  loop[5].buffer = 2
  loop[6].buffer = 2
  
  loop[1].ui_x = 20
  loop[1].ui_y = 18
  loop[2].ui_x = 20
  loop[2].ui_y = 48
  loop[3].ui_x = 60
  loop[3].ui_y = 18
  loop[4].ui_x = 60
  loop[4].ui_y = 48
  loop[5].ui_x = 100
  loop[5].ui_y = 18
  loop[6].ui_x = 100
  loop[6].ui_y = 48
end

function init_softcut()
  print("init softcut")
  softcut.buffer_clear()
  softcut.buffer(1,1)
  softcut.buffer(2,1)
  softcut.buffer(3,1)
  softcut.buffer(4,2)
  softcut.buffer(5,2)
  softcut.buffer(6,2)
  audio.level_adc_cut(1)
  
  for i= 1,6 do
    softcut.enable(i,1)
    softcut.level(i,1.0)
    softcut.loop(i,1)
    softcut.loop_start(i,loop[i].loop_start)
    softcut.loop_end(i,loop[i].loop_end)
    softcut.position(i,loop[i].loop_start)
    softcut.level_input_cut(1,i,1.0)
    softcut.rec_level(i,0.0)
    softcut.pre_level(i,0.0)
    softcut.fade_time(i,0.01)
    softcut.rate_slew_time(i,0.1)
    softcut.play(i,1)
    softcut.rec(i,1)
    softcut.phase_quant(i,0.01)
  end

  softcut.event_phase(update_positions)
  softcut.poll_start_phase()
end

function init_grid_variables()
  g_counter = 1
  g_blink = true
  g_loop_select = {y = 1}
  g_loop_state = {}
  g_global_functions = {}
  g_params = {}
  g_level = {}
  g_pan = {}
  g_rate = {}
  g_master = {}
  g_group = {}
  g_multiple = {}
  g_alt = {x = 6}
  for y=1,6 do
    g_loop_state[y] = {x = 3}
    g_params[y] = {x = 6}
    g_level[y] = {x = 16}
    g_pan[y] = {x = 11}
    g_rate[y] = {x = 10}
    g_master[y] = {x = 6}
    g_group[y] = {x = 6}
    g_multiple[y] = {x = 6}
  end
  for x=1,4 do
    g_global_functions[x] = false
  end
  
end

function init_parameters()
  print("init_parameters")
  params:add_separator("GIRO - LOOPS")
  for i=1,6 do
    params:add_group("loop "..i,7)
    params:add {
      type="number",
      id=i.."master",
      name="master loop",
      min=1,
      max=6,
      default=1,
      action=function(value)
        local mult_look = params.lookup[i.."multiple"]
        print(i.."master loop : "..value)
        if i == value then
          stop_state(i)
          softcut.buffer_clear_region_channel(loop[i].buffer,loop[i].loop_start,MAX_LOOP_LENGTH,0.00,0)
          loop[i].content = false
          loop[i].length = MAX_LOOP_LENGTH
          softcut.loop_end(i,loop[i].loop_end)
          params.params[mult_look].max = 1
          params:set(i.."multiple",1)
        else
          if value == params:get(i.."master") then
            stop_state(i)
            softcut.buffer_clear_region_channel(loop[i].buffer,loop[i].loop_start,MAX_LOOP_LENGTH,0.00,0)
            loop[i].content = false
            loop[i].length = loop[params:get(i.."master")].length
            softcut.loop_end(i,loop[i].loop_start+loop[params:get(i.."master")].length)
            softcut.position(i,loop[i].loop_start+loop[params:get(i.."master")].position-loop[params:get(i.."master")].loop_start)
          end
          local max_multiples = math.floor(MAX_LOOP_LENGTH/loop[i].length)
          if loop[value].content then
            params.params[mult_look].max = max_multiples
            if params:get(i.."multiple") > max_multiples then
              params:set(i.."multiple",max_multiples)
            end
          else
            params.params[mult_look].max = 8
          end
        end
        grid_dirty = true
      end
    }
    params:add {
      type="number",
      id=i.."group",
      name="loop group",
      min=1,
      max=6,
      default=1,
      action=function(value)
        print(i.."loop group: "..value)
        grid_dirty = true
      end
    }
    params:add {
      type="number",
      id=i.."multiple",
      name="loop multiple",
      min=1,
      max=8,
      default=1,
      action=function(value)
        if loop[params:get(i.."master")].content then
          loop[i].length = loop[params:get(i.."master")].length*value
          softcut.loop_end(i,loop[i].loop_start+loop[i].length)
        end
        print(i.."multiple: "..value)
        grid_dirty = true
      end
    }    
    params:add {type="control",id=i.."level",name="level",controlspec=controlspec.new(0,1.0,'db',0.01,1.0,''),
      action=function(value)
        if loop[i].stop ~= 2 then
          softcut.level(i,value)
        end
        print(i.."level "..value)
        grid_dirty = true
      end
    }
    params:add {type="control",id=i.."pan",name="pan",controlspec=controlspec.new(-1,1.0,'lin',0.01,0.0,''),
      action=function(value)
        softcut.pan(i,value)
        print(i.."pan"..value)
        grid_dirty = true
      end
    }
    params:add {
      type="option",
      id=i.."rate",name="rate",
      options=rates,
      default=5,
      action=function(value)
        softcut.rate(i,rates[value])
        print(i.."rate"..rates[value])
        grid_dirty = true
      end
    }
    params:add {
      type="option",
      id=i.."sync",
      name="sync mode",
      options=sync_modes,
      default=1,
      action=function(value)
        sync_mode = value
        if value == 2 then
          params:set(i.."master",i)
        end
      end
    }
  end
  
  params:add_separator("GIRO - RECORDING")
  params:add {type="control",id="rec_level",name="rec level",controlspec=controlspec.new(0,1.0,'lin',0.01,1.0,''),
    action=function(value)
      print("rec level "..value)
    end
  }
  params:add {type="control",id="pre_level",name="loop preserve on ovr",controlspec=controlspec.new(0,1.0,'lin',0.01,1.0,''),
    action=function(value)
      print("pre level "..value)
    end
  }
  
  params:add_separator("GIRO - TIME SIGNATURE")
  params:add {
    type="number",
    id="time_numerator",
    name="time numerator",
    min=1,
    max=16,
    default=4,
    action=function(value)
      print("beats in sec: "..clock.get_beat_sec()*params:get("time_numerator")*4/time_denominators[params:get("time_denominator")])
    end
  }
  params:add {
    type="option",
    id="time_denominator",
    name="time denominator",
    options=time_denominators,
    default=3,
    action=function(value)
      print("beats in sec: "..clock.get_beat_sec()*params:get("time_numerator")*4/time_denominators[params:get("time_denominator")])
    end
  }
  
  params:bang()

  params:add_separator("GIRO - BUTTONS")
  params:add {type="binary",id="rec",name="record/ovr/play",behavior="toggle",
    action=function()
      print("rec button pressed")
      rec_press()
    end
  }
  params:add {type="binary",id="play",name="play",behavior="toggle",
    action=function()
      print("play button pressed")
      play_press()
    end
  }
  params:add {type="binary",id="stop",name="stop",behavior="toggle",
    action=function()
      print("stop button pressed")
      stop_press()
    end
  }
  params:add {type="binary",id="stop_all",name="stop all",behavior="toggle",
    action=function()
      stop_all_press()
    end
  }
  params:add {type="binary",id="clear",name="clear",behavior="toggle",
    action=function()
      print("clear button pressed")
      clear_press()
    end
  }
  params:add {type="binary",id="undo",name="undo",behavior="toggle",
    action=function()
      print("undo button pressed")
      undo_press()
    end
  }
  params:add {type="binary",id="next",name="next loop",behavior="toggle",
    action=function()
      if selected_loop < 6 then
        selected_loop = selected_loop+1
      end
    end
  }
  params:add {type="binary",id="prev",name="previous loop",behavior="toggle",
    action=function()
      if selected_loop > 1 then
        selected_loop = selected_loop-1
      end
    end
  }
  params:add {type="binary",id="group_play",name="group play",behavior="toggle",
    action=function()
      group_play = not group_play
    end
  }
  params:add {type="binary",id="transport_start",name="start transport",behavior="toggle",
    action=function()
      clock.transport.start()
    end
  }
  params:add {type="binary",id="transport_stop",name="stop transport",behavior="toggle",
    action=function()
      clock.transport.stop()
    end
  }
  
end

--
-- INIT AT STARTUP
--
function init()
  if not util.file_exists(PATH) then util.make_dir(PATH) end
  norns.enc.sens(1,5)
  norns.enc.sens(3,5)
  init_loop_variables()
  init_grid_variables()
  init_softcut()
  init_parameters()
  init_pset_callbacks()
  screen_redraw_metro = metro.init(screen_redraw_event,1/60,-1)
  screen_redraw_metro:start()
  grid_redraw_metro = metro.init(grid_redraw_event,1/30,-1)
  grid_redraw_metro:start()
  clock.run(master_clock)
end

--
-- CALLBACK FUNCTIONS
--
function update_positions(voice,position)
  loop[voice].position = position
end

function clock.transport.start()
  bc = clock.run(beat_clock)
end

function clock.transport.stop()
  stop_all_press()
  clock.cancel(bc)
  transport = 0
  beat = 1
  bar = 1
end

function init_pset_callbacks()
  params.action_write = function(filename,name)
    print("finished writing '"..filename.."' as '"..name.."'")

    for i=1,6 do
      local loop_file = PATH..name.."_loop"..i..".wav"
      if loop[i].content then
        print("save loop "..i)
        softcut.buffer_write_mono(loop_file,loop[i].loop_start,loop[i].length,loop[i].buffer)
      else
        if util.file_exists(loop_file) then
          os.execute("rm "..loop_file)
        end
      end
    end
  end
  
  params.action_read = function(filename)
    print("finished reading '"..filename.."'")
    local pset_file = io.open(filename, "r")
    if pset_file then
      io.input(pset_file)
      local pset_name = string.sub(io.read(), 4, -1)
      io.close(pset_file)
      
      softcut.buffer_clear()

      for i=1,6 do
        loop[i].content = false
        loop_file = PATH..pset_name.."_loop"..i..".wav"
        if util.file_exists(loop_file) then
          print(loop_file.." found")
          local ch, samples = audio.file_info(loop_file)
          local file_length = (samples/48000)
          softcut.buffer_read_mono(loop_file,0,loop[i].loop_start,loop[i].loop_end,ch,loop[i].buffer)
          loop[i].content = true
          loop[i].length = file_length
          softcut.loop_end(i,loop[i].loop_start+file_length)
        else
          calc_multiple(i)
          loop[i].length = loop[params:get(i.."master")].length * params:get(i.."multiple")
          softcut.loop_end(i,loop[i].loop_start+(loop[params:get(i.."master")].length * params:get(i.."multiple")))
        end
      end
    end
  end
  
end

--
-- CLOCK FUNCTIONS
--

function screen_redraw_event()
  ready = true
end

function refresh()
  if ready then
    redraw()
    ready = false
  end
end

function beat_clock()
  if params:string("clock_source") == "link" then
    print("linking")
    clock.sync(4/time_denominators[params:get("time_denominator")])
    transport = 0
    beat = 1
    bar = 1
  end
  while true do
    clock.sync(4/time_denominators[params:get("time_denominator")])
    transport = transport + 1
    beat = beat + 1
    if transport % params:get("time_numerator") == 0 then
      if params:get(selected_loop.."sync") == 2 then
        clock_tick()
      end
      beat = 1
      bar = bar + 1
    end
    restart_loops_to_beat_clock()
  end
end

function grid_redraw_event()
  update_grid_variables()
  if grid_dirty then
    grid_redraw()
    grid_dirty = false
  end
end

function master_clock()
  while true do
    clock.sleep(CLOCK_INTERVAL)
    if params:get(selected_loop.."sync") == 1 then
      clock_tick()
    end
  end
end

function clock_tick()
  for _,v in pairs(event_queue) do
    if loop[v].rec == 1 then
      stop_other_loop_groups(v)
      reset_loop_ends(v)
      restart_loops(v)
      rec_state(v)
    elseif loop[v].ovr == 1 then
      ovr_state(v)
    elseif loop[v].play == 1 then
      stop_other_loop_groups(v)
      if loop[v].rec == 2 then
        sync_loop_ends_to_master(v)
        play_state(v)
      elseif loop[v].stop == 2 then
        if master_loop_stopped(v) then
          restart_loops(v)
        end
        if group_play then
          for i=1,6 do
            if loop[i].content and params:get(i.."group") == params:get(v.."group") then
              play_state(i)
            end
          end
        else
          wait_for_master(v)
          play_state(v)
        end
      end
      play_state(v)
    elseif loop[v].stop == 1 then
      stop_other_loop_groups(v)
      if loop[v].rec == 2 then
        sync_loop_ends_to_master(v)
      end
      if group_play then
        for i=1,6 do
          if params:get(i.."group") == params:get(v.."group") then
            stop_state(i)
          end
        end
      else
        stop_state(v)
      end
    end
  end
  event_queue = {}
end

--
-- UI FUNCTIONS
--
function key(n,z)
  if n == 1 then
    shifted = z == 1
  elseif n == 2 and z == 1 and shifted then
    group_play = not group_play
  elseif n == 3 and z == 1 and shifted then
    clear_press()
  elseif n == 2 and z == 1 then
    rec_press()
  elseif n == 3 and z == 1 then
    stop_press()
  end
  grid_dirty = true
end

function enc(n,d)
  if n == 1 then
    selected_loop = util.clamp(selected_loop + d,1,6)
  elseif n == 2 and shifted then
    params:delta(selected_loop.."pan",d)
  elseif n == 3 and shifted then
    params:delta(selected_loop.."rate",d)
  elseif n == 2 then
    params:delta(selected_loop.."level",d)
  elseif n == 3 then
    for i=1,6 do
      if params:get(i.."group") == params:get(selected_loop.."group") then
        params:delta(i.."rate",d)
      end
    end
  end
  grid_dirty = true
end

function g.key(x,y,z)
  if y == 8 then
    g_global_functions[x] = z == 1 and true or false
  end
  if z == 1 then
    if x == 1 and y <= 6 then
      g_loop_select.y = y
      selected_loop = g_loop_select.y
    elseif x >= 2 and x <= 4 and y <= 6 then
      g_loop_state[y].x = x
      g_loop_select.y = y
      selected_loop = g_loop_select.y
      if g_loop_state[y].x == 2 then
        rec_press()
      elseif g_loop_state[y].x == 3 then
        stop_press()
      elseif g_loop_state[y].x == 4 then
        clear_press()
      end
    elseif y == 8 and x >= 6 and x <= 11 then
      g_alt.x = x
    elseif y == 8 and x <= 4 then
      if x == 1 then
        group_play = not group_play
      elseif x == 2 then
        undo_press()
      elseif x == 3 then
        stop_all_press()
      elseif x == 4 then
        print("still thinking about")
      end
    elseif g_alt.x == 9 then
      if x >= 6 and x <=16 and y <= 6 then
        g_level[y].x = x
        params:set(y.."level",(0.1*(x-6)))
      end
    elseif g_alt.x == 10 then
      if x >= 6 and x <=16 and y <= 6 then
        g_pan[y].x = x
        params:set(y.."pan",(0.2*(x-11)))
      end
    elseif g_alt.x == 11 then
      if x >= 6 and x <=11 and y <= 6 then
        g_rate[y].x = x
        params:set(y.."rate",(x-5))
      end
    elseif g_alt.x == 6 then
      if x >= 6 and x <=11 and y <= 6 then
        g_master[y].x = x
        params:set(y.."master",(x-5))
      end
    elseif g_alt.x == 7 then
      if x >= 6 and x <=11 and y <= 6 then
        g_group[y].x = x
        params:set(y.."group",(x-5))
      end
    elseif g_alt.x == 8 then
      if x >= 6 and x <=13 and y <= 6 then
        g_multiple[y].x = x
        params:set(y.."multiple",(x-5))
      end
    end
  end
  grid_dirty = true
end

--
-- LOOPING LOGIC FUNCTIONS
--
function rec_state(selected)
  softcut.buffer_clear_region_channel(loop[selected].buffer,loop[selected].loop_start,MAX_LOOP_LENGTH,0.00,0)
  softcut.level(selected,params:get(selected.."level"))
  softcut.rec_level(selected,params:get("rec_level"))
  softcut.pre_level(selected,0.0)
  loop[selected].content = true
  loop[selected].rec = 2
  loop[selected].play = 0
  loop[selected].ovr = 0
  loop[selected].stop = 0
  loop[selected].next_restart = 0
  grid_dirty = true
end

function play_state(selected)
  softcut.level(selected,params:get(selected.."level"))
  softcut.rec_level(selected,0.0)
  softcut.pre_level(selected,1.0)
  loop[selected].rec = 0
  loop[selected].play = 2
  loop[selected].ovr = 0
  loop[selected].stop = 0
  loop[selected].next_restart = transport + loop[selected].length_in_beats
  grid_dirty = true
end

function ovr_state(selected)
  backup_loop(selected)
  softcut.level(selected,params:get(selected.."level"))
  softcut.rec_level(selected,params:get("rec_level"))
  softcut.pre_level(selected,params:get("pre_level"))
  loop[selected].content = true
  loop[selected].rec = 0
  loop[selected].play = 0
  loop[selected].ovr = 2
  loop[selected].stop = 0
  loop[selected].next_restart = transport + loop[selected].length_in_beats
  grid_dirty = true
end

function stop_state(selected)
  softcut.level(selected,0.0)
  softcut.rec_level(selected,0.0)
  softcut.pre_level(selected,1.0)
  loop[selected].rec = 0
  loop[selected].play = 0
  loop[selected].ovr = 0
  loop[selected].stop = 2
  loop[selected].next_restart = 0
  grid_dirty = true
end

function clear_state(selected)
  softcut.buffer_clear_region_channel(loop[selected].buffer,loop[selected].loop_start,MAX_LOOP_LENGTH,0.00,0)
  loop[selected].content = false
  loop[selected].length_in_bars = 0
  grid_dirty = true
end

function rec_press()
  
  table.insert(event_queue,selected_loop)
  
  -- if loop is empty
  if not loop[selected_loop].content and is_master_loop(selected_loop) then
    loop[selected_loop].rec = 1
  elseif not loop[selected_loop].content and loop[params:get(selected_loop.."master")].play == 2 then
    loop[selected_loop].ovr = 1
  
  -- if there is content in the loop
  elseif loop[selected_loop].content then
    if loop[selected_loop].rec == 2 then
      loop[selected_loop].play = 1
    elseif loop[selected_loop].stop == 2 then
      loop[selected_loop].play = 1
    elseif loop[selected_loop].play == 2 then
      loop[selected_loop].ovr = 1
    elseif loop[selected_loop].ovr == 2 then
      loop[selected_loop].play = 1
    end
  end
end 

function play_press()
  table.insert(event_queue,selected_loop)
  loop[selected_loop].play = 1
end

function stop_press()
  table.insert(event_queue,selected_loop)
  if loop[selected_loop].stop ~= 2 then
    loop[selected_loop].stop = 1
  end
end

function stop_all_press()
  for i=1,6 do
    table.insert(event_queue,i)
    stop_state(i)
  end
end

function clear_press()
  --table.insert(event_queue,selected_loop)
  clear_state(selected_loop)
  stop_state(selected_loop)
end

function undo_press()
  table.insert(event_queue,selected_loop)
  if loop[selected_loop].content then
    if loop[selected_loop].play == 2 or loop[selected_loop].stop == 2 then
      if backup == selected_loop then
        restore_loop(selected_loop)
      end
    end
  end
end

--
-- HELPER FUNCTIONS
--
function is_master_loop(selected)
  if params:get(selected.."master") == selected then
    return true
  else
    return false
  end
end

function master_loop_stopped(selected)
  if loop[params:get(selected.."master")].stop == 2 then
    return true
  end
  return false
end

function wait_for_master(selected)
  if not is_master_loop(selected) and loop[params:get(selected.."master")].play == 2 then
    while loop[params:get(selected.."master")].position ~= loop[params:get(selected.."master")].loop_start do
      clock.sleep(0.01)
    end
    softcut.position(selected,loop[selected].loop_start)
  end
end

function calc_multiple(selected)
  local max_multiples = math.floor(MAX_LOOP_LENGTH / loop[params:get(selected.."master")].length)
  local mult_look = params.lookup[selected.."multiple"]
  if max_multiples > 8 then
    max_multiples = 8
  end
  params.params[mult_look].max = max_multiples
  if params:get(selected.."multiple") > max_multiples then
    params:set(selected.."multiple",max_multiples)
  end
end

function sync_loop_ends_to_master(selected)
  
  local master_length = loop[selected].position - loop[selected].loop_start
  
  if params:get(selected.."sync") == 2 then
    loop[selected].length_in_beats = math.floor(master_length / clock.get_beat_sec() * time_denominators[params:get("time_denominator")] / 4 + 0.5)
    print("master length in beats: "..loop[selected].length_in_beats)
    master_length = loop[selected].length_in_beats * clock.get_beat_sec() * 4 / time_denominators[params:get("time_denominator")]
    print("master length in sec: "..master_length)
  end
    
  for i=1,6 do
    if params:get(i.."master") == params:get(selected.."master") then
      calc_multiple(i)
      loop[i].length = master_length * params:get(i.."multiple")
      softcut.loop_end(i,loop[i].loop_start+master_length*params:get(i.."multiple"))
    end
  end
end

function reset_loop_ends(selected)
  for i=1,6 do
    if params:get(i.."master") == params:get(selected.."master") then
      softcut.loop_end(i,loop[i].loop_end)
    end
  end
end

function restart_loops(selected)
  for i=1,6 do
    if params:get(i.."master") == params:get(selected.."master") then
      softcut.position(i,loop[i].loop_start)
    end
  end
end

function stop_other_loop_groups(selected)
  for i=1,6 do
    if params:get(i.."group") ~= params:get(selected.."group") then
      stop_state(i)
    end
  end
end

function restart_loops_to_beat_clock()
  for i=1,6 do
    if loop[i].content 
    and loop[i].length_in_beats ~= 0 
    and params:get(i.."sync") == 2 
    and (loop[i].play == 2 or loop[i].ovr == 2) then
      if transport == loop[i].next_restart then
        loop[i].next_restart = transport + loop[i].length_in_beats
        print("restart loop "..i)
        softcut.position(i,loop[i].loop_start)
      end
    end
  end
end

function backup_loop(selected)
  softcut.buffer_copy_mono(loop[selected].buffer,loop[selected].buffer,loop[selected].loop_start,1+3*MAX_LOOP_LENGTH,MAX_LOOP_LENGTH,0.00,0.0,0)
  backup = selected
end

function restore_loop(selected)
  softcut.buffer_copy_mono(loop[selected].buffer,loop[selected].buffer,1+3*MAX_LOOP_LENGTH,loop[selected].loop_start,MAX_LOOP_LENGTH,0.00,0.0,0)
  backup = 0
end

function update_grid_variables()
  g_loop_select.y = selected_loop
  
  for i=1,6 do
    if loop[i].rec == 2 or loop[i].ovr == 2 or loop[i].play == 2 then
      g_loop_state[i].x = 2
      grid_dirty = true
    elseif loop[i].stop == 2 then
      g_loop_state[i].x = 3
    end
    
    g_master[i].x = params:get(i.."master")+5
    g_group[i].x = params:get(i.."group")+5
    g_multiple[i].x = params:get(i.."multiple")+5
    g_level[i].x = math.floor(params:get(i.."level")*10)+6
    g_pan[i].x = math.floor((params:get(i.."pan")+1.1)*5)+6
    g_rate[i].x = params:get(i.."rate")+5
  end
  
  g_global_functions[1] = group_play
  
  if g_counter > 5 then
    g_counter = 1
    g_blink = not g_blink
  else
    g_counter = g_counter + 1
  end
end

function is_clocked()
  for i=1,6 do
    if params:get(i.."sync") == 2 then
      return true
    else
      return false
    end
  end
end
     

--
-- REDRAW FUNCTIONS
--
function redraw()
  screen.clear()
  -- transport
  screen.level(15)
  --screen.move(10,6)
  --screen.text(transport)
  for i=1,params:get("time_numerator") do
    if i == beat then
      screen.rect(i*6-1,0,4,4)
      screen.fill()
    else
      screen.rect(i*6,1,3,3)
      screen.stroke()
    end
  end
  --  group play
  if group_play then
    screen.level(15)
    screen.move(124,6)
    screen.text("G")
  end
  -- loops
  for i=1,6 do
    screen.level(15)
    screen.aa(0)
    screen.line_width(1)
    --selected loop
    if i == selected_loop then
      screen.aa(1)
      screen.circle(loop[i].ui_x+0.5,loop[i].ui_y+8.5,2)
      screen.fill()
    end
    --loop number & state
    screen.move(loop[i].ui_x,loop[i].ui_y-4)
    if loop[i].content then
      screen.text_center(i.."c")
    else
      screen.text_center(i)
    end
    screen.move(loop[i].ui_x,loop[i].ui_y+4)
    if loop[i].rec == 2 then
      screen.text_center("rec")
    elseif loop[i].play == 2 then
      screen.text_center("play")
    elseif loop[i].ovr == 2 then
      screen.text_center("ovr")
    elseif loop[i].stop == 2 then
      screen.text_center("stop")
    end
    --loop master / content / group
    screen.move(loop[i].ui_x+14,loop[i].ui_y-6)
    screen.text("m"..params:get(i.."master"))
    screen.move(loop[i].ui_x+14,loop[i].ui_y+2)
    screen.text("x"..params:get(i.."multiple"))
    screen.move(loop[i].ui_x+14,loop[i].ui_y+10)
    screen.text("g"..params:get(i.."group"))
    --loop progress circle
    screen.aa(1)
    screen.line_width(1.5)
    screen.level(3)
    screen.move(loop[i].ui_x+ui_radius,loop[i].ui_y)
    screen.circle(loop[i].ui_x,loop[i].ui_y,ui_radius)
    screen.stroke()
    if loop[i].play == 2 or loop[i].ovr == 2 then
      screen.level(15)
      screen.arc(loop[i].ui_x,loop[i].ui_y,ui_radius,-math.pi/2,2*math.pi*(loop[i].position-loop[i].loop_start)/loop[i].length-math.pi/2)
      screen.stroke()
    end
    --loop progress when stopped
    if loop[i].stop == 2 and loop[params:get(i.."master")].play == 2 and i == selected_loop then
      screen.level(15)
      screen.pixel(loop[i].ui_x-0.5+ui_radius*math.sin(2*math.pi*(loop[i].position-loop[i].loop_start)/loop[i].length), loop[i].ui_y-0.5-ui_radius*math.cos(2*math.pi*(loop[i].position-loop[i].loop_start)/loop[i].length))
      screen.fill()
    end
    --pan
    screen.level(15)
    screen.aa(0)
    screen.line_width(1)
    screen.move(loop[i].ui_x-13,loop[i].ui_y+15)
    screen.line_rel(26,0)
    screen.stroke()
    screen.aa(0)
    screen.rect(loop[i].ui_x+params:get(i.."pan")*13,loop[i].ui_y+13,1,3)
    screen.fill()
    --level
    screen.aa(0)
    screen.line_width(1)
    screen.move(loop[i].ui_x-14,loop[i].ui_y-13)
    screen.line_rel(0,26)
    screen.stroke()
    screen.aa(0)
    screen.rect(loop[i].ui_x-16,loop[i].ui_y+13-params:get(i.."level")*26,3,1)
    screen.fill()
  end
  screen.update()
end

function grid_redraw()
  g:all(0)
  for y = 1,6 do
    g:led(1,y,4)
    g:led(1, g_loop_select.y, 15)
    for x=2,4 do
      g:led(x,y,4)
    end
    if loop[y].rec == 2 or loop[y].ovr == 2 then
      g:led(g_loop_state[y].x ,y, g_blink and 15 or 4)
    else
      g:led(g_loop_state[y].x ,y, 15)
    end
    if loop[y].content then
      g:led(4, y, 9)
    else
      g:led(4,y,4)
    end
    if g_alt.x == 9 then
      for x=6,16 do
        g:led(x,y,4)
      end
      g:led(g_level[y].x, y, 15)
    elseif g_alt.x == 10 then
      for x=6,16 do
        g:led(x,y,4)
      end
      g:led(11,y,9)
      g:led(g_pan[y].x, y, 15)
    elseif g_alt.x == 11 then
      for x=6,11 do
        g:led(x,y,4)
      end
      g:led(g_rate[y].x, y, 15)
    elseif g_alt.x == 6 then
      for x=6,11 do
        g:led(x,y,4)
      end
      g:led(g_master[y].x, y, 15)
    elseif g_alt.x == 7 then
      for x=6,11 do
        g:led(x,y,4)
      end
      g:led(g_group[y].x, y, 15)
    elseif g_alt.x == 8 then
      for x=6,13 do
        g:led(x,y,4)
      end
      g:led(g_multiple[y].x, y, 15)
    end
  end
  for x=6,11 do
    g:led(x,8,4)
  end
  g:led(g_alt.x, 8, 15)
  for x=1,4 do
    g:led(x,8,4)
    if g_global_functions[x] then
      g:led(x,8,15)
    end
  end

  g:refresh()
end
