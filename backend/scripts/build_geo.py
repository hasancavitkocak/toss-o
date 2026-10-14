"""GeoNames verisinden ülke / il (bölge) / yerleşim listesini üretir.

Çıktı: backend/data/geo.json.gz
  regions: [ülke, bölge kodu, ad]
  places:  [ülke, bölge kodu, ad, enlem, boylam, nüfus]   (nüfus >= 1000)

Kaynak: https://download.geonames.org/export/dump/ (CC BY 4.0)

Kullanım:  python scripts/build_geo.py [indirilen-dosyaların-klasörü]
"""

import gzip
import io
import json
import os
import sys
import urllib.request
import zipfile

BASE = "https://download.geonames.org/export/dump/"
OUT = os.path.join(os.path.dirname(__file__), "..", "data", "geo.json.gz")

# GeoNames'te İngilizce/eksik yazılan il adları
TR_FIX = {"Istanbul": "İstanbul", "Canakkale": "Çanakkale", "Hakkâri": "Hakkari"}


def fetch(name, cache):
    path = os.path.join(cache, name) if cache else None
    if path and os.path.exists(path):
        with open(path, "rb") as f:
            return f.read()
    print(f"indiriliyor: {name}")
    with urllib.request.urlopen(BASE + name) as r:
        return r.read()


def region_name(country, name):
    # "State of Berlin" -> "Berlin", "Niğde Province" -> "Niğde", "Osaka Prefecture" -> "Osaka"
    name = name.removeprefix("State of ")
    for suffix in (" Province", " Prefecture"):
        name = name.removesuffix(suffix)
    if country == "TR":
        name = TR_FIX.get(name, name)
    return name


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    cache = sys.argv[1] if len(sys.argv) > 1 else None
    regions = {}
    for line in fetch("admin1CodesASCII.txt", cache).decode("utf-8").splitlines():
        code, name = line.split("\t")[:2]
        country, region = code.split(".", 1)
        regions[(country, region)] = region_name(country, name)

    raw = zipfile.ZipFile(io.BytesIO(fetch("cities1000.zip", cache))).read("cities1000.txt")
    countries_with_regions = {c for c, _ in regions}
    places = []
    for line in raw.decode("utf-8").splitlines():
        r = line.split("\t")
        country, region = r[8], r[10]
        pop = int(r[14] or 0)
        if pop < 1000:
            continue
        if (country, region) not in regions:
            # Bölgesi olmayan küçük ülkeler tek bölge olarak eklenir
            if country in countries_with_regions:
                continue
            region = "00"
            regions.setdefault((country, region), None)
        places.append([country, region, r[1], round(float(r[4]), 5), round(float(r[5]), 5), pop])

    used = {(p[0], p[1]) for p in places}
    out = {
        "regions": sorted([c, r, n] for (c, r), n in regions.items() if (c, r) in used),
        "places": places,
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with gzip.open(OUT, "wt", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    countries = {r[0] for r in out["regions"]}
    print(f"{len(countries)} ülke, {len(out['regions'])} bölge, {len(places)} yerleşim -> {OUT}")


if __name__ == "__main__":
    main()
