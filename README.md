# SE Auto Ship Hull Generator 0.3.3

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

## Sphere perimeter: thin continuity fix
Version 0.3.3 removes the thick annular wall band introduced in 0.3.1/0.3.2.

It now starts with the one-tile digital-circle edge: floor cells that have at least
one north/south/east/west neighbour outside the disk. It then adds only the
single-tile connector needed for each diagonal-only join between two cells in that
original edge. Connectors are chosen from the existing floor disk and are selected
to stay as close to the outer radius as possible.

Important: connectors are calculated from the original edge only. They are not
recursively bridged, which avoids progressively filling the interior with walls.

## Validation against the supplied Space Exploration code
The integrity source uses two different neighbour rules:

- Floor/bulkhead discovery and console connectivity use 4-way neighbours.
- Containment spreads to floor tiles using 8-way neighbours, including diagonals.

Before building, the sphere geometry is validated to ensure:

- Every wall is on a floor tile.
- The wall cells are one 4-way-connected component.
- An 8-way flood started outside cannot reach a non-wall floor tile.

The pointed-hull method is unchanged.

## Default sphere (radius 10)
The geometry simulation reports:

- 317 floor tiles
- 76 wall tiles: 56 original digital-circle edge cells + 20 one-cell connectors
- 0 phantom tiles in the source weak-section scan
- 100% calculated streamline
- 260 gross structural-stress estimate before the empty-floor allowance and any installed entities

The stress estimate uses the source values: 317 floor/bulkhead tiles minus
76 × 0.75 wall credit. The actual game check then applies its empty-floor allowance
and any installed equipment, generator, container, or fluid stress.

The 4-way connectivity and 8-way containment simulations pass for radii 4–30.
Streamline is calculated for each radius and is not guaranteed to be 100% at every
radius. This is a geometry simulation, not a live Factorio test; the console's
in-game integrity check remains authoritative.

This is a hull generator only. Add propulsion and other required ship systems.
Back up your save before testing.
