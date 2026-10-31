"""Bake a stage from a real road: OpenStreetMap centreline + Copernicus elevation.

Writes data/stages/<id>.json (route, height profile, grid layout, credits) and
data/stages/<id>.bin (terrain heights) for TrackBuilder's "geo" maps. The game
reads only those two files; this script is the one place that needs the
internet. See tools/real_stage/README.md.

    python bake_stage.py turini            # bake one stage
    python bake_stage.py turini --preview  # also draw a top view and profile

Road data: OpenStreetMap contributors (ODbL), read from the Overture Maps
transportation theme on AWS. Elevation: Copernicus GLO-30 DEM (ESA, free
licence), read from the AWS open data bucket.
"""

import argparse
import json
import math
import os
import struct
import sys
import urllib.request
from urllib.parse import urlparse

import numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
CACHE = os.path.join(HERE, "cache")
OUT = os.path.join(REPO, "data", "stages")
OVERTURE = "overturemaps-us-west-2/release/2026-10-21.0/theme=transportation/type=segment/"
DEM_URL = ("https://copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_N{lat:02d}_00_E{lon:03d}_00_DEM/"
	"Copernicus_DSM_COG_10_N{lat:02d}_00_E{lon:03d}_00_DEM.tif")
# ArcticDEM 2 m mosaic (everything north of 60 deg, so all of Finland): 50 km
# subtiles in polar stereographic metres (EPSG:3413)
ARCTIC_URL = ("https://pgc-opendata-dems.s3.us-west-2.amazonaws.com/arcticdem/mosaics/v4.1/2m/"
	"{row:02d}_{col:02d}/{row:02d}_{col:02d}_{sr}_{sc}_2m_v4.1_dem.tif")

CELL = 8.0  # TrackBuilder.CELL: the near terrain grid, in game metres
FAR_CELL = 96.0  # the distant terrain, a whole number of near cells
FAR_HALF = 5200.0  # how far the distant terrain reaches from the stage
BAND = 300.0  # the near (solid) terrain covers this far from the road
DETAIL = (110.0, 180.0)  # ...with full detail this close, eased into the distant mesh by the outer distance
MAX_GRADE = 0.16  # the steepest slope a 2 m road profile keeps

STAGES = {
	"turini": {
		# the climb from La Bollene-Vesubie to the Col de Turini (Alpes-Maritimes):
		# the stretch of hairpins up the side of the Vallon de la Planchette
		"road": "Route du Col de Turini",
		"bbox": [7.30, 43.92, 7.45, 44.02],  # lon/lat to search for the road
		"from_m": 1500.0,  # metres along the road (from its La Bollene end)
		"to_m": 6500.0,
		"lead": 60.0,  # real road kept before the start and past the finish
		"tail": 150.0,
		"scale": 1.3,  # game metres per real metre, across and up alike
		"spacing": 10.0,  # control points, game metres apart
	},
	"ouninpohja": {
		# Rally Finland's legend, near Jamsa: the gravel of Ouninpohjantie in the
		# classic direction, from the Mutanen junction west towards Hamepohja
		"road": "Ouninpohjantie",
		"bbox": [24.85, 61.72, 25.03, 61.79],
		"from_m": 3200.0,
		"to_m": 8200.0,
		"lead": 60.0,
		"tail": 150.0,
		"scale": 1.15,
		"spacing": 10.0,
		# the 30 m elevation smooths Ouninpohja's crests away: put them back on
		# the real ones (sharpest bends of a finer profile), [real metres from
		# the start, height and half-length in game metres]. The biggest is the
		# yellow house jump's stand-in
		"jumps": [[1033, 0.8, 12.0], [1661, 1.4, 15.0], [2147, 0.7, 12.0], [2474, 1.2, 14.0],
			[2643, 1.7, 16.0], [3136, 1.5, 15.0], [3939, 1.3, 14.0], [4237, 1.2, 14.0]],
	},
	"ouninpohja_hd": {
		# the detail test: Ouninpohjantie again (a stretch further on, through
		# the twistier bends towards the Hamepohjantie junction), but with the
		# road's height from the 2 m ArcticDEM instead of the 30 m model, so
		# every real crest and dip is there; banked bends; small bumps; life
		# size and a tighter line so the real corners stay tight
		"road": "Ouninpohjantie",
		"roads_from": "ouninpohja",  # same Overture download
		"bbox": [24.85, 61.72, 25.03, 61.79],
		"from_m": 4000.0,
		"to_m": 9800.0,
		"lead": 60.0,
		"tail": 150.0,
		"scale": 1.0,
		"spacing": 5.0,
		"line_sigma": 2.5,
		"fine_dem": "arcticdem",
		# the sharpest crest it keeps (vertical radius, real metres): at 50 the
		# autopilot was off the ground for 13% of the stage, mostly over
		# treetop lumps; at 130 a car takes off over a crest from ~130 km/h
		"crest_r": 130.0,
		# road camber, rise per metre across: leaning into a bend of radius R by
		# turn / R, plus `hill` times the slope of the hillside it runs along,
		# no more than `max` either way
		"camber": {"turn": 4.5, "hill": 0.2, "max": 0.11},
		# small bumps on top of the real profile (game metres, roughly)
		"roughness": 0.06,
	},
}


