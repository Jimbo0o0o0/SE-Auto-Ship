# SE Auto Ship Hull Generator 0.3.1

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

## Bulkhead connectivity fix
Space Exploration's floor-connectivity and console-connectivity passes use four-way
(neighbouring north/south/east/west) traversal. Diagonal corner contact is not enough.
The containment pass also expands to diagonal neighbours, so the perimeter must seal
the inside rather than leave diagonal leaks.

Version 0.3.1 changes both hulls:

- Sphere: uses a connected annular bulkhead band rather than only the single-tile
  digital-circle edge. The default radius-10 hull uses 124 wall tiles; the ring is
  four-way connected and blocks diagonal containment leaks.
- Pointed bow: adds the inboard step behind each diagonal bow tile, connecting the
  front bulkhead chain horizontally/vertically.

Before placement, the generator runs a four-way connectivity test over the planned
wall positions and refuses to build if any wall is disconnected. It also warns if
Factorio fails to place every wall entity.

## Default sphere validation
For `/se-generate-ship sphere` (radius 10):

- 317 floor tiles
- 124 connected perimeter bulkhead walls
- 0 phantom tiles in the weak-section scan
- 100% calculated streamline
- 224 estimated structural stress before additional ship entities

This estimate mirrors the relevant source functions and assumes the game recognises
all generated floor and wall tiles and that all floor tiles are connected to the
console. The actual in-game integrity check remains authoritative. Cargo, generators,
fluids, and other installed entities can increase stress.

This is a hull generator only; add propulsion and other required ship systems.
Back up your save before testing; this mod has not been tested in a running game here.
