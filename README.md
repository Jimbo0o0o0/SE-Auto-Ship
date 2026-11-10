# SE Auto Ship Hull Generator 0.2.0

Factorio 2.1 / Space Exploration 0.7.x.

## Install
Replace the previous `se-auto-ship` mod with this ZIP in your Factorio `mods` folder.
Enable it and load your save.

## Generate
Stand in a clear construction area and run:

    /se-generate-ship

Optional dimensions:

    /se-generate-ship 13 31

Width is clamped to 7–31 and length to 15–81; dimensions are made odd.

## Streamline geometry
The previous version used a bow with a flat front edge. This version constructs the
hull column-by-column. For each X column, its frontmost tile is:

    front_y(x) = bow_tip_y + abs(x - centre_x)

That creates a symmetric stepped/45-degree pointed bow. In the supplied
`SpaceshipIntegrity.stop_integrity_check` formula, it produces at most two columns
sharing any one front Y, and enough distinct front Y values on each side to saturate
the flatness, left, and right factors. The resulting calculated streamline is 1.0
(100%) for the supported odd widths.

## Notes
The 100% claim is for the streamline calculation in the uploaded source file, assuming
the integrity traversal recognizes the generated hull's floor and bulkhead tiles as
connected. It is not a claim that the ship is flight-ready or stress-valid.
This is a hull-only generator; add propulsion and other ship systems as needed.
The mod has not been run in a Factorio game instance here. Back up your save before
testing.
