-- giro
-- 
-- (a)sync looping
-- performance
-- instrument
--
-- 
--    ▼ instructions below ▼
--
-- e1 select loop
-- k2 rec/ovr/play
-- k3 stop
-- k1+k2 enable group play
-- k1+k3 clear loop
-- e2 loop level
-- k1+e2 loop pan
-- e3 loop group rate
-- k1+e3 loop rate
--

--
-- VARIABLES
--
PATH = _path.audio.."giro/"
SESSIONID = string.format("%06.0f",1000000*math.random())
MAX_LOOP_LENGTH = 80  -- max loop length 80 sec
CLOCK_INTERVAL = 0.01
shifted = false
loop = {}
selected_loop = 1
screen_refresh = true
rates = {-2.0,-1.0,-0.5,0.5,1.0,2.0}
ui_radius = 12
group_play = true
backup = 0

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

function init_parameters()
  print("init_parameters")
  params:add_separator("GIRO - LOOPS")
  for i=1,6 do
    params:add_group("loop "..i,6)
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
      end
    }    
    params:add {type="control",id=i.."level",name="level",controlspec=controlspec.new(0,1.0,'db',0.01,1.0,''),
      action=function(value)
        if loop[i].stop ~= 2 then
          softcut.level(i,value)
        end
        print(i.."level "..value)
      end
    }
    params:add {type="control",id=i.."pan",name="pan",controlspec=controlspec.new(-1,1.0,'lin',0.01,0.0,''),
      action=function(value)
        softcut.pan(i,value)
        print(i.."pan"..value)
      end
    }
    params:add {type="option",id=i.."rate",name="rate",options=rates,default=5,
      action=function(value)
        softcut.rate(i,rates[value])
        print(i.."rate"..rates[value])
      end
    }
  end
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
      for i=1,6 do
        stop_state(i)
      end
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
      selected_loop = selected_loop+1
    end
  }
  params:add {type="binary",id="prev",name="previous loop",behavior="toggle",
    action=function()
      selected_loop = selected_loop-1
    end
  }
  params:add {type="binary",id="group_play",name="group play",behavior="toggle",
    action=function()
      group_play = not group_play
    end
  }
  
  params:add_separator("GIRO - FILES")
  params:add {type="binary",id="save",name="save loops to disk",behavior="toggle",
  action=function()
    print("loops saved to disk")
    save_loops_to_disk()
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
  init_softcut()
  init_parameters()
  clock.run(screen_redraw_clock)
  clock.run(master_clock)
end

--
-- CALLBACK FUNCTIONS
--
function update_positions(voice,position)
  loop[voice].position = position
end

--
-- CLOCK FUNCTIONS
--
function screen_redraw_clock()
  while true do
    clock.sleep(1/30) -- refresh at 30fps.
    redraw()
  end
end

function master_clock()
  while true do
    clock.sleep(CLOCK_INTERVAL)
    clock_tick()
  end
end

function clock_tick()
  if loop[selected_loop].rec == 1 then
    stop_other_loop_groups(selected_loop)
    reset_loop_ends(selected_loop)
    restart_loops(selected_loop)
    rec_state(selected_loop)
  elseif loop[selected_loop].ovr == 1 then
    ovr_state(selected_loop)
  elseif loop[selected_loop].play == 1 then
    stop_other_loop_groups(selected_loop)
    if loop[selected_loop].rec == 2 then
      sync_loop_ends_to_master(selected_loop)
      play_state(selected_loop)
    elseif loop[selected_loop].stop == 2 then
      if all_loops_stopped() then
        restart_loops(selected_loop)
      end
      if group_play then
        sync_to_master(selected_loop)
        for i=1,6 do
          if loop[i].content and params:get(i.."group") == params:get(selected_loop.."group") then
            play_state(i)
          end
        end
      else
        sync_to_master(selected_loop)
        play_state(selected_loop)
      end
    end
    play_state(selected_loop)
  elseif loop[selected_loop].stop == 1 then
    stop_other_loop_groups(selected_loop)
    if loop[selected_loop].rec == 2 then
      sync_loop_ends_to_master(selected_loop)
    end
    stop_state(selected_loop)
  end
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
end

--
-- LOOPING LOGIC FUNCTIONS
--
function rec_state(selected)
  softcut.buffer_clear_region_channel(loop[selected].buffer,loop[selected].loop_start,MAX_LOOP_LENGTH,0.00,0)
  softcut.level(selected,params:get(selected.."level"))
  softcut.rec_level(selected,1.0)
  softcut.pre_level(selected,0.0)
  loop[selected].content = true
  loop[selected].rec = 2
  loop[selected].play = 0
  loop[selected].ovr = 0
  loop[selected].stop = 0
end

function play_state(selected)
  softcut.level(selected,params:get(selected.."level"))
  softcut.rec_level(selected,0.0)
  softcut.pre_level(selected,1.0)
  loop[selected].rec = 0
  loop[selected].play = 2
  loop[selected].ovr = 0
  loop[selected].stop = 0
end

function ovr_state(selected)
  backup_loop(selected)
  softcut.level(selected,params:get(selected.."level"))
  softcut.rec_level(selected,1.0)
  softcut.pre_level(selected,1.0)
  loop[selected].content = true
  loop[selected].rec = 0
  loop[selected].play = 0
  loop[selected].ovr = 2
  loop[selected].stop = 0
end

function stop_state(selected)
  softcut.level(selected,0.0)
  softcut.rec_level(selected,0.0)
  softcut.pre_level(selected,1.0)
  loop[selected].rec = 0
  loop[selected].play = 0
  loop[selected].ovr = 0
  loop[selected].stop = 2
end

function clear_state(selected)
  softcut.buffer_clear_region_channel(loop[selected].buffer,loop[selected].loop_start,MAX_LOOP_LENGTH,0.00,0)
  loop[selected].content = false
end

function rec_press()
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
  loop[selected_loop].play = 1
end

function stop_press()
  loop[selected_loop].stop = 1
end

function clear_press()
  clear_state(selected_loop)
  stop_state(selected_loop)
end

function undo_press()
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

function all_loops_stopped()
  for i=1,6 do
    if loop[i].stop ~= 2 then
      return false
    end
  end
  return true
end

--how to handle multiple?
function sync_to_master(selected)
  if not is_master_loop(selected) and loop[params:get(selected.."master")].play == 2 then
    softcut.position(selected,loop[selected].loop_start+loop[params:get(selected.."master")].position-loop[params:get(selected.."master")].loop_start)
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

function backup_loop(selected)
  softcut.buffer_copy_mono(loop[selected].buffer,loop[selected].buffer,loop[selected].loop_start,1+3*MAX_LOOP_LENGTH,MAX_LOOP_LENGTH,0.00,0.0,0)
  backup = selected
end

function restore_loop(selected)
  softcut.buffer_copy_mono(loop[selected].buffer,loop[selected].buffer,1+3*MAX_LOOP_LENGTH,loop[selected].loop_start,MAX_LOOP_LENGTH,0.00,0.0,0)
  backup = 0
end

function save_loops_to_disk()
  saveid = string.format("%06.0f",1000000*math.random())
  for i=1,6 do
    if loop[i].content then
      print("save loop "..i)
      saved = "giro_sessionid"..SESSIONID.."_saveid"..saveid.."_loop"..i..".wav"
      softcut.buffer_write_mono(PATH..saved,loop[i].loop_start,loop[i].length,loop[i].buffer)
    end
  end
end


--
-- REDRAW FUNCTIONS
--
function redraw()
  screen.clear()
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
--    if loop[i].content == true then
--      screen.move(loop[i].ui_x+15,loop[i].ui_y+2)
--      screen.text("c")
--    end
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
      screen.move(loop[i].ui_x+ui_radius,loop[i].ui_y)
      screen.arc(loop[i].ui_x,loop[i].ui_y,ui_radius,0,2*math.pi*(loop[i].position-loop[i].loop_start)/loop[i].length)
      screen.stroke()
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
