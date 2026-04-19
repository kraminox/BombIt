# Session Notes - Character System & Cosmetics

## What Was Done
- Replaced old 6-character system (Sparky, Bubbles, etc.) with 3 color-based characters (Pink, Blue, Orange)
- Each character has a `cosmeticsFolder` pointing to `PinkAssets`, `BlueAssets`, `OrangeAssets` in `ReplicatedStorage/Assets/Cosmetics`
- Removed dead code: `MapGenerator.BuildCharacters()` and `MapGenerator.CreateCharacterModel()`
- There is ONE base rig in `ReplicatedStorage/Characters` (not separate models per character). It has AnimSaves, a Humanoid, and attachment points for cosmetics.
- CharacterUI updated: clicking a character head swaps the outfit (Outfit1 accessories), not the rig itself
- Left/Right accessory pairing in CharacterUI (e.g., LeftOrangeShoe + RightOrangeShoe displayed together as "OrangeShoe")
- SaveChanges button sends character ID + equipped cosmetics list to server via `CharacterSelected` remote
- Server stores `equippedCosmetics` on `PlayerData` (added to GameState)
- ViewportFrame uses manual weld (`AttachAccessoryToCharacter`) because `Humanoid:AddAccessory()` doesn't work in ViewportFrames
- Body part hiding: when "Shoe" is in accessory name, `LeftFoot`/`RightFoot` transparency set to 1

## Current Bug: Right Shoe Not Appearing In-Game
The right shoe (RightOrangeShoe, BlueRightShoe, etc.) consistently gets ejected from the in-game character ~2 seconds after spawning. The LEFT shoe works fine. This ONLY affects the in-game character - the ViewportFrame preview shows both shoes correctly.

### What We Tried (None Fixed It)
1. **`humanoid:AddAccessory(clone)`** - Right shoe silently fails, never appears as child of character
2. **Manual WeldConstraint** (same as ViewportFrame approach) - Both shoes parent successfully, but RightKnee body part gets EJECTED by the engine ~2 seconds later, taking RightOrangeShoe with it. Debug confirmed: `CHILD REMOVED: RightKnee MeshPart` followed by `CHILD REMOVED: RightOrangeShoe Accessory`
3. **Weld instead of WeldConstraint** (C0/C1 style) - Same result, RightKnee still ejected
4. **Extract Handle as plain MeshPart** (not Accessory wrapper) - Accessories stopped appearing entirely (no debug output for cosmetics)
5. **Move cosmetics application to BEFORE `character.Parent = Workspace`** - Latest attempt, not yet tested. Theory: adding accessories after `player.Character = character` triggers Humanoid's internal accessory reprocessing which conflicts with existing Motor6D joints on RightKnee

### Key Debug Findings
- All accessories successfully parent (confirmed via print statements)
- The engine itself removes RightKnee (not any script) - `debug.traceback()` showed no user script in the stack
- Timing is consistent: always ~2 seconds after character creation
- LeftKnee is NOT affected - only RightKnee
- Attachment names: `LeftShoeAttachment` on LeftKnee, `RightShoeAttachment` on RightKnee
- The ViewportFrame uses the exact same data/accessories and works perfectly

### Theories to Investigate
- The rig's RightKnee Motor6D might have a subtle issue that only manifests when an accessory is welded to it
- The Humanoid's internal accessory processing (triggered by `player.Character` assignment) may conflict with manual welds specifically on the right side
- The latest approach (cosmetics before Workspace parenting) might work - needs testing
- Could try: add accessories to the template BEFORE cloning, or delay accessory addition with `task.defer`

## Files Modified
- `src/shared/Constants.lua` - 3 characters (Pink/Blue/Orange) with cosmeticsFolder
- `src/shared/GameState.lua` - Added `equippedCosmetics: {string}` to PlayerData
- `src/server/GameManager.server.lua` - CharacterSelected handler accepts cosmetics list
- `src/server/MapGenerator.lua` - Removed BuildCharacters/CreateCharacterModel
- `src/server/RoundSystem.lua` - Cosmetics application in GetOrCreateCharacter (currently moved to before Workspace parenting)
- `src/client/CharacterUI.client.lua` - Full rewrite: head selection, cosmetics display with L/R pairing, manual weld for ViewportFrame, SaveChanges sends data to server
