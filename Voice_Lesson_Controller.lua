local ctx = reaper.ImGui_CreateContext("Voice Lesson Controller")

-- =========================================================================
-- 【5列対応版】外部のCSVファイルから曲リストを自動で読み込む関数
-- =========================================================================
local function LoadSongList(csvPath)
  local list = {}
  local file = io.open(csvPath, "r")
  if not file then return list end

  for line in file:lines() do
    local title, path, tag, bpm, ts_num = line:match("^([^,]+),([^,]+),([^,]+),([^,]+),([^,\r\n]+)")
    
    if not title then
      title, path, tag, bpm = line:match("^([^,]+),([^,]+),([^,]+),([^,\r\n]+)")
      ts_num = "4"
      if not title then
        title, path, tag = line:match("^([^,]+),([^,]+),([^,\r\n]+)")
        bpm = "120"
        ts_num = "4"
        if not title then
          title, path = line:match("^([^,]+),([^,\r\n]+)")
          tag = ""
          bpm = "120"
          ts_num = "4"
        end
      end
    end
    
    if title and path then
      title = title:match("^%s*(.-)%s*$")
      path = path:match("^%s*(.-)%s*$")
      tag = tag and tag:match("^%s*(.-)%s*$") or ""
      bpm = bpm:match("^%s*(.-)%s*$")
      ts_num = ts_num:match("^%s*(.-)%s*$")
      
      table.insert(list, { title = title, file = path, tag = tag, bpm = bpm, ts_num = ts_num })
    end
  end

  file:close()
  return list
end

-- =========================================================================
-- パス・初期設定
-- =========================================================================
local script_dir = debug.getinfo(1, "S").source:match([[^@?(.*[\/])]])
script_dir = script_dir:gsub("\\", "/")

local csv_file_path = reaper.GetExtState("VoiceLessonJukebox", "CsvPath")
if csv_file_path == "" then csv_file_path = script_dir .. "songs.csv" end

local song_list = LoadSongList(csv_file_path)
local selected_index = 0
local audio_dir = reaper.GetExtState("VoiceLessonJukebox", "AudioDir")
local filter_text = ""

-- 現在のキーの変更量を保存しておく変数（最初は±0）
local current_pitch_offset = 0

-- =========================================================================
-- 再生 ＆ BPM・拍子自動同期関数
-- =========================================================================
local function PlayAudio(song)
  current_pitch_offset = 0

  local track = reaper.GetTrack(0, 0)
  if not track then return end
  
  reaper.SetOnlyTrackSelected(track)
  reaper.Main_OnCommand(40914, 0) 
  
  local item_count = reaper.CountTrackMediaItems(track)
  for i = item_count - 1, 0, -1 do
    local item = reaper.GetTrackMediaItem(track, i)
    reaper.DeleteTrackMediaItem(track, item)
  end
  
  local num_bpm = tonumber(song.bpm)
  local num_ts = tonumber(song.ts_num) or 4
  
  if num_bpm and num_bpm > 0 then
    if reaper.CountTempoTimeSigMarkers(0) > 0 then
      reaper.SetTempoTimeSigMarker(0, 0, 0, -1, -1, num_bpm, num_ts, 4, false)
    else
      reaper.SetTempoTimeSigMarker(0, -1, 0, -1, -1, num_bpm, num_ts, 4, false)
    end
    reaper.SetCurrentBPM(0, num_bpm, true)
    reaper.UpdateTimeline() 
  end
  
  reaper.SetEditCurPos(0, true, false)
  
  local full_path = audio_dir .. "/" .. song.file
  full_path = full_path:gsub("\\", "/"):gsub("//", "/")
  reaper.InsertMedia(full_path, 0) 
  
  reaper.SetEditCurPos(0, true, false)
  reaper.Main_OnCommand(1007, 0)  
end