# --------------------------------------------------------------------------- download

def overture_roads(cfg, stage_id):
	"""Road segments in the stage's bbox from Overture (cached)."""
	import pyarrow.dataset as ds
	import pyarrow.fs as pf
	import pyarrow.parquet as pq
	path = os.path.join(CACHE, cfg.get("roads_from", stage_id) + "_roads.parquet")
	if not os.path.exists(path):
		proxy = {}
		if os.environ.get("HTTPS_PROXY"):
			p = urlparse(os.environ["HTTPS_PROXY"])
			proxy = {"proxy_options": {"scheme": p.scheme, "host": p.hostname, "port": p.port}}
		fs = pf.S3FileSystem(anonymous=True, region="us-west-2", **proxy)
		x0, y0, x1, y1 = cfg["bbox"]
		f = ((ds.field("bbox", "xmin") > x0) & (ds.field("bbox", "xmax") < x1)
			& (ds.field("bbox", "ymin") > y0) & (ds.field("bbox", "ymax") < y1))
		print("querying Overture (a few minutes)...")
		t = ds.dataset(OVERTURE, filesystem=fs, format="parquet").to_table(
			filter=f, columns=["id", "names", "class", "subtype", "geometry", "road_surface"])
		pq.write_table(t, path)
	return pq.read_table(path).to_pylist()


def road_line(cfg, stage_id):
	"""The named road as one lon/lat polyline, its segments joined end to end."""
	import shapely.wkb
	from shapely.ops import linemerge
	segs = [shapely.wkb.loads(r["geometry"]) for r in overture_roads(cfg, stage_id)
		if (r["names"] or {}).get("primary") == cfg["road"]]
	if not segs:
		sys.exit("road %r not found" % cfg["road"])
	line = linemerge(segs) if len(segs) > 1 else segs[0]
	if line.geom_type != "LineString":
		sys.exit("road %r doesn't join into one line" % cfg["road"])
	return np.array(line.coords)


def dem_tile(lat, lon):
	path = os.path.join(CACHE, "dem_N%02d_E%03d.tif" % (lat, lon))
	if not os.path.exists(path):
		print("downloading DEM tile", lat, lon)
		urllib.request.urlretrieve(DEM_URL.format(lat=lat, lon=lon), path)
	return path


