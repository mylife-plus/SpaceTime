# GPX/KMZ Upload — How "New Memories" Is Calculated

When you upload a GPX or KMZ track, SpaceTime does **not** create one memory for every GPS point. Instead, it groups nearby points into stops and only creates memories for stops that are not already in your library.

---

## Step-by-step pipeline

```
Raw track points
    ↓  Ignore rules (optional — skip certain placemarks)
Filtered points
    ↓  Duplicate check vs your existing library
Remaining entries
    ↓  Cluster by Min time apart + Min distance apart
New memories
```

Each number on the upload screen comes from a different step.

---

## What each number means

| Label | Meaning |
|-------|---------|
| **Entries** | Total GPS points / stops found in the file |
| **Ignored entries** | Points removed by your ignore rules (e.g. marker name or text filter) |
| **Duplicate entries** | Points that **already match a memory** in your library (same date + location). Counted **before** clustering. |
| **Remaining entries** | Entries − Ignored − Duplicates |
| **New memories** | How many **new** memories would be created after grouping nearby points. Only groups that are **not** already in your library count here. |

**Important:** "Remaining entries" and "New memories" are not the same. Many raw points can merge into one memory.

---

## Memory creation settings

Two settings control how points are grouped:

- **Min time apart** — e.g. 1 min, 5 min, 30 min, 1 hour  
- **Min distance apart** — e.g. 10 m, 25 m, 50 m, 100 m, 1 km  

**Default:** 5 minutes and 50 meters.

### The rule (AND to start a new memory)

Points are sorted by time. The app walks through them in order.

Points **stay in the same memory** when they are still:

- within **X** of the current group start in time, **or**
- within **Y** meters of that same anchor on the map

A **new memory** starts only when the next point is **both**:

- at least **X** apart in time from the group start, **and**
- at least **Y** meters away on the map from that same anchor

In short:

> Merge while still within min time *or* min distance. Start a new memory only when far enough in **time and distance**.

Each memory uses the **first point** in its group (time + location) as its representative.

---

## Example

**Settings:** 5 min apart, 25 m apart

| Point | Time from anchor | Distance from anchor | Result |
|-------|------------------|----------------------|--------|
| A | — | — | Memory 1 starts (anchor = A) |
| B | 2 min | 100 m | Merged (still within 5 min, even though > 25 m) |
| C | 6 min | 10 m | Merged (still within 25 m, even though > 5 min) |
| D | 6 min | 30 m | **New memory** (6 min ≥ 5 min **and** 30 m ≥ 25 m) |

**Result:** 2 memories from 4 points.

---

## How changing the settings affects the count

| Change | Typical effect |
|--------|----------------|
| **Lower** min time or distance | More splits → **more** new memories |
| **Higher** min time or distance | More merging → **fewer** new memories |

Changing either dropdown updates the preview immediately (the file does not need to be re-uploaded).

The **date range** (From / To) also filters which points are included, so it can change the new-memory count as well.

---

## Why "New memories" can show 0

Even when points look far apart, the count can be 0 for these reasons:

1. **Everything is already in your library**  
   If those locations and dates already exist as memories, duplicate detection removes them → **0 new memories**, even if "Remaining entries" is greater than 0.

2. **Distance is measured from the group start, not point-to-point**  
   If point B and point C are 40 m apart from each other, but both are within 25 m of the **first** point in the group, they still merge into one memory.  
   "Entries are further apart" often refers to **consecutive** points; the app uses distance from the **start of the current group**.

3. **Stricter settings merge more points**  
   Raising min distance (e.g. 25 m → 100 m) groups more points together → fewer clusters → the count can drop, including to 0.

4. **Date filter**  
   If the selected date range excludes most points, the count can drop to 0.

---

## Summary (one paragraph)

SpaceTime groups nearby track points into single memories using your **Min time apart** and **Min distance apart** settings. Points stay in one memory while they are still within the min time *or* the min distance of the group start. A new memory starts only when a point is far enough in **both** time and distance. **New memories** is the number of those groups that do not already exist in your library, not the raw number of GPS points in the file.

---

## Simple analogy

Think of a trip with many GPS pings along a path. You usually want one memory per **stop** or **meaningful place**, not one per step. Min time and min distance define what counts as a new stop versus staying at the same visit.
