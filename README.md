# SE Auto Ship Hull Generator 0.3.3

Factorio 2.1 / Space Exploration 0.7.x.

## Generate
Stand in a clear construction area. The console is placed at your character's position.

Triangle
    
    /se-generate-ship triangle [width] [length]

Sphere (default radius 10):

    /se-generate-ship sphere
    /se-generate-ship sphere 10

Pointed bow:

    /se-generate-ship pointed 13 31

The previous command syntax remains supported:

    /se-generate-ship 13 31
    
## Validation 
Before placing the hull, the generator evaluates the planned tile map using the formulas from:

- `SpaceshipIntegrity.stop_integrity_check`: frontmost tile per X column, maximum number of columns sharing a front Y, left/right distinct front rows, and the combined streamline score.
- `SpaceshipIntegrity.calculate_integrity_stress`: per-row widths, alternating front/back thin-section scan, phantom-tile cost, perimeter-wall credit, and the long/thin multiplier.