class Dem:
	"""Copernicus GLO-30 heights over a lon/lat box, sampled bicubically."""

	def __init__(self, lon0, lat0, lon1, lat1):
		import rasterio
		# one arc-second grid; whole tiles stacked north to south
		self.step = 1.0 / 3600.0
		self.lon0 = math.floor(lon0 * 3600) / 3600
		self.lat1 = math.ceil(lat1 * 3600) / 3600
		w = int(math.ceil((lon1 - self.lon0) * 3600)) + 1
		h = int(math.ceil((self.lat1 - lat0) * 3600)) + 1
		self.z = np.zeros((h, w), np.float32)
		for la in range(int(math.floor(lat0)), int(math.floor(lat1)) + 1):
			for lo in range(int(math.floor(lon0)), int(math.floor(lon1)) + 1):
				with rasterio.open(dem_tile(la, lo)) as src:
					tile = src.read(1)
				if tile.shape[1] != 3600:
					# north of 50 deg the tiles are 2400 (1800 past 60 deg, ...) px
					# wide: stretch them onto the one arc-second grid
					rr, cc = np.mgrid[0:3600, 0:3600].astype(np.float32)
					tile = ndimage.map_coordinates(tile, [rr, cc * tile.shape[1] / 3600.0], order=1, mode="nearest")
				# tile row r is at latitude la + 1 - r / 3600, column c at lo + c / 3600
				r0 = round((self.lat1 - la - 1) * 3600)
				c0 = round((lo - self.lon0) * 3600)
				rs, cs = max(r0, 0), max(c0, 0)
				re, ce = min(r0 + 3600, h), min(c0 + 3600, w)
				if rs < re and cs < ce:
					self.z[rs:re, cs:ce] = tile[rs - r0:re - r0, cs - c0:ce - c0]
		# the DSM includes trees and roofs: soften it a little
		self.z = ndimage.gaussian_filter(self.z, 1.0)

	def sample(self, lon, lat):
		r = (self.lat1 - np.asarray(lat)) * 3600
		c = (np.asarray(lon) - self.lon0) * 3600
		return ndimage.map_coordinates(self.z, [r, c], order=3, mode="nearest")


