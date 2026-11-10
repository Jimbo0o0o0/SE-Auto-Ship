# SE Auto Ship Hull Generator 0.3.2

Factorio 2.1 / Space Exploration 0.7.x.

## Generate
Stand in a clear construction area. The console is placed at your character's position.

Sphere (default radius 10):

    /se-generate-ship sphere
    /se-generate-ship sphere 10

Pointed bow:

    /se-generate-ship pointed 13 31

The previous command syntax remains supported:

    /se-generate-ship 13 31

## Sphere perimeter revision
The previous version used a thick annular band of bulkhead walls. Version 0.3.2
replaces that band with a one-tile-thick, orthogonal staircase contour around the
filled circular floor.

The contour is generated from the floor disk itself:

1. For each row, calculate the left and right edge using
   `floor(sqrt(radius^2 - y^2))`.
2. Keep the edge tile on both sides of every row.
3. Join consecutive row edges with a horizontal run on the wider row. All added
   connector tiles are still within the disk.

This is deliberately not a thickened ring. The short horizontal connector runs are
the minimum stair-step geometry needed to avoid diagonal-only wall connections.

## Validation against the supplied Space Exploration code
The integrity source uses two different neighbour rules:

- Floor/bulkhead discovery and console connectivity use 4-way neighbours
  (north, south, east, west).
- Containment spreads to floor tiles using 8-way neighbours, including diagonals.

The sphere generator now validates both conditions before placement:

- Every wall tile is in the floor disk.
- All wall tiles form one 4-way-connected component.
- An 8-way flood started outside the ship cannot reach any non-wall floor tile.

The pointed hull generation method is unchanged in this revision.

## Default sphere (radius 10)
The planned shape has:

- 317 floor tiles
- 76 bulkhead wall tiles (one-tile-thick contour)
- 0 phantom tiles in the supplied weak-section scan
- 100% calculated streamline
- 260 gross structural-stress estimate before the in-game empty-floor allowance and installed entities

The 260 estimate is `317 - 76 * 0.75`, with no long/thin multiplier. The actual
integrity calculation then applies the empty-floor allowance and adds stress from
installed equipment, generators, containers, and fluids.

The orthogonal-connectivity and containment checks were tested on the generated
integer-grid layouts for radii 4–30. This is a geometry simulation, not a live
Factorio test; the in-game console integrity check remains authoritative.

This is a hull generator only. Add propulsion and other required ship systems.
Back up your save before testing.