-- =========================================================================
-- メインループ
-- =========================================================================
local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 520, 400, reaper.ImGui_Cond_Always())
  
  local window_flags = reaper.ImGui_WindowFlags_NoResize()
  local visible, open = reaper.ImGui_Begin(ctx, "Voice Lesson Controller", true, window_flags)
  
  -- ループ自動ON監視
  local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if start_time ~= end_time then
    reaper.GetSetRepeat(1)
  else
    reaper.GetSetRepeat(0)
  end

  if visible then
    -- パス設定欄（折りたたみ）
    if reaper.ImGui_CollapsingHeader(ctx, "Path Setting") then
      reaper.ImGui_Text(ctx, "Song List Path:")
      local csv_changed, csv_txt = reaper.ImGui_InputText(ctx, "##CsvPath", csv_file_path)
      if csv_changed then
        csv_file_path = csv_txt
        reaper.SetExtState("VoiceLessonJukebox", "CsvPath", csv_file_path, true)
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "Reload") then
        song_list = LoadSongList(csv_file_path)
        selected_index = 0
      end
      
      reaper.ImGui_Text(ctx, "Audio Files Path:")
      local audio_changed, audio_txt = reaper.ImGui_InputText(ctx, "##AudioPath", audio_dir)
      if audio_changed then
        audio_dir = audio_txt
        reaper.SetExtState("VoiceLessonJukebox", "AudioDir", audio_dir, true)
      end
      reaper.ImGui_Separator(ctx)
    end
    
    reaper.ImGui_Spacing(ctx)
    
    -- 検索窓
    reaper.ImGui_Text(ctx, "🔍 Filter Song List")
    local filter_changed, f_txt = reaper.ImGui_InputText(ctx, "##FilterText", filter_text)
    if filter_changed then filter_text = f_txt end
    
    -- コントロールパネル
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, "🎵 Control Panel") -- タイトルをシンプルに戻しました
    
    local track = reaper.GetTrack(0, 0)
    
    -- 1. ♭ボタン
    if reaper.ImGui_Button(ctx, "Key ♭ (-1)") then
      if track then
        reaper.SetOnlyTrackSelected(track)
        reaper.Main_OnCommand(40421, 0) 
        reaper.Main_OnCommand(40205, 0) 
        current_pitch_offset = current_pitch_offset - 1
      end
    end
    
    reaper.ImGui_SameLine(ctx)
    
    -- 2. ＃ボタン
    if reaper.ImGui_Button(ctx, "Key ＃ (+1)") then
      if track then
        reaper.SetOnlyTrackSelected(track)
        reaper.Main_OnCommand(40421, 0) 
        reaper.Main_OnCommand(40204, 0) 
        current_pitch_offset = current_pitch_offset + 1
      end
    end
    
    reaper.ImGui_SameLine(ctx)
    
    -- ---------------------------------------------------------------------
    -- Key変更ボタンのすぐ右隣に変更した数値を並べる
    -- ---------------------------------------------------------------------
    local key_str = "原調 (±0)"
    if current_pitch_offset > 0 then
      key_str = "+" .. current_pitch_offset
    elseif current_pitch_offset < 0 then
      key_str = tostring(current_pitch_offset)
    end
    reaper.ImGui_Text(ctx, "[ Key: " .. key_str .. " ]")
    -- ---------------------------------------------------------------------
    
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Spacing(ctx) 
    reaper.ImGui_SameLine(ctx)
    
    -- 3. ❌ Turn off Loop
    if reaper.ImGui_Button(ctx, "❌ Turn off Loop") then
      reaper.Main_OnCommand(40020, 0) 
    end
    
    reaper.ImGui_SameLine(ctx)
    
    -- 4. 🔄 波形再描画ボタン
    if reaper.ImGui_Button(ctx, "🔄 Redraw Waveform") then
      reaper.Main_OnCommand(40441, 0) 
    end
    
    -- 曲リスト表示（スクロールエリア）
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, "Song List")
    
    if reaper.ImGui_BeginChild(ctx, "ScrollableList", 0, 0) then
      
      if #song_list == 0 then
        reaper.ImGui_Text(ctx, "曲リストが空っぽ、またはファイルが見つかりません。")
      else
        for i, song in ipairs(song_list) do
          local show_item = true
          if filter_text ~= "" then
            local clean_filter = filter_text:gsub(" ", " ")
            local search_target = (song.title .. " " .. song.tag):lower()
            for word in string.gmatch(clean_filter:lower(), "[^%s]+") do
              if not string.find(search_target, word, 1, true) then
                show_item = false
                break
              end
            end
          end
          
          if show_item then
            local is_selected = (selected_index == i)
            local display_name = song.title .. " (♩=" .. song.bpm .. " / " .. song.ts_num .. "拍子)"
            
            if reaper.ImGui_Selectable(ctx, display_name, is_selected) then
              selected_index = i      
              PlayAudio(song) 
            end
          end
        end
      end
      
      reaper.ImGui_EndChild(ctx) 
    end
    
    reaper.ImGui_End(ctx)
  end
  
  if open then
    reaper.defer(loop)
  end
end

reaper.defer(loop)