class ArcticDem:
	"""ArcticDEM 2 m heights round a lon/lat box (a surface model: trees and
	all), read straight from the cloud-optimised tiles and cached. Heights are
	over the ellipsoid, so they sit some metres off Copernicus's: callers
	only use them relative to each other."""

	def __init__(self, stage_id, lon0, lat0, lon1, lat1):
		from pyproj import Transformer
		self.to_ps = Transformer.from_crs(4326, 3413, always_xy=True)
		path = os.path.join(CACHE, stage_id + "_arcticdem.npz")
		if os.path.exists(path):
			d = np.load(path)
			self.x0, self.y1, self.z = float(d["x0"]), float(d["y1"]), d["z"]
			return
		cx, cy = self.to_ps.transform([lon0, lon1, lon0, lon1], [lat0, lat0, lat1, lat1])
		self.x0 = math.floor(min(cx) / 2.0) * 2.0
		self.y1 = math.ceil(max(cy) / 2.0) * 2.0
		w = int((math.ceil(max(cx) / 2.0) * 2.0 - self.x0) / 2.0)
		h = int((self.y1 - math.floor(min(cy) / 2.0) * 2.0) / 2.0)
		self.z = np.full((h, w), np.nan, np.float32)
		tiles = set()
		for x in np.linspace(self.x0, self.x0 + w * 2.0, 8):
			for y in np.linspace(self.y1 - h * 2.0, self.y1, 8):
				col, row = int((x + 4e6) // 1e5) + 1, int((y + 4e6) // 1e5) + 1
				sc, sr = int((x + 4e6) % 1e5 >= 5e4) + 1, int((y + 4e6) % 1e5 >= 5e4) + 1
				tiles.add((row, col, sr, sc))
		self._read(tiles, w, h)
		np.savez_compressed(path, x0=self.x0, y1=self.y1, z=self.z)

	def _read(self, tiles, w, h):
		import rasterio
		from rasterio.windows import Window
		env = {"GDAL_DISABLE_READDIR_ON_OPEN": "EMPTY_DIR"}
		if os.environ.get("HTTPS_PROXY"):
			env["GDAL_HTTP_PROXY"] = os.environ["HTTPS_PROXY"]
		with rasterio.Env(**env):
			for row, col, sr, sc in sorted(tiles):
				url = ARCTIC_URL.format(row=row, col=col, sr=sr, sc=sc)
				print("reading ArcticDEM", url.rsplit("/", 1)[1])
				with rasterio.open("/vsicurl/" + url) as src:
					c0 = round((self.x0 - src.transform.c) / 2.0)
					r0 = round((src.transform.f - self.y1) / 2.0)
					tile = src.read(1, window=Window(c0, r0, w, h), boundless=True, fill_value=-9999.0)
				tile[tile < -1000] = np.nan
				self.z = np.where(np.isnan(self.z), tile, self.z)

	def sample(self, lon, lat):
		x, y = self.to_ps.transform(np.asarray(lon), np.asarray(lat))
		c = (np.asarray(x) - self.x0) / 2.0 - 0.5
		r = (self.y1 - np.asarray(y)) / 2.0 - 0.5
		ok = ~np.isnan(self.z)
		v = ndimage.map_coordinates(np.where(ok, self.z, 0.0), [r, c], order=1, mode="nearest")
		w = ndimage.map_coordinates(ok.astype(np.float32), [r, c], order=1, mode="nearest")
		return np.where(w > 0.99, v, np.nan)


def fine_profile(adem, real, kx, ky, crest_r):
	"""The road's height every real metre from the 2 m model: across the road
	(5 m either side) the lower quarter of the samples, which keeps the odd
	tree overhanging the verge out of it, then a light smoothing (sigma 2.5 m)
	that takes out the model's noise but keeps crests a few tens of metres
	long. NaN where the model has no data."""
	tan = np.gradient(real, axis=0)
	tan /= np.linalg.norm(tan, axis=1)[:, None]
	nrm = np.c_[-tan[:, 1], tan[:, 0]]
	cross = []
	for o in np.arange(-5.0, 5.5, 1.0):
		q = real + nrm * o
		cross.append(adem.sample(q[:, 0] / kx, -q[:, 1] / ky))
	z = np.nanpercentile(np.stack(cross, 1), 25, axis=1)
	bad = np.isnan(z)
	if bad.all():
		sys.exit("no ArcticDEM along the road")
	if bad.any():
		z[bad] = np.interp(np.flatnonzero(bad), np.flatnonzero(~bad), z[~bad])
	# a surface model sees the treetops where the forest closes over a narrow
	# road: they only ever add height, so take the ground as the highest
	# curve under the samples that no road could beat: crests no sharper than
	# crest_r (a parabola rolled along underneath) and no slope steeper than
	# MAX_GRADE
	x = np.arange(-45.0, 46.0)
	z = ndimage.grey_opening(z, structure=-x * x / (2.0 * crest_r), size=len(x), mode="nearest")
	x = np.arange(-150.0, 151.0)
	z = ndimage.grey_erosion(z, structure=-MAX_GRADE * np.abs(x), size=len(x), mode="nearest")
	return ndimage.gaussian_filter1d(z, 2.5, mode="nearest"), bad


def camber_profile(cfg, real, dem, kx, ky):
	"""Rise per metre across the road, + where its right side is higher: into
	the bends, and with the hillside it's cut into (so now and then a bend
	leans the wrong way, as real back roads do). Real metre steps."""
	c = cfg["camber"]
	# (the bend as a whole: OSM draws a corner as a few kinks at its nodes)
	sm = np.c_[ndimage.gaussian_filter1d(real[:, 0], 8.0, mode="nearest"),
		ndimage.gaussian_filter1d(real[:, 1], 8.0, mode="nearest")]
	tan = np.gradient(sm, axis=0)
	tan /= np.linalg.norm(tan, axis=1)[:, None]
	# x east, z south: the right of a heading (tx, tz) is (-tz, tx), and a
	# left-hand bend turns the heading the other way round
	dt = np.gradient(tan, axis=0)
	left = -(tan[:, 0] * dt[:, 1] - tan[:, 1] * dt[:, 0])  # 1 / radius, + to the left, real metres
	left = ndimage.gaussian_filter1d(left, 6.0, mode="nearest")
	right = np.c_[-tan[:, 1], tan[:, 0]]
	q0 = real - right * 15.0
	q1 = real + right * 15.0
	hill = (dem.sample(q1[:, 0] / kx, -q1[:, 1] / ky) - dem.sample(q0[:, 0] / kx, -q0[:, 1] / ky)) / 30.0
	hill = ndimage.gaussian_filter1d(hill, 10.0, mode="nearest")
	cam = c["turn"] * left / cfg["scale"] + c["hill"] * hill
	cam = ndimage.gaussian_filter1d(np.clip(cam, -c["max"], c["max"]), 5.0, mode="nearest")
	return cam


def bumps(n, amp, seed):
	"""Small bumps and ripples every real metre: a few waves 9-30 m long with
	random phases, stronger on some stretches than others."""
	rng = np.random.default_rng(seed)
	x = np.arange(n, dtype=float)
	out = np.zeros(n)
	for wl, a in [(9.0, 0.3), (13.0, 0.45), (19.0, 0.5), (29.0, 0.55)]:
		ph = rng.uniform(0, 2 * np.pi)
		drift = ndimage.gaussian_filter1d(rng.normal(0, 1, n), 40.0) * 25.0  # the waves wander a little
		out += a * np.sin(2 * np.pi * x / wl + ph + drift)
	out /= np.abs(out).max()
	env = ndimage.gaussian_filter1d(rng.normal(0, 1, n), 60.0)
	env = 0.35 + 0.65 * np.clip((env - env.min()) / (np.ptp(env) + 1e-9), 0, 1)
	return out * env * amp


# --------------------------------------------------------------------------- geometry

def resample(xy, step):
	d = np.r_[0, np.cumsum(np.hypot(*np.diff(xy, axis=0).T))]
	s = np.arange(0, d[-1], step)
	return np.c_[np.interp(s, d, xy[:, 0]), np.interp(s, d, xy[:, 1])], s


def tri_interp(grid, x0, z0, cell, x, z):
	"""Heights of a grid mesh at points, split into triangles the way
	TrackBuilder splits its terrain (diagonal from (x, z) to (x+1, z+1))."""
	n = grid.shape[0]
	fx = np.clip((x - x0) / cell, 0, n - 1.001)
	fz = np.clip((z - z0) / cell, 0, n - 1.001)
	gx = fx.astype(int)
	gz = fz.astype(int)
	fx -= gx
	fz -= gz
	h00 = grid[gz, gx]
	h10 = grid[gz, gx + 1]
	h01 = grid[gz + 1, gx]
	h11 = grid[gz + 1, gx + 1]
	return np.where(fx >= fz, h00 + fx * (h10 - h00) + fz * (h11 - h10), h00 + fz * (h01 - h00) + fx * (h11 - h01))


def bake(stage_id, preview):
	cfg = STAGES[stage_id]
	os.makedirs(CACHE, exist_ok=True)
	os.makedirs(OUT, exist_ok=True)
	sc = cfg["scale"]
	ll = road_line(cfg, stage_id)
	# local metres: x east, z south (Godot's -z is north), centred on the stretch
	mid_lat = float(ll[:, 1].mean())
	kx = 111320.0 * math.cos(math.radians(mid_lat))
	ky = 110540.0
	real, s = resample(np.c_[ll[:, 0] * kx, -ll[:, 1] * ky], 1.0)
	a = int(cfg["from_m"] - cfg["lead"])
	b = int(cfg["to_m"] + cfg["tail"])
	if a < 0 or b >= len(real):
		sys.exit("stretch runs off the end of the road (%d m long)" % len(real))
	real = real[a:b + 1]
	# OSM's nodes leave little kinks: smooth the line a touch (sigma 3 m)
	sig = cfg.get("line_sigma", 3.0)
	real = np.c_[ndimage.gaussian_filter1d(real[:, 0], sig, mode="nearest"),
		ndimage.gaussian_filter1d(real[:, 1], sig, mode="nearest")]
	lon = real[:, 0] / kx
	lat = -real[:, 1] / ky
	pad = (FAR_HALF / sc + 500.0) / ky
	dem = Dem(lon.min() - pad * ky / kx, lat.min() - pad, lon.max() + pad * ky / kx, lat.max() + pad)
	# the road's height: the ground along it, with the trees and the 30 m
	# grid's smear taken out (median over 80 m, then smoothed over ~45 m)
	zr = dem.sample(lon, lat)
	zr = ndimage.median_filter(zr, 81, mode="nearest")
	zr = ndimage.gaussian_filter1d(zr, 45.0, mode="nearest")
	# with a finer model the road takes its height from that instead, every
	# crest and dip of it; `fine` is how far it is off the coarse profile, which
	# the ground beside the road takes too (fading out away from it), so a
	# crest is a little hill and not just the road heaped up
	fine = None
	if cfg.get("fine_dem") == "arcticdem":
		apad = 0.004
		adem = ArcticDem(stage_id, lon.min() - apad * 2, lat.min() - apad, lon.max() + apad * 2, lat.max() + apad)
		zf, gaps = fine_profile(adem, real, kx, ky, cfg.get("crest_r", 130.0))
		raw = dem.sample(lon, lat)
		zf -= np.median(zf[~gaps] - raw[~gaps])  # onto Copernicus's datum
		fine = zf - zr
		zr = zf
		print("2 m profile: %.1f m off the 30 m one at most, %d m without data" % (np.abs(fine).max(), gaps.sum()))
	if cfg.get("roughness"):
		zr = zr + bumps(len(zr), cfg["roughness"] / cfg["scale"], 1971)
	base = float(zr[int(cfg["lead"])])  # the start line is at height 0
	centre = real.mean(axis=0)
	road = (real - centre) * sc
	prof = (zr - base) * sc
	at = np.arange(len(prof), dtype=float)
	for m, h, half in cfg.get("jumps", []):
		d = (at - cfg["lead"] - m) * sc / half
		prof += np.where(np.abs(d) < 1.0, h * (0.5 + 0.5 * np.cos(d * np.pi)), 0.0)
	cam = camber_profile(cfg, real, dem, kx, ky) if cfg.get("camber") else None
	origin_lon = (centre[0]) / kx
	origin_lat = -(centre[1]) / ky

	def to_lonlat(gx, gz):
		return (gx / sc + centre[0]) / kx, -(gz / sc + centre[1]) / ky

	def dem_game(gx, gz):
		lo, la = to_lonlat(gx, gz)
		return (dem.sample(lo, la) - base) * sc

	# control points every `spacing` game metres, the start and finish on points
	cp, cs = resample(road, cfg["spacing"])
	lead_n = int(round(cfg["lead"] * sc / cfg["spacing"]))
	tail_n = int(round(cfg["tail"] * sc / cfg["spacing"]))
	# the far grid: square round the stage, its lines on whole far cells
	mn, mx = road.min(axis=0), road.max(axis=0)
	mid = (mn + mx) * 0.5
	fn = int(math.ceil(FAR_HALF * 2 / FAR_CELL)) + 1
	fx0 = math.floor((mid[0] - FAR_HALF) / FAR_CELL) * FAR_CELL
	fz0 = math.floor((mid[1] - FAR_HALF) / FAR_CELL) * FAR_CELL
	fgx, fgz = np.meshgrid(fx0 + np.arange(fn) * FAR_CELL, fz0 + np.arange(fn) * FAR_CELL)
	far = dem_game(fgx.ravel(), fgz.ravel()).reshape(fn, fn)
	# the near grid: square round the road plus the band, its edges on far lines
	ext = (mx - mn).max() * 0.5 + BAND + FAR_CELL
	nx0 = fx0 + math.floor((mid[0] - ext - fx0) / FAR_CELL) * FAR_CELL
	nz0 = fz0 + math.floor((mid[1] - ext - fz0) / FAR_CELL) * FAR_CELL
	span = math.ceil(ext * 2 / FAR_CELL + 1) * FAR_CELL
	nn = int(span / CELL) + 1
	ngx, ngz = np.meshgrid(nx0 + np.arange(nn) * CELL, nz0 + np.arange(nn) * CELL)
	gx, gz = ngx.ravel(), ngz.ravel()
	near = dem_game(gx, gz)
	dense, _ = resample(road, 1.0)
	dist, _ = cKDTree(dense).query(np.c_[gx, gz])
	# far from the road the near ground eases onto the distant mesh's own
	# surface, so the two meet without a seam where the near mesh stops
	t = np.clip((dist - DETAIL[0]) / (DETAIL[1] - DETAIL[0]), 0, 1)
	t = t * t * (3 - 2 * t)
	near = near * (1 - t) + tri_interp(far, fx0, fz0, FAR_CELL, gx, gz) * t
	if fine is not None:
		_, at_i = cKDTree(dense).query(np.c_[gx, gz])
		fade = np.clip((dist - 14.0) / 56.0, 0, 1)
		fade = 1 - fade * fade * (3 - 2 * fade)
		near = near + fine[np.clip(np.round(at_i / sc).astype(int), 0, len(fine) - 1)] * sc * fade
	near = near.reshape(nn, nn)
	dist = dist.reshape(nn, nn)
	lo_h = float(min(near.min(), far.min())) - 1.0
	q = lambda h: np.clip(np.round((h - lo_h) * 10.0), 0, 65535).astype("<u2")
	with open(os.path.join(OUT, stage_id + ".bin"), "wb") as f:
		f.write(q(near).tobytes())
		f.write(np.clip(np.round(dist / 4.0), 0, 255).astype(np.uint8).tobytes())
		f.write(q(far).tobytes())
	meta = {
		"credit": "Road: (c) OpenStreetMap contributors, ODbL (via Overture Maps). "
			"Terrain: Copernicus GLO-30 DEM, (c) DLR e.V. 2010-2014 and Airbus 2014-2018, provided under COPERNICUS by the "
			"European Union and ESA." + (" Road heights: ArcticDEM v4.1 2 m mosaic, Polar Geospatial Center "
			"(NSF-OPP awards 1043681, 1559691, 1542736, 1810976, 2129685), CC BY 4.0." if fine is not None else ""),
		"road": cfg["road"],
		"origin": [round(origin_lat, 6), round(origin_lon, 6)],
		"base_height": round(base, 1),
		"scale": sc,
		"points": [[round(float(x), 2), round(float(z), 2)] for x, z in cp],
		"lead": lead_n,
		"tail": tail_n,
		# heights along the route, `step` game metres apart from the first point
		"profile_step": 2.0,
		"profile": [round(float(h), 2) for h in np.interp(np.arange(0, cs[-1] + 2.0, 2.0) / sc,
			np.arange(len(prof)), prof)],
		"height_min": round(lo_h, 1),
		**({"camber": [round(float(c), 3) for c in np.interp(np.arange(0, cs[-1] + 2.0, 2.0) / sc,
			np.arange(len(cam)), cam)]} if cam is not None else {}),
		"near": {"x0": nx0, "z0": nz0, "n": nn, "cell": CELL, "band": BAND},
		"far": {"x0": fx0, "z0": fz0, "n": fn, "cell": FAR_CELL},
	}
	with open(os.path.join(OUT, stage_id + ".json"), "w") as f:
		json.dump(meta, f, separators=(",", ":"))
	climb = prof[-int(cfg["tail"])] - prof[int(cfg["lead"])]
	print("%s: %.0f m stage (game), climb %.0f m, %d control points, near grid %d^2, far grid %d^2"
		% (stage_id, (len(prof) - cfg["lead"] - cfg["tail"]) * sc, climb, len(cp), nn, fn))
	if preview:
		_preview(stage_id, near, nx0, nz0, nn, road, prof, sc, cam)


def _preview(stage_id, near, nx0, nz0, nn, road, prof, sc, cam=None):
	import matplotlib
	matplotlib.use("Agg")
	import matplotlib.pyplot as plt
	fig, (a, b) = plt.subplots(1, 2, figsize=(16, 7), gridspec_kw={"width_ratios": [1.3, 1]})
	ext = [nx0, nx0 + (nn - 1) * CELL, nz0 + (nn - 1) * CELL, nz0]
	a.imshow(near, extent=ext, cmap="terrain")
	a.contour(near, levels=np.arange(-600, 1500, 25), extent=[ext[0], ext[1], ext[3], ext[2]], colors="k", linewidths=0.3)
	a.plot(road[:, 0], road[:, 1], "r-", lw=1)
	a.set_title(stage_id + " (game metres, north up)")
	b.plot(np.arange(len(prof)) * sc, prof)
	b.set_title("road profile" + (" (red: camber x100)" if cam is not None else ""))
	if cam is not None:
		b.plot(np.arange(len(cam)) * sc, cam * 100.0, "r-", lw=0.5)
	b.grid(True)
	path = os.path.join(CACHE, stage_id + "_preview.png")
	plt.savefig(path, dpi=80, bbox_inches="tight")
	print("preview:", path)


if __name__ == "__main__":
	ap = argparse.ArgumentParser()
	ap.add_argument("stage", choices=sorted(STAGES))
	ap.add_argument("--preview", action="store_true")
	args = ap.parse_args()
	bake(args.stage, args.preview)
