-- Pad Shuffle Sampler (ReaScript Lua)
-- Replaces the JSFX to allow direct insertion of MP3s

local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])")
if not script_path then script_path = "" end
local base_audio_dir = script_path .. "Audio files/"

local subfolders = {}
local i = 0
while true do
    local folder = reaper.EnumerateSubdirectories(base_audio_dir, i)
    if not folder then break end
    table.insert(subfolders, folder)
    i = i + 1
end
if #subfolders == 0 then
    table.insert(subfolders, ".")
end

local current_folder_idx = 1
local audio_files = {}
local SAMPLE_COUNT = 0
local PAD_COUNT = 16

local pads = {}
local pad_locks = {}
local pending_pads = {}

local function get_current_audio_dir()
    if subfolders[current_folder_idx] == "." then return base_audio_dir end
    return base_audio_dir .. subfolders[current_folder_idx] .. "/"
end

local function load_folder(idx)
    current_folder_idx = idx
    local dir = get_current_audio_dir()
    
    audio_files = {}
    local k = 0
    while true do
        local file = reaper.EnumerateFiles(dir, k)
        if not file then break end
        if file:match("%.mp3$") or file:match("%.wav$") or file:match("%.ogg$") or file:match("%.flac$") then
            table.insert(audio_files, file)
        end
        k = k + 1
    end
    
    SAMPLE_COUNT = #audio_files
    
    if SAMPLE_COUNT > 0 then
        math.randomseed(reaper.time_precise())
        for j = 1, PAD_COUNT do
            pads[j] = math.random(1, SAMPLE_COUNT)
            pending_pads[j] = pads[j]
            pad_locks[j] = false
        end
    else
        for j = 1, PAD_COUNT do
            pads[j] = 0
            pending_pads[j] = 0
            pad_locks[j] = false
        end
    end
end

-- initial load
load_folder(1)

local function shuffle()
    if SAMPLE_COUNT == 0 then return end
    local available = {}
    for j = 1, SAMPLE_COUNT do
        table.insert(available, j)
    end
    for j = #available, 2, -1 do
        local k = math.random(1, j)
        available[j], available[k] = available[k], available[j]
    end
    local idx = 1
    for j = 1, PAD_COUNT do
        if not pad_locks[j] then
            if idx <= #available then
                pending_pads[j] = available[idx]
                idx = idx + 1
            else
                pending_pads[j] = math.random(1, SAMPLE_COUNT)
            end
        else
            pending_pads[j] = pads[j]
        end
    end
end

local function commit_shuffle()
    for j = 1, PAD_COUNT do
        pads[j] = pending_pads[j]
    end
end

local function wrap_filename(fname)
    fname = fname:gsub("%.mp3$", ""):gsub("%.wav$", "")
    local lines = {}
    local max_chars = 14
    while #fname > max_chars do
        table.insert(lines, fname:sub(1, max_chars) .. "-")
        fname = fname:sub(max_chars + 1)
    end
    table.insert(lines, fname)
    if #lines > 3 then
        lines[3] = lines[3]:sub(1, max_chars - 2) .. ".."
        return {lines[1], lines[2], lines[3]}
    end
    return lines
end

local is_dragging = false
local pull_amount = 0
local has_triggered = false
local last_any_click = false

-- Animation states
local is_animating_snapback = false
local spring_velocity = 0
local pad_spin_timers = {}
for j = 1, 16 do pad_spin_timers[j] = 0 end
local is_spinning_globally = false

local sidebar_w = 160
gfx.init("Pad Shuffle Sampler", 700 + sidebar_w, 540, 0)
gfx.setfont(1, "Arial", 14)
gfx.setfont(2, "Arial", 12)
gfx.setfont(3, "Arial", 16) -- For folder names

local pad_w = 120
local pad_h = 100

local lever_box_x, lever_box_y = 570 + sidebar_w, 50
local lever_box_w, lever_box_h = 80, 445
local slot_x = lever_box_x + 30
local slot_y = lever_box_y + 10
local slot_w = 20
local slot_h = lever_box_h - 20

