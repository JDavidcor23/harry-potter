# Spellbound Academy - Brick Duel

A wizard duel game made with Godot 4.7.

## Download and play

Get the latest build from the [Releases](https://github.com/JDavidcor23/harry-potter/releases) page.

### Windows

1. Download `SpellboundAcademy-Windows.zip` and unzip it.
2. Run `SpellboundAcademy.exe`.
3. If Windows SmartScreen appears, click **More info** > **Run anyway** (the build is not signed).

### macOS (Intel and Apple Silicon)

1. Download `SpellboundAcademy-macOS.zip` and unzip it.
2. Move `Spellbound Academy - Brick Duel.app` to Applications.
3. The app is not notarized, so the first time: right-click the app > **Open** > **Open**.
   If macOS says the app is damaged, run this in Terminal:

   ```sh
   xattr -cr "/Applications/Spellbound Academy - Brick Duel.app"
   ```

## Run from source

1. Install [Godot 4.7](https://godotengine.org/download).
2. Open `project.godot` in the editor and press **F5**.

## Export

With the Godot export templates for 4.7.2 installed:

```sh
godot --headless --path . --export-release "Windows Desktop" build/windows/SpellboundAcademy.exe
godot --headless --path . --export-release "macOS" build/macos/SpellboundAcademy.zip
```
