-- M-VAVE / Cuvave SMC-PAD (4x4 pads, 8+8 knobs, transport buttons)
--
-- Hardware map (verified against the vendor MIDI suite and the user's Ableton
-- remote-script research):
--   pads        Bank A: notes 36-51 on CH 10, bottom-left -> top-right
--               Bank B: notes 52-67 on CH 10 (unused here)
--   pad LEDs    Note On CH 10, velocity = color (0 = off)
--   knobs       Bank A: CC 30-37, Bank B: CC 38-45, both CH 1, absolute
--               (both banks transmit simultaneously; norns' parameter
--               MIDI-learn consumes them via the menu hook, not here)
--   transport   CC 25-29 on CH 1, "CC Push" (127 on press, 0 on release)
--               button LEDs: Note On CH 1, notes 25-29 (not driven yet)
--
-- midigrid role: Bank A pads are a 4x4 grid; use the '8x8p' vgrid layout so
-- the 16 pads page through a virtual 8x8. < and > switch pages, PLAY/PAUSE/REC
-- drive the MIDI clock transport (norns sends clock ticks via
-- PARAMETERS > CLOCK > "midi clock out"; these buttons send the transport
-- bytes norns doesn't).

local device = include('midigrid/lib/devices/generic_device')

device.width = 4
device.height = 4

-- rows are listed so that grid y=1 (monome bottom) matches the physical pad
-- row that carries notes 48-51 (the note numbers run top-down on the
-- hardware, confirmed live: the bottom-up mapping rendered vertically
-- inverted)
device.grid_notes = {
  { 48, 49, 50, 51 },
  { 44, 45, 46, 47 },
  { 40, 41, 42, 43 },
  { 36, 37, 38, 39 }
}

-- grid LED level 0-15 -> pad color velocity, quantized from the colors the
-- pad accepts (5/6 green, 7 cyan, 9 magenta, 13 yellow, 15 red, 45 orange,
-- 64 blue, 32 white). Green->cyan->yellow->red reads as intensity.
device.brightness_map = { 0, 5, 5, 5, 6, 6, 7, 7, 13, 13, 15, 15, 45, 45, 32, 32 }

device.quad_switching_enabled = false

-- Bank B left column pads (notes 52/56/60/64) select the grid page directly;
-- their LEDs show the active page (bright = current, dim = others)
device.page_pads = { [52] = 1, [56] = 2, [60] = 3, [64] = 4 }

device.update_page_leds = function(self)
  local dev = midi.devices[self.midi_id]
  if dev == nil then return end
  for note, quad in pairs(self.page_pads) do
    local vel = (quad == self.current_quad) and 32 or 5
    dev:send({ 0x99, note, vel })
  end
end

local generic_change_quad = device.change_quad
device.change_quad = function(self, quad)
  generic_change_quad(self, quad)
  self:update_page_leds()
end

-- transport buttons: input via aux 'col' entries, handlers installed in _init
-- (the generic _init clears the handler tables)
device.aux = {
  col = {
    { 'cc', 25, nil }, -- <    page left
    { 'cc', 26, nil }, -- >    page right
    { 'cc', 27, nil }, -- PLAY  midi start
    { 'cc', 28, nil }, -- PAUSE midi stop
    { 'cc', 29, nil }, -- REC   reset (stop, position 0, start)
  },
  row = {}
}

-- vports with PARAMETERS > CLOCK > "midi clock out" enabled
local function clock_out_ports()
  local ports = {}
  for i = 1, 16 do
    local id = "clock_midi_out_" .. i
    if params.lookup[id] ~= nil and params:get(id) == 1 then
      table.insert(ports, i)
    end
  end
  return ports
end

function device:page(dir)
  local n = #self.vgrid.quads
  if n < 2 then return end
  local q = ((self.current_quad - 1 + dir) % n) + 1
  self:change_quad(q)
end

function device:transport_start()
  self.transport_running = true
  self:update_transport_leds()
  for _, i in ipairs(clock_out_ports()) do
    midi.vports[i]:start()
  end
  -- re-align script beat phase when norns itself is the clock source
  if params:get("clock_source") == 1 then
    clock.internal.start()
  end
end

function device:transport_stop()
  self.transport_running = false
  self:update_transport_leds()
  for _, i in ipairs(clock_out_ports()) do
    midi.vports[i]:stop()
  end
end

function device:transport_reset()
  self:transport_stop()
  for _, i in ipairs(clock_out_ports()) do
    midi.vports[i]:song_position(0, 0)
  end
  clock.run(function()
    clock.sleep(0.06) -- let slaves see a distinct STOP before START
    self:transport_start()
  end)
end

-- pad LEDs live on channel 10 (0x99), not the generic channel 1 (0x90)
device._update_led = function(self, x, y, z)
  if y < 1 or y > #self.grid_notes or x < 1 or x > #self.grid_notes[y] then
    return
  end
  local vel = self.brightness_map[z + 1]
  local note = self.grid_notes[y][x]
  local midi_msg = { 0x99, note, vel }
  if midi.devices[self.midi_id] then
    midi.devices[self.midi_id]:send(midi_msg)
  end
end

-- PLAY button LED reflects the transport state (Note On CH 1, note 27;
-- the button's Led binding from the vendor preset). Button LEDs live on the
-- button channel (CH 1), pad LEDs on CH 10.
device.transport_running = false

device.update_transport_leds = function(self)
  local dev = midi.devices[self.midi_id]
  if dev == nil then return end
  dev:send({ 0x90, 27, self.transport_running and 127 or 0 })
end

-- keep the generic event handler from spamming the console: knobs (CC 30-45)
-- belong to norns' parameter system; Bank B pads either select a page (left
-- column) or are unused. The event is the raw byte table; peek at it and pass
-- the original through (the generic handler converts it itself).
local generic_event = device.event
device.event = function(self, vgrid, event)
  local status = event[1]
  if status ~= nil then
    local kind = status & 0xf0
    local ch = (status & 0x0f) + 1
    if kind == 0xb0 and event[2] >= 30 and event[2] <= 45 then
      return
    end
    if ch == 10 and (kind == 0x90 or kind == 0x80) then
      local note = event[2]
      if note >= 52 and note <= 67 then
        local page = self.page_pads[note]
        if page ~= nil and kind == 0x90 and event[3] > 0 then
          self:change_quad(page)
        end
        return
      end
    end
  end
  generic_event(self, vgrid, event)
end

-- install transport/page handlers after the generic _init has cleared them
local generic_init = device._init
device._init = function(self, vgrid, device_number)
  generic_init(self, vgrid, device_number)
  self.aux.col_handlers = {
    function(dev, val) if val == 1 then self:page(-1) end end,
    function(dev, val) if val == 1 then self:page(1) end end,
    function(dev, val) if val == 1 then self:transport_start() end end,
    function(dev, val) if val == 1 then self:transport_stop() end end,
    function(dev, val) if val == 1 then self:transport_reset() end end,
  }
  self:update_page_leds()
end

return device
