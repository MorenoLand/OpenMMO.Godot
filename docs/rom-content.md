# Direct ROM content

The client accepts a user-selected compatible FireRed or LeafGreen `.gba` base ROM. Both are Kanto sources for the same initial content contract. Desktop builds use Godot's native operating-system file dialog; Web builds use the browser file picker because Web cannot access the host filesystem directly.

The reader identifies FireRed and LeafGreen from their GBA header game codes (`BPRE` and `BPRF`) and Nintendo maker code (`01`). A graphics patch can therefore change ROM bytes without being rejected solely because its whole-file fingerprint changed.

ROM handling is profile-driven. Each profile owns its region, content contract, map-group table, map format, animation sources, object graphics, and renderer status. FireRed is the first enabled map reader; LeafGreen, Ruby, Sapphire, and Emerald are recognized profiles with their own future extension points rather than being misread through FireRed offsets.

After a valid Kanto ROM is selected, the client remembers its local path in `user://openmmogo-roms.json`. If the file is moved or removed, the client clears the stale path and opens Client Management so it can be selected again. ROM bytes are never written to the repository or uploaded to the server.

The current reader performs a structural FireRed map-layout check against the source-defined pointer tables, reads the ROM bytes into the client session, extracts the GBA header identifiers, and exposes the normalized Kanto map contract. The displayed SHA-1 is only a diagnostic fingerprint; it is not an acceptance gate. Unknown game codes and incompatible map layouts are rejected.

Online sessions receive authoritative map and player state from OpenMMO game packets. The selected ROM remains local and supplies the matching base-game visual content; ROM bytes never go to the server. Server-defined map and custom-content packet support is integrated at the protocol and renderer boundary rather than through a generated content pack.

No ROM, extracted asset, generated map, or derived content file belongs in this repository. Optional extraction stages must keep their output outside Git and remain independent of the network protocol.

The offline tester exposes the Kanto towns, routes, Viridian Forest, and selected Pallet Town and Viridian City interiors. Preview renders the selected map directly from the local ROM. Play loads that same decoded map into the interactive map scene with temporary character sprites, ROM object events, collision, ledges, warps, and map connections. The tester does not require an account or server connection.


Hoenn Emerald/Ruby/Sapphire profiles now include MAPSEC region_map_section_names (start 0) so HUD location labels resolve (e.g. Inside of Truck, Littleroot Town) instead of Unlisted area. Indoor/truck maps no longer expand border metatiles into the camera void.

