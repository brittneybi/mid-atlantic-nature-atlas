"""
Clean a GBIF download of iNaturalist observations (Maryland, Pennsylvania, DC)
into Power BI-ready files.

Usage:
    pip install pandas
    python scripts/prep_gbif.py data/raw/occurrence.txt

Outputs (in data/processed/):
    observations.csv         one row per observation
    effort_weekly.csv        observations + distinct observers per week, state, group
    effort_total_weekly.csv  same, all groups combined (distinct observers can't
                             be summed in DAX, so it's precomputed here)
"""
import csv
import hashlib
import sys
from pathlib import Path

import pandas as pd

STATES = {"Maryland", "Pennsylvania", "District of Columbia"}
WANTED = {
    "occurrenceID", "catalogNumber", "kingdom", "class", "order", "family",
    "genus", "species", "taxonRank", "scientificName", "stateProvince",
    "decimalLatitude", "decimalLongitude", "coordinateUncertaintyInMeters",
    "year", "month", "day", "recordedBy",
}
OUT = Path("data/processed")


def iconic_group(df):
    g = pd.Series("Other", index=df.index)
    g[df["kingdom"] == "Animalia"] = "Other animals"
    g[df["kingdom"] == "Plantae"] = "Plants"
    g[df["kingdom"] == "Fungi"] = "Fungi"
    g[df["class"] == "Aves"] = "Birds"
    g[df["class"] == "Insecta"] = "Insects"
    return g


def anon(name):
    if not isinstance(name, str) or not name:
        return None
    return hashlib.sha1(name.encode("utf-8")).hexdigest()[:10]


def main(src):
    chunks = pd.read_csv(
        src, sep="\t", dtype=str, usecols=lambda c: c in WANTED,
        chunksize=500_000, quoting=csv.QUOTE_NONE, on_bad_lines="skip",
        encoding="utf-8",
    )
    parts = []
    for i, ch in enumerate(chunks, 1):
        ch = ch[ch["stateProvince"].isin(STATES)]
        parts.append(ch)
        print(f"chunk {i}: kept {len(ch):,} rows")
    df = pd.concat(parts, ignore_index=True)

    # Observation ID: the trailing number of the iNaturalist URL
    ids = df["occurrenceID"].str.extract(r"(\d+)$")[0]
    if "catalogNumber" in df.columns:
        ids = ids.fillna(df["catalogNumber"])
    df["inat_id"] = ids

    # Dates and weeks
    parts_dt = {k: pd.to_numeric(df[k], errors="coerce") for k in ("year", "month", "day")}
    df["date"] = pd.to_datetime(parts_dt, errors="coerce")
    df = df.dropna(subset=["date", "inat_id"]).copy()
    df["week_start"] = (df["date"] - pd.to_timedelta(df["date"].dt.weekday, unit="D")).dt.normalize()
    df["week_of_year"] = df["date"].dt.isocalendar().week.astype(int)

    # Taxon group and anonymized observer
    df["group"] = iconic_group(df)
    df["observer_id"] = df["recordedBy"].map(anon)

    keep = [
        "inat_id", "date", "year", "week_of_year", "week_start", "stateProvince",
        "group", "kingdom", "class", "order", "family", "genus", "species",
        "scientificName", "taxonRank", "decimalLatitude", "decimalLongitude",
        "coordinateUncertaintyInMeters", "observer_id",
    ]
    OUT.mkdir(exist_ok=True)
    df[keep].to_csv(OUT / "observations.csv", index=False)

    eff = (df.groupby(["week_start", "stateProvince", "group"])
             .agg(observations=("inat_id", "size"), observers=("observer_id", "nunique"))
             .reset_index())
    eff.to_csv(OUT / "effort_weekly.csv", index=False)

    tot = (df.groupby(["week_start", "stateProvince"])
             .agg(observations=("inat_id", "size"), observers=("observer_id", "nunique"))
             .reset_index())
    tot.to_csv(OUT / "effort_total_weekly.csv", index=False)

    print(f"Wrote {len(df):,} observations to {OUT}/")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("Usage: python scripts/prep_gbif.py data/raw/occurrence.txt")
    main(sys.argv[1])
