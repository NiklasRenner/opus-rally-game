# Real roads into stages

`bake_stage.py` turns a stretch of a real road into the data a `geo` stage
needs (`data/stages/<id>.json` and `.bin`). The game only reads those files;
nothing here runs in Godot.

## What it does

1. Finds the road by name in the Overture Maps transportation data (which is
   OpenStreetMap's roads, ODbL) inside a lon/lat box, and joins its segments.
2. Cuts the stretch you asked for (metres along the road), plus some real
   road before the start and past the finish for the lead-in and run-out,
   smooths OSM's node kinks and scales it (`scale`, 1.3 for Turini, so the
   hairpins suit the game's cars; heights are scaled the same so gradients
   stay true).
3. Samples the Copernicus GLO-30 elevation model (30 m grid) along the road
   and smooths it (median then Gaussian, which takes out the trees and roofs
   the model includes) into the road's height profile.
4. Bakes two terrain grids in game metres: a near one on TrackBuilder's 8 m
   grid round the road, and a 96 m one out to about 5 km for the horizon. The
   near ground eases onto the far mesh's surface away from the road so they
   meet without a seam. The road itself is cut in by the game
   (`GeoStage.heights`), banks no steeper than its CUT/FILL.

## Adding a stage

Add an entry to `STAGES` in the script (road name as OSM has it, a lon/lat
box round it, the stretch in metres from the road's first node), then:

    pip install numpy scipy pyarrow shapely rasterio matplotlib pyproj
    python tools/real_stage/bake_stage.py <id> --preview

Look at `tools/real_stage/cache/<id>_preview.png` (top view and profile),
then add a map in `scripts/maps.gd` with `"geo": "<id>"`, `point_to_point`,
surface `sections` and the dressing keys (see the Turini entry). Downloads
are cached in `tools/real_stage/cache/` (ignored by git).

Elevation tiles north of 50 degrees are narrower (2400 px, 1800 past 60
degrees); they're stretched onto the one arc-second grid. The road has to
join into one line. 30 m elevation won't show small crests or jumps: give
the stage's `STAGES` entry `jumps` ([real metres from the start, height,
half-length in game metres]) and the bake adds them to the road profile, so
the banks follow them (see Ouninpohja). A lake can be shown with `"water": []`
and a `water_level` just above its surface in the map entry; trees and props
then keep out of the ground below it.

## More detail (OUNINPOHJA HD)

The 30 m model, smoothed over ~100 m, irons every small crest out of a road,
and the road was laid flat across. A stage entry can ask for more:

- `"fine_dem": "arcticdem"` takes the road's height from the ArcticDEM 2 m
  mosaic (everywhere north of 60 deg, so all of Finland; read straight from
  the Polar Geospatial Center's tiles on AWS and cached). It is a surface
  model, so where the forest closes over a narrow road it sees the
  treetops: the bake keeps the highest curve under it with crests no
  sharper than `crest_r` (vertical radius, real metres) and slopes no
  steeper than 16 %. The ground beside the road follows the difference
  from the 30 m model, fading out over ~70 m, so a crest is a small hill.
  Lower `crest_r` gives more air (at 50 the autopilot was airborne 13 % of
  the stage, mostly over treetop lumps).
- `"camber": {"turn", "hill", "max"}` banks the road: `turn / R` into a
  bend of radius R (game metres), plus `hill` times the hillside's slope
  across the road (so a bend can lean the wrong way), clamped to `max`.
  It's baked as a per-2 m list and the game tilts the road mesh, the banks
  and the height queries with it (`TrackBuilder.camber`, `road_y()`).
- `"roughness"` adds small bumps (9-30 m waves, stronger on some stretches).
- `"line_sigma"` (default 3) is how much the OSM line is smoothed and
  `"spacing"` the game's control points; `"roads_from"` reuses another
  stage's Overture download.

OSM draws Ouninpohjantie with a node every ~35 m, so wiggles smaller than
that aren't in the data at all; the corners it has are kept.

## Credits

Road data © OpenStreetMap contributors, ODbL. Terrain: Copernicus GLO-30 DEM,
© DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018, provided
under COPERNICUS by the European Union and ESA.

OUNINPOHJA HD's road heights: ArcticDEM v4.1 2 m mosaic, Polar Geospatial
Center (NSF-OPP awards 1043681, 1559691, 1542736, 1810976, 2129685), CC BY 4.0.
