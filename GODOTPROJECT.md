# Godot OpenMMO project notes

## Hoenn (Emerald) client fixes
- HUD map names: Hoenn ROM profiles supply MAPSEC section names (start=0), including Inside of Truck.
- Truck void bleed: indoor/secret-base maps skip border metatile expansion so tiles do not wrap into the black void.
- OW sprites / dialogue MAGMA spam: see recent commits on features/openmmo (Kanto sprite fallback + page spam guard).
