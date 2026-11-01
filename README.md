# Cosmos

A Swift and Metal framework for macOS 27 and iOS/iPadOS 27 that shows the 11,975 stars within 200 light years in 3D, at their true relative positions, sized and colored from catalog data. Rotatable, zoomable, with toggleable star names and star selection.

## Modules

| Module | Status | What it does |
| --- | --- | --- |
| `StarCatalog` | Done | Loads the bundled CSV; computes 3D positions (light years, Sun at origin, equatorial frame), luminosity, temperature, estimated radius, and blackbody color; size normalization for both size modes |
| `StarRenderer` | First light | Metal renderer: one instanced draw of all stars with additive glow, Sun marker, `OrbitCamera` with rotate, zoom, pan, roll, reset and fling. Labels to come |
| `StarFieldUI` | First light | SwiftUI `StarFieldView`, `StarFieldScene` (macOS and iOS), `StarFieldWindow.open()` (macOS), mouse and trackpad input. Touch input and selection to come |

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
| Reset | Double-click |

To show stars in your own app, use `StarFieldScene()` as a scene, place `StarFieldView()` in your UI, or call `StarFieldWindow.open()` from AppKit.

## Data

`Sources/StarCatalog/Resources/stars.csv` is derived from the HYG database (stars within 200 ly). Temperatures come from B-V via the Ballesteros formula, falling back to spectral class and then the catalog color name. Radii are estimates from R ∝ √L / T².

## Requirements

Swift 6.4, macOS 27 or iOS/iPadOS 27. `StarCatalog` is pure Swift and also builds and tests on Linux, which CI uses.
