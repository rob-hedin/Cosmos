# Cosmos

A Swift and Metal framework for macOS 27 and iOS/iPadOS 27 that shows the 11,975 stars within 200 light years in 3D, at their true relative positions, sized and colored from catalog data. Rotatable, zoomable, with toggleable star names and star selection.

## Modules

| Module | Status | What it does |
| --- | --- | --- |
| `StarCatalog` | Done | Loads the bundled CSV; computes 3D positions (light years, Sun at origin, equatorial frame), luminosity, temperature, estimated radius, and blackbody color; size normalization for both size modes |
| `StarRenderer` | First light | Metal renderer: one instanced draw of all stars with additive glow, Sun marker, `OrbitCamera` with rotate, zoom, pan, roll, reset and fling; picking, selection ring, fly-to, decluttered star names |
| `StarFieldUI` | First light | SwiftUI `StarFieldView`, `StarFieldScene` (macOS and iOS), `StarFieldWindow.open()` (macOS), mouse, trackpad and touch input, selection binding, `StarInfoCard`, `StarFieldBrowser` with name and size controls. |

## Usage

```swift
import StarCatalog

let catalog = try StarCatalog.bundled()
let sirius = catalog.star(named: "Sirius")
let sizes = catalog.normalizedSizes(for: .luminosity) // or .estimatedRadius
```

## Demo

```sh
swift run CosmosDemo
```

Opens a macOS window with every star, viewed from outside the 200 ly sphere with north up.

| Action | Input |
| --- | --- |
| Rotate | Drag (release while moving to fling) |
| Zoom | Scroll wheel, trackpad scroll or pinch |
| Pan | Shift-drag, right-drag or middle-drag |
| Roll | Trackpad rotate |
| Select a star | Click it (shows a ring and an info card; click empty space to deselect) |
| Fly to a star | Double-click it, then rotate around it |
| Reset | Double-click empty space |

On iPhone and iPad:

| Action | Input |
| --- | --- |
| Rotate | One-finger drag (release while moving to fling) |
| Zoom | Pinch, or scroll with an iPad trackpad or mouse |
| Pan | Two-finger drag |
| Roll | Two-finger rotate |
| Select a star | Tap it (tap empty space to deselect) |
| Fly to a star | Double-tap it |
| Reset | Double-tap empty space |

`CosmosDemo` runs on macOS; on iOS, use `StarFieldScene()` or `StarFieldView()` in an app target.

The controls at the top right turn star names and the reference rings on and off. The rings are 50, 100 and 200 ly from the Sun in three planes at right angles: the celestial equator (blue, labeled) and the two pole-to-pole planes through RA 0h/12h (green) and 6h/18h (amber). The controls also switch star size between luminosity and estimated radius. The Sun is marked with a ring and a label. Names appear for named stars bright enough to see with the naked eye from the camera's position, brightest first, without overlapping; the selected star is always labeled.

To show stars in your own app, use `StarFieldScene()` as a scene, place `StarFieldView()` in your UI, or call `StarFieldWindow.open()` from AppKit.

### Focus and routes

To open centered on a star, pass a focus with the span, in light years, across the view's shorter side. To show a route, pass star names in order: the stops are joined with lines, a tile lists each leg's distance and the total, and the view centers on the first stop and zooms to fit them all. Names are as shown on the info card, plus "Sun" or "Sol", a few common aliases such as "Alpha Centauri" and "Proxima", and catalog numbers such as "HIP 71683" or "HD 128620". Names that match nothing are listed in the tile. A focus, when given, decides the view.

```swift
StarFieldScene(focus: StarFieldFocus(star: "Vega", span: 20))
StarFieldView(route: ["Sol", "Alpha Centauri", "Sirius"])
StarFieldWindow.open(route: ["Sun", "Barnard's Star", "Wolf 359"])
```

The demo takes the same options:

```sh
swift run CosmosDemo --star Vega --span 20
swift run CosmosDemo --route "Sol, Alpha Centauri, Sirius"
```

## Data

`Sources/StarCatalog/Resources/stars.csv` is derived from the HYG database (stars within 200 ly). Temperatures come from B-V via the Ballesteros formula, falling back to spectral class and then the catalog color name. Radii are estimates from R ∝ √L / T².

## Requirements

Swift 6.4, macOS 27 or iOS/iPadOS 27. `StarCatalog` is pure Swift and also builds and tests on Linux, which CI uses.
