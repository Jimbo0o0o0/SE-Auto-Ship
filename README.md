# SE Auto Ship Hull Generator 0.3.0

Factorio 2.1 / Space Exploration 0.7.x.

## Install
Replace the previous `se-auto-ship` mod with this version in your Factorio `mods` folder, enable it, and load your save.

## Generate a ship
Stand in a clear construction area. The console is placed at your character's position.

Spherical hull (default radius 10):

    /se-generate-ship sphere

Choose a sphere radius (clamped to 4–30):

    /se-generate-ship sphere 10

Pointed-bow hull (defaults to 13 x 31):

    /se-generate-ship pointed 13 31

The previous command syntax remains supported:

    /se-generate-ship 13 31

## Validation against the supplied Space Exploration functions
Before placing the hull, the generator evaluates the planned tile map using the formulas from:

- `SpaceshipIntegrity.stop_integrity_check`: frontmost tile per X column, maximum number of columns sharing a front Y, left/right distinct front rows, and the combined streamline score.
- `SpaceshipIntegrity.calculate_integrity_stress`: per-row widths, alternating front/back thin-section scan, phantom-tile cost, perimeter-wall credit, and the long/thin multiplier.

After generation, it prints the calculated streamline percentage, estimated structural stress, floor-tile count, perimeter-wall count, and phantom-tile count. The estimate assumes the generated floors are all connected, each perimeter wall is recognized as a connected bulkhead, and no extra containers, fluids, equipment, or generators are installed. The console's actual integrity check remains authoritative.

### Default sphere result
For `/se-generate-ship sphere` (radius 10), the integer-grid disk contains:

- 317 floor tiles
- 56 perimeter bulkhead walls
- 0 phantom tiles in the source function's weak-section scan
- 100% calculated streamline
- 275 estimated structural stress before any installed ship equipment or cargo

The radius-10 sphere therefore stays below the source file's base structural integrity limit of 300 on hull geometry alone. Larger radii may exceed the base limit; research can increase the actual force limit.

## Notes
The sphere is a filled circular disk on the game's tile grid (a 2D sphere silhouette), not a hollow shell. Its size is a radius in tiles. A rasterized circle does not score 100% streamline at every possible radius, so the generator reports the actual score instead of promising 100% for all sizes.

This is a hull generator only. Add propulsion and other required ship systems separately. It has not been tested inside a running Factorio instance; back up your save before testing.
