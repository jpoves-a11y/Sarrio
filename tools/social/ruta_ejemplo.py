"""Ruta de ejemplo (GPX) de un punto de salida a una cima siguiendo los senderos de OpenStreetMap.

Para la cuenta de demostración que se usa al grabar vídeos de marketing: nunca para una cuenta real.
Variables: VIA="lat,lon;lat,lon" (puntos de paso en orden), COTA=<altitud oficial del pico>,
EXPLORAR=<regex> (lista los nombres de la zona y sale), RUTA_CACHE (caché de descargas).

  python3 -I ruta.py <nombre> <lat_salida> <lon_salida> <lat_cima> <lon_cima> <fecha_hora_salida_iso> <salida.gpx> [regex_cima] [regex_salida]
Las coordenadas son aproximadas: si se dan las regex, se usan el pico y el punto de salida de OSM con ese nombre.

Altitud: OpenTopoData (EU-DEM 25 m). Horas: función de Tobler con paradas cortas, ida y vuelta.
Datos de senderos © OpenStreetMap contributors (ODbL).
"""
import heapq, json, math, sys, time, urllib.parse, urllib.request
from datetime import datetime, timedelta

import re
name, slat, slon, plat, plon, start_iso, out = sys.argv[1], *map(float, sys.argv[2:6]), sys.argv[6], sys.argv[7]
peak_re = sys.argv[8] if len(sys.argv) > 8 else None
start_re = sys.argv[9] if len(sys.argv) > 9 else None

def dist(a, b):
    R = 6371000
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dp, dl = p2 - p1, math.radians(b[1] - a[1])
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(h))

import hashlib, os
CACHE = os.environ.get("RUTA_CACHE", "/tmp/sarrio-osm-cache")
os.makedirs(CACHE, exist_ok=True)

def fetch(url, data=None, tries=5):
    key = os.path.join(CACHE, hashlib.sha1((url + str(data)).encode()).hexdigest() + ".json")
    if os.path.exists(key):
        return json.load(open(key))
    r = _fetch(url, data, tries)
    json.dump(r, open(key, "w"))
    return r

def _fetch(url, data=None, tries=5):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, data=data, headers={"User-Agent": "sarrio-ruta-ejemplo"})
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.loads(r.read())
        except Exception as e:
            if i == tries - 1: raise
            time.sleep(6 * (i + 1))

# 1. Senderos de la zona: API oficial de OSM, en teselas pequeñas (política de uso: pocas peticiones, zonas pequeñas)
pad = 0.02
s, w = min(slat, plat) - pad, min(slon, plon) - pad
n, e = max(slat, plat) + pad, max(slon, plon) + pad
step = 0.04
nodes, tags_nodes, ways = {}, {}, {}
la = s
while la < n:
    lo = w
    while lo < e:
        bb = f"{lo:.5f},{la:.5f},{min(lo + step, e):.5f},{min(la + step, n):.5f}"
        d = fetch(f"https://api.openstreetmap.org/api/0.6/map.json?bbox={bb}")
        for el in d["elements"]:
            if el["type"] == "node":
                nodes[el["id"]] = (el["lat"], el["lon"])
                if el.get("tags"): tags_nodes[el["id"]] = el["tags"]
            elif el["type"] == "way":
                ways[el["id"]] = el
        time.sleep(1)
        lo += step
    la += step
HW = re.compile(r"path|footway|track|bridleway|steps|unclassified|service|via_ferrata|tertiary|residential")
graph = {}
for el in ways.values():
    t = el.get("tags", {})
    if not HW.fullmatch(t.get("highway", "")): continue
    ids = el["nodes"]
    for a, b in zip(ids, ids[1:]):
        if a in nodes and b in nodes:
            d = dist(nodes[a], nodes[b])
            graph.setdefault(a, []).append((b, d)); graph.setdefault(b, []).append((a, d))

def find(rx, near, peak=False):
    best = None
    for k, t in tags_nodes.items():
        if peak and t.get("natural") not in ("peak", "volcano"): continue
        if re.search(rx, t.get("name", ""), re.I):
            dd = dist(nodes[k], near)
            if dd < 6000 and (best is None or dd < best[0]): best = (dd, k, t)
    if not peak:
        for el in ways.values():
            t = el.get("tags", {})
            if re.search(rx, t.get("name", ""), re.I) and not t.get("highway"):
                pts = [nodes[i] for i in el["nodes"] if i in nodes]
                if pts:
                    c = (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))
                    dd = dist(c, near)
                    if dd < 6000 and (best is None or dd < best[0]): best = (dd, None, t, c)
    return best

if os.environ.get("EXPLORAR"):
    rx = re.compile(os.environ["EXPLORAR"], re.I)
    for k, t in tags_nodes.items():
        if rx.search(t.get("name", "")): print("node", nodes[k], t.get("name"), t.get("natural") or t.get("tourism") or t.get("amenity") or "", t.get("ele", ""))
    for el in ways.values():
        t = el.get("tags", {})
        if rx.search(t.get("name", "")) and not t.get("highway"):
            pts = [nodes[i] for i in el["nodes"] if i in nodes]
            if pts: print("way ", pts[0], t.get("name"), t.get("tourism") or t.get("amenity") or "")
    sys.exit()

if peak_re:
    f = find(peak_re, (plat, plon), peak=True)
    if f: plat, plon = nodes[f[1]]; print(f"{name}: cima OSM «{f[2].get('name')}» {f[2].get('ele','')} m")