local function loop()
    local char = gfx.getchar()
    if char == -1 then 
        os.execute("killall afplay 2>/dev/null")
        return 
    end
    
    local left_click = (gfx.mouse_cap & 1) == 1
    local right_click = (gfx.mouse_cap & 2) == 2
    local any_click = left_click or right_click
    local click_down = any_click and not last_any_click
    
    local mouse_x, mouse_y = gfx.mouse_x, gfx.mouse_y
    
    if click_down then
        -- Check Sidebar clicks
        if left_click and mouse_x < sidebar_w then
            local list_y = 50
            for idx, folder in ipairs(subfolders) do
                if mouse_y >= list_y - 5 and mouse_y <= list_y + 25 then
                    if idx ~= current_folder_idx and not is_spinning_globally then
                        load_folder(idx)
                        os.execute("killall afplay 2>/dev/null") -- stop preview on folder change
                    end
                end
                list_y = list_y + 35
            end
        elseif mouse_x > lever_box_x and mouse_x < lever_box_x + lever_box_w and
           mouse_y > lever_box_y and mouse_y < lever_box_y + lever_box_h then
           if left_click and not is_spinning_globally and SAMPLE_COUNT > 0 then
               is_dragging = true
               has_triggered = false
               is_animating_snapback = false
               spring_velocity = 0
           end
        else
            -- Check Pad Clicks
            local pad_idx = 1
            for row = 0, 3 do
                for col = 0, 3 do
                    local px = sidebar_w + 20 + (col * (pad_w + 15))
                    local py = 50 + (row * (pad_h + 15))
                    
                    local btn_prev_x = px + 5
                    local btn_prev_y = py + pad_h - 30
                    local btn_prev_w = 50
                    local btn_prev_h = 24
                    
                    local btn_ins_x = px + 65
                    local btn_ins_y = py + pad_h - 30
                    local btn_ins_w = 50
                    local btn_ins_h = 24

                    if mouse_x > px and mouse_x < px + pad_w and mouse_y > py and mouse_y < py + pad_h then
                        if pad_spin_timers[pad_idx] > 0 or SAMPLE_COUNT == 0 then
                            -- ignore clicks
                        else
                            local display_idx = pads[pad_idx]
                            if display_idx > 0 then
                                if left_click then
                                    if mouse_x >= btn_prev_x and mouse_x <= btn_prev_x + btn_prev_w and mouse_y >= btn_prev_y and mouse_y <= btn_prev_y + btn_prev_h then
                                        local file_to_play = get_current_audio_dir() .. audio_files[display_idx]
                                        os.execute("killall afplay 2>/dev/null")
                                        os.execute('afplay "' .. file_to_play .. '" &')
                                    elseif mouse_x >= btn_ins_x and mouse_x <= btn_ins_x + btn_ins_w and mouse_y >= btn_ins_y and mouse_y <= btn_ins_y + btn_ins_h then
                                        local file_to_insert = get_current_audio_dir() .. audio_files[display_idx]
                                        reaper.InsertMedia(file_to_insert, 0)
                                        reaper.UpdateArrange()
                                    else
                                        pad_locks[pad_idx] = not pad_locks[pad_idx]
                                    end
                                elseif right_click then
                                    pad_locks[pad_idx] = not pad_locks[pad_idx]
                                end
                            end
                        end
                    end
                    pad_idx = pad_idx + 1
                end
            end
        end
    end

    if is_dragging then
        if not left_click then
            is_dragging = false
            if has_triggered then
                shuffle()
                commit_shuffle()
                
                is_animating_snapback = true
                spring_velocity = 0
                has_triggered = false
                
                for r = 0, 3 do
                    for c = 0, 3 do
                        local p_idx = 1 + c + (r * 4)
                        if not pad_locks[p_idx] then
                            pad_spin_timers[p_idx] = 20 + (c * 20) + (r * 5)
                        else
                            pad_spin_timers[p_idx] = 0
                        end
                    end
                end
            else
                is_animating_snapback = true
                spring_velocity = 0
            end
        else
            local raw_pull = (mouse_y - slot_y) / slot_h
            pull_amount = math.max(0, math.min(1, raw_pull))
            if pull_amount >= 0.95 and not has_triggered then
                has_triggered = true
            end
        end
    else
        if is_animating_snapback then
            local target = 0
            local tension = 0.2
            local damp = 0.65
            local force = (target - pull_amount) * tension
            spring_velocity = (spring_velocity + force) * damp
            pull_amount = pull_amount + spring_velocity
            
            if math.abs(pull_amount) < 0.005 and math.abs(spring_velocity) < 0.005 then
                pull_amount = 0
                is_animating_snapback = false
            end
        end
    end
    
    is_spinning_globally = false
    for j = 1, 16 do
        if pad_spin_timers[j] > 0 then
            pad_spin_timers[j] = pad_spin_timers[j] - 1
            is_spinning_globally = true
        end
    end
    
    -- DRAWING
    gfx.set(0.12, 0.12, 0.12, 1)
    gfx.rect(0, 0, gfx.w, gfx.h, 1)
    
    -- DRAW SIDEBAR
    gfx.set(0.08, 0.08, 0.08, 1)
    gfx.rect(0, 0, sidebar_w, gfx.h, 1)
    gfx.set(1, 1, 1, 1)
    gfx.setfont(1)
    gfx.x = 10
    gfx.y = 15
    gfx.drawstr("KITS / FOLDERS")
    gfx.set(0.3, 0.3, 0.3, 1)
    gfx.line(10, 35, sidebar_w - 10, 35)
    
    local list_y = 50
    gfx.setfont(3)
    for idx, folder in ipairs(subfolders) do
        if idx == current_folder_idx then
            gfx.set(0.3, 0.3, 0.4, 1)
            gfx.rect(0, list_y - 5, sidebar_w, 30, 1)
            gfx.set(1, 1, 1, 1)
        else
            gfx.set(0.6, 0.6, 0.6, 1)
        end
        
        -- Trucate folder name if too long
        local short_f = folder
        if gfx.measurestr(folder) > sidebar_w - 20 then
            short_f = string.sub(folder, 1, 12) .. ".."
        end
        
        gfx.x = 10
        gfx.y = list_y
        gfx.drawstr(short_f)
        
        list_y = list_y + 35
    end
    
    -- lever background
    gfx.set(0.05, 0.05, 0.05, 1)
    gfx.rect(slot_x, slot_y, slot_w, slot_h, 1)
    
    local handle_base_y = slot_y + (slot_h * 0.1)
    local handle_range = slot_h * 0.7
    local handle_h = 40
    local handle_current_y = handle_base_y + (handle_range * pull_amount)
    
    -- arm
    gfx.set(0.4, 0.4, 0.4, 1)
    gfx.rect(slot_x, handle_current_y, 20, handle_h, 1)
    
    -- knob
    local knob_r = 20
    local knob_x = slot_x + (slot_w / 2)
    local knob_y = handle_current_y - knob_r + (handle_h / 2)
    if pull_amount >= 0.95 or has_triggered then
        gfx.set(1.0, 0.3, 0.3, 1)
    else
        gfx.set(0.8, 0.1, 0.1, 1)
    end
    gfx.circle(knob_x, knob_y, knob_r, 1, 1)
    
    gfx.setfont(1)
    gfx.set(1, 1, 1, 1)
    gfx.x = lever_box_x
    gfx.y = lever_box_y - 25
    gfx.drawstr("DRAG DOWN")
    
    -- Instruction Text
    gfx.x = sidebar_w + 20
    gfx.y = 15
    gfx.set(0.8, 0.8, 0.8, 1)
    gfx.drawstr("Click Pad Background to LOCK | Preview Button to HEAR | Insert Button to ADD")
    
    -- pads
    local pad_idx = 1
    for row = 0, 3 do
        for col = 0, 3 do
            local px = sidebar_w + 20 + (col * (pad_w + 15))
            local py = 50 + (row * (pad_h + 15))
            
            local is_spinning = (pad_spin_timers[pad_idx] > 0)
            
            if pad_locks[pad_idx] then
                gfx.set(0.4, 0.15, 0.15, 1)
            elseif is_spinning then
                gfx.set(0.15, 0.15, 0.18, 1)
            else
                gfx.set(0.2, 0.2, 0.25, 1)
            end
            gfx.rect(px, py, pad_w, pad_h, 1)
            
            local display_idx = pads[pad_idx]
            if is_spinning and SAMPLE_COUNT > 0 then
                display_idx = math.random(1, SAMPLE_COUNT)
            end
            
            if SAMPLE_COUNT == 0 then
                gfx.setfont(2)
                gfx.set(0.6, 0.6, 0.6, 1)
                gfx.x = px + 10
                gfx.y = py + 40
                gfx.drawstr("No Audio")
            else
                -- File name
                gfx.setfont(2)
                if is_spinning then
                    gfx.set(0.5, 0.5, 0.5, 1)
                else
                    gfx.set(0.9, 0.9, 0.9, 1)
                end
                
                local fname = audio_files[display_idx]
                if fname then
                    local wrapped_lines = wrap_filename(fname)
                    for l = 1, #wrapped_lines do
                        gfx.x = px + 5
                        gfx.y = py + 5 + ((l-1) * 15)
                        gfx.drawstr(wrapped_lines[l])
                    end
                end
                
                -- Draw Buttons (hide if spinning)
                if not is_spinning then
                    local btn_prev_x = px + 5
                    local btn_prev_y = py + pad_h - 30
                    local btn_prev_w = 50
                    local btn_prev_h = 24
                    
                    gfx.set(0.2, 0.6, 0.3, 1)
                    gfx.rect(btn_prev_x, btn_prev_y, btn_prev_w, btn_prev_h, 1)
                    gfx.set(1, 1, 1, 1)
                    gfx.x = btn_prev_x + 5
                    gfx.y = btn_prev_y + 5
                    gfx.drawstr("Preview")
                    
                    local btn_ins_x = px + 65
                    local btn_ins_y = py + pad_h - 30
                    local btn_ins_w = 50
                    local btn_ins_h = 24
                    
                    gfx.set(0.2, 0.4, 0.8, 1)
                    gfx.rect(btn_ins_x, btn_ins_y, btn_ins_w, btn_ins_h, 1)
                    gfx.set(1, 1, 1, 1)
                    gfx.x = btn_ins_x + 9
                    gfx.y = btn_ins_y + 5
                    gfx.drawstr("Insert")
                end
                
                -- Lock indicator
                if pad_locks[pad_idx] then
                    gfx.setfont(1)
                    gfx.set(1, 1, 1, 1)
                    gfx.x = px + pad_w - 15
                    gfx.y = py + 5
                    gfx.drawstr("L")
                end
            end
            
            pad_idx = pad_idx + 1
        end
    end
    
    last_any_click = any_click
    
    gfx.update()
    reaper.defer(loop)
end

loop()
