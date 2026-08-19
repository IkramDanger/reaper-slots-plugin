# Pad Shuffle Sampler (REAPER Lua Script)

A slot-machine style, interactive sample randomizer built specifically for REAPER! This script provides a fun, visual way to generate random kits, preview sounds, and insert them directly into your music production timeline.

##  Folder Structure & Audio Setup

To ensure the script works correctly, you must maintain a specific folder structure. You can place the main project folder anywhere on your computer (e.g., Desktop, Documents), as long as the internal structure remains intact.

```text
reaper-slots-plugin/          <-- Your main project folder
│
├── PadShuffler.lua           <-- The main script you run in REAPER
│
└── Audio files/              <-- The master directory for all your sounds
    │
    ├── meme_audio/           <-- Subfolder 1 (acts as a "Kit")
    │   ├── sound1.mp3
    │   └── sound2.wav
    │
    └── drums/                <-- Subfolder 2 (acts as another "Kit")
        ├── kick.wav
        └── snare.wav
```

**Adding New Sounds:**
The script automatically reads the folders inside the `Audio files/` directory and turns them into selectable "Kits" in the sidebar. Simply create a new folder inside `Audio files/` and drop your `.mp3`, `.wav`, `.ogg`, or `.flac` files into it!

---

##  How to Run the Plugin in REAPER

Because this tool interacts deeply with your REAPER timeline (inserting files, dynamic UI), it runs as a **ReaScript**, not a traditional JSFX plugin.

1. Open **REAPER**.
2. In the top menu bar, click on **Actions** > **Show action list...** (or press `?`).
3. Click the **New action...** button (usually near the bottom right or top right).
4. Select **Load ReaScript...**
5. Navigate to the `reaper-slots-plugin` folder and select **`PadShuffler.lua`**.
6. The script is now added to your Action List! Simply double-click `PadShuffler.lua` in the list to open the window.

---

##  How to Use the Interface

* **Kits Sidebar (Left):** Click any folder name in the sidebar to instantly load those sounds.
* **The Lever (Right):** Click and drag the red knob all the way down and release it to randomize all unlocked pads with a slot-machine cascading spin animation.
* **Pad Background:** Click the empty space of any pad (or Right-Click it) to **Lock** it. A locked pad won't be replaced the next time you pull the lever!
* **Preview Button:** Click this to instantly play a preview of the audio file in the background without affecting your track. *(Note: Preview relies on macOS native `afplay`).*
* **Insert Button:** Click this to drop the audio file directly onto your REAPER timeline at the current Edit Cursor on your selected track.