if start_re:
    f = find(start_re, (slat, slon))
    if f:
        slat, slon = nodes[f[1]] if f[1] else f[3]; print(f"{name}: salida OSM «{f[2].get('name')}»")

def nearest(pt):
    return min(graph, key=lambda k: dist(nodes[k], pt))

# 2. Camino más corto (Dijkstra) por senderos, pasando por los puntos de VIA en orden
def dijkstra(src, dst):
    best, prev, pq = {src: 0}, {}, [(0, src)]
    while pq:
        d, u = heapq.heappop(pq)
        if u == dst: break
        if d > best.get(u, 1e18): continue
        for v, w2 in graph[u]:
            nd = d + w2
            if nd < best.get(v, 1e18):
                best[v], prev[v] = nd, u
                heapq.heappush(pq, (nd, v))
    if dst not in best: return None
    path, u = [dst], dst
    while u != src:
        u = prev[u]; path.append(u)
    return [nodes[k] for k in reversed(path)]

vias = [tuple(map(float, v.split(","))) for v in os.environ.get("VIA", "").split(";") if v]
stops = [(slat, slon)] + vias + [(plat, plon)]
pts = [stops[0]]
for a_, b_ in zip(stops, stops[1:]):
    na, nb = nearest(a_), nearest(b_)
    leg_ = dijkstra(na, nb) if dist(nodes[na], a_) < 300 and dist(nodes[nb], b_) < 300 else None
    if leg_:
        pts += leg_
        print(f"{name}: tramo por sendero ({len(leg_)} nodos)")
    else:
        print(f"{name}: tramo sin sendero en OSM, en línea recta ({dist(a_, b_):.0f} m)")
    pts.append(b_)

# 3. Un punto cada ~25 m
dense = [pts[0]]
for a, b in zip(pts, pts[1:]):
    d = dist(a, b); k = max(1, int(d // 25))
    for i in range(1, k + 1):
        t = i / k
        dense.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))

# 4. Altitud (EU-DEM 25 m), de 100 en 100 puntos y sin pasar de 1 petición por segundo
eles = []
for i in range(0, len(dense), 100):
    chunk = dense[i:i + 100]
    locs = "|".join(f"{la:.6f},{lo:.6f}" for la, lo in chunk)
    res = fetch(f"https://api.opentopodata.org/v1/eudem25m?locations={locs}")
    eles += [r["elevation"] for r in res["results"]]
    time.sleep(1.1)
# Suaviza el ruido del modelo de terreno
sm = [sum(eles[max(0, i - 2):i + 3]) / len(eles[max(0, i - 2):i + 3]) for i in range(len(eles))]
# El DEM aplana las cimas afiladas: en los últimos 200 m se lleva la altitud, poco a poco, a la cota del pico
peak_ele = float(os.environ.get("COTA", "nan"))
if not math.isnan(peak_ele):
    for i, pnt in enumerate(dense):
        d = dist(pnt, (plat, plon))
        if d < 200:
            w = (1 - d / 200) ** 1.5
            sm[i] = sm[i] * (1 - w) + max(sm[i], peak_ele - 3) * w

# 5. Horas: Tobler (km/h = 6·e^(-3.5·|pendiente+0.05|)), un poco más lento que el teórico, ida y vuelta
def leg(points, alts, t0):
    out_pts, t = [], t0
    since_break = 0.0
    for i, (p, z) in enumerate(zip(points, alts)):
        if i:
            d = dist(points[i - 1], p)
            slope = (z - alts[i - 1]) / d if d else 0
            v = 6 * math.exp(-3.5 * abs(slope + 0.05)) * 0.82
            dt = d / (max(v, 0.6) / 3.6)
            t += timedelta(seconds=dt); since_break += dt
            if since_break > 75 * 60:  # parada corta cada hora y cuarto
                t += timedelta(minutes=6); since_break = 0
        out_pts.append((p, z, t))
    return out_pts, t

t0 = datetime.fromisoformat(start_iso)
up, t_top = leg(dense, sm, t0)
down, _ = leg(list(reversed(dense)), list(reversed(sm)), t_top + timedelta(minutes=25))
track = up + down

gain = sum(max(0, b - a) for a, b in zip(sm, sm[1:]))
print(f"{name}: {sum(dist(a, b) for a, b in zip(dense, dense[1:]))/1000:.1f} km ida, +{gain:.0f} m, cima {max(sm):.0f} m (DEM), subida {(t_top - t0)}, total {(track[-1][2] - t0)}")

# 6. GPX
def iso(t): return t.astimezone().astimezone(tz=None).isoformat() if t.tzinfo else t.isoformat() + "Z"
with open(out, "w") as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n<gpx version="1.1" creator="Sarrio (ruta de ejemplo)" xmlns="http://www.topografix.com/GPX/1/1">\n')
    f.write(f"<metadata><name>{name}</name><desc>Ruta de ejemplo generada con senderos de OpenStreetMap (© OpenStreetMap contributors) y EU-DEM.</desc></metadata>\n")
    f.write(f"<trk><name>{name}</name><type>hiking</type><trkseg>\n")
    for (la, lo), z, t in track:
        ts = t.astimezone(tz=None).strftime("%Y-%m-%dT%H:%M:%S%z")
        ts = ts[:-2] + ":" + ts[-2:]
        f.write(f'<trkpt lat="{la:.6f}" lon="{lo:.6f}"><ele>{z:.1f}</ele><time>{ts}</time></trkpt>\n')
    f.write("</trkseg></trk>\n</gpx>\n")
print(f"{name}: {len(track)} puntos → {out}")
