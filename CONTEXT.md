# Cosmos

A browser for the stars near the Sun, and for the planetary systems around them.

## Language

### Stars

**Star**:
One entry in the star catalog: a star within 200 light years of the Sun.
_Avoid_: object, point

**Multiple star**:
A **Star** that has one or more companion stars bound to it. The star view's filter calls these "multiple star systems".
_Avoid_: star system (on its own, it is ambiguous with **Planetary System**)

### Planetary systems

**Planetary System**:
A **Central Star** together with every **Body** and **Belt** that orbits it.
_Avoid_: solar system (that is our own one only), star system

**Solar System**:
The **Planetary System** of the Sun. It ships as the built-in example.

**Central Star**:
The star at the middle of a **Planetary System**. It is either a catalog **Star** or a star described from scratch. A system has exactly one for now; systems with more than one are planned.

**Body**:
Anything with its own orbit in a **Planetary System** that is not a star. Every Body has a **Kind** and orbits a **Parent**.
_Avoid_: satellite, object

**Kind**:
What sort of **Body** it is: planet, dwarf planet, moon, asteroid or comet.

**Parent**:
What a **Body** orbits: the **Central Star**, or another **Body** (a moon's Parent is its planet).

**Belt**:
A region of many small bodies around a **Parent**, drawn as a ring rather than as individual **Bodies** (the asteroid belt, the Kuiper belt). A **Body** can lie within a Belt (Ceres within the asteroid belt) while still being its own **Body**.

**Orbit**:
The path a **Body** follows around its **Parent**. Only the distance is required; an Orbit given with nothing else is circular and flat.

**Compressed scale**:
The view where distances are squeezed and **Bodies** are drawn larger than life, so everything can be seen at once. The view opens in this scale.
_Avoid_: log scale, fake scale

**True scale**:
The view where distances and sizes keep their real proportions.

## Relationships

- A **Planetary System** has one **Central Star**, and any number of **Bodies** and **Belts**.
- Each **Body** has one **Parent**; Bodies nest (Sun → Earth → Moon).
- A moon's **Parent** is a planet, dwarf planet or asteroid. Planets, dwarf planets, asteroids and comets have the **Central Star** as their **Parent**.
- A **Belt** has a **Parent** and an inner and outer edge.
- The **Solar System**'s **Central Star** is the catalog's Sun.

## Flagged ambiguities

- "Star system" was used both for a star with companions and for a star with its planets. Resolved: **Multiple star** for the first, **Planetary System** for the second.
- "Satellite" was used for anything orbiting the star. Resolved: **Body**; "moon" is the **Kind** for a Body whose **Parent** is another Body.
