# Planetary System view: design

Agreed with Robert on 2 November 2026. Terms follow `CONTEXT.md`.

## What it is

A new 3D view of one **Planetary System**: the **Central Star** at the middle, and its **Bodies** and **Belts** in orbit. It reuses the star view's camera, gestures and renderer. It works on Mac, iPhone and iPad.

## Input

- **Central Star**: either a catalog star matched by name, or one described from scratch. When described from scratch, the spectral type is required, and mass, radius and temperature are optional and estimated from it. Catalog stars get an estimated mass. One star for now; more are planned for later.
- **Body**: name, Kind, Parent, distance (AU) and radius (km) are required. Mass (Earth masses), period, color, starting position, eccentricity and inclination are optional. Without them, the orbit is circular and flat, and the period is worked out from the Parent's mass.
- **Kinds**: planet, dwarf planet, moon, asteroid, comet. A moon orbits a planet, dwarf planet or asteroid. The other kinds orbit the star.
- **Belt**: name, Parent, and inner and outer edges in AU. Bodies such as Ceres lie within a Belt.
- Apps supply systems as Swift values or as a JSON file.
- Bad input (an unknown Parent, a loop, a negative distance, a Kind rule broken) fails with the full list of problems.

## Built-in Solar System

Ships as JSON and is tied to the catalog's Sun. It includes the 8 planets; Ceres, Pluto, Eris, Haumea and Makemake; the Moon, Io, Europa, Ganymede, Callisto, Titan, Triton and Charon; and the asteroid belt and Kuiper belt. No comets.

## The view

- **Scale**: a switch between Compressed and True scale, opening in Compressed. Each level is compressed on its own, so moons stay outside their enlarged planet.
- **Look**: shaded spheres, with the Body's color or a default per Kind. Belts are faint rings. Saturn-style rings are left for later.
- **Motion**: animated orbits, with pause and speeds from 1 day to 1 year per second. Real positions for a chosen date may come later.
- **Interaction**: tap for an info card, names on screen, double-click to fly to a Body.
- **Info card**: Kind, Parent, distance, period, radius, mass when known, and the Belt it lies in.
- **Opening it**: a "Show planetary system" button on the star view's info card when that star has a system, and a standalone view for apps.

## Delivery: three PRs

1. The data model, JSON loading, the input checks and the Solar System data, with tests.
2. The 3D view: rendering, scale switch, animation, selection, names and info card.
3. The star view's info-card button and the demo app.

## Later

Multiple central stars, real positions for a date, planetary rings, and comets in the built-in data.
