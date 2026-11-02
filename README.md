# Cosmos

A Swift and Metal framework for macOS 27 and iOS/iPadOS 27 that shows the 11,975 stars within 200 light years in 3D, at their true relative positions, sized and colored from catalog data. Rotatable, zoomable, with toggleable star names and star selection.

## Modules

| Module | Status | What it does |
| --- | --- | --- |
| `StarCatalog` | Done | Loads the bundled CSV; computes 3D positions (light years, Sun at origin, equatorial frame), luminosity, temperature, estimated radius, and blackbody color; size normalization for both size modes |
| `StarRenderer` | First light | Metal renderer: one instanced draw of all stars with additive glow, Sun marker, `OrbitCamera` with rotate, zoom, pan, roll, reset and fling; picking, selection ring, fly-to, decluttered star names. `PlanetarySystemRenderer` draws one planetary system: lit spheres, belts, orbit lines, names. |
| `StarFieldUI` | First light | SwiftUI `StarFieldView`, `StarFieldScene` (macOS and iOS), `StarFieldWindow.open()` (macOS), mouse, trackpad and touch input, selection binding, `StarInfoCard`, `StarFieldBrowser` with search, filters, a route builder, and name and size controls. `PlanetarySystemView`, `PlanetarySystemInfoCard` and `PlanetarySystemWindow.open()` (macOS) for planetary systems; the star view's info card opens them. |

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
| Select a star | Click it (shows a ring and an info card; click empty space to deselect). Click the Sun's marker to select the Sun |
| Fly to a star | Double-click it, then rotate around it |
| Reset | Double-click empty space |

On iPhone and iPad:

| Action | Input |
| --- | --- |
| Rotate | One-finger drag (release while moving to fling) |
| Zoom | Pinch, or scroll with an iPad trackpad or mouse |
| Pan | Two-finger drag |
| Roll | Two-finger rotate |
| Select a star | Tap it (tap empty space to deselect). Tap the Sun's marker to select the Sun |
| Fly to a star | Double-tap it |
| Reset | Double-tap empty space |

`swift run CosmosDemo` runs on macOS. For iPhone and iPad, `Demo/CosmosDemo.swiftpm` is a small app package that builds with `xcodebuild` for the iOS Simulator (it depends on this package by path):

```sh
cd Demo/CosmosDemo.swiftpm
xcodebuild -scheme CosmosDemo \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath ../../.build/demo-ios build -quiet
xcrun simctl install "iPhone 18 Pro" ../../.build/demo-ios/Build/Products/Debug-iphonesimulator/CosmosDemo.app
xcrun simctl launch "iPhone 18 Pro" com.rob-hedin.CosmosDemo                  # the star field
xcrun simctl launch "iPhone 18 Pro" com.rob-hedin.CosmosDemo --solar-system   # the Solar System
```

Use another simulator name, such as `iPad Pro 11-inch (M5)`, for the iPad. The same build installs on both. Xcode may print "Supported platforms for the buildables in the current scheme is empty"; it is harmless. The manifest works out the package's name from the folder the repository is checked out in, so it works in a worktree too. Opening `CosmosDemo.swiftpm` in Xcode and changing its settings in the UI can rewrite the manifest.

In your own app, use `StarFieldScene()` or `StarFieldView()`.

The controls at the top right turn star names and the reference rings on and off. The rings are 50, 100 and 200 ly from the Sun in three planes at right angles: the celestial equator (blue, labeled) and the two pole-to-pole planes through RA 0h/12h (green) and 6h/18h (amber). The controls also switch star size between luminosity and estimated radius. The Sun is marked with a ring and a label. Names appear for named stars bright enough to see with the naked eye from the camera's position, brightest first, without overlapping; the selected star is always labeled.

To show stars in your own app, use `StarFieldScene()` as a scene, place `StarFieldView()` in your UI, or call `StarFieldWindow.open()` from AppKit.

### The Sun and planetary systems

The Sun isn't a row in the catalog, but you can select it: click or tap its marker, or pick "Sun" or "Sol" from search. Its info card is `Star.sun`, and the selection binding holds `Star.sunID` (`Int.min`, which no catalog uses; `catalog.star(withID:)` never returns it). In route mode, clicks still add stars only.

When the selected star has a planetary system, its info card has a **Show planetary system** button. On the Mac it opens a window titled with the system's name (pressing it again brings that window to the front); on iPhone and iPad it shows the system full screen, with a Done button. Which stars have a system comes from a `PlanetarySystemDirectory`, by the central star's catalog location. It defaults to `.builtIn`, which holds the Solar System, so the Sun's card offers it. Pass `.empty` for no buttons, or add your own systems:

```swift
let siriusSystem = try PlanetarySystem(name: "Sirius", centralStar: CentralStar(catalogStar: sirius), bodies: [...])
let directory = PlanetarySystemDirectory(PlanetarySystemDirectory.builtIn.systems + [siriusSystem])
StarFieldView(planetarySystems: directory)
StarFieldWindow.open(planetarySystems: .empty)
```

`StarFieldBrowser`, `StarFieldScene` and `StarFieldWindow.open` take the same `planetarySystems:` parameter. A system whose central star was described from scratch has no place in the catalog, so it never matches a star; show it with `PlanetarySystemView` or `PlanetarySystemWindow.open(system:)` yourself. To put the button on a catalog star, build the system against the same catalog the view shows, with `CentralStar(catalogStar:)`.

The demo opens the Solar System in its own window with `--solar-system`, and on the Mac the Planetary Systems menu has Show Solar System (⇧⌘S):

```sh
swift run CosmosDemo --solar-system
```

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

### Constellations

The Constellations toggle draws the 88 constellation figures, with their names, as seen from Earth: on a sphere 200 ly around the Sun, by each star's direction alone, so the figures are complete even where their stars lie far beyond the catalog (most of Orion, Deneb, Polaris). Zoom in toward the Sun and they look as they do in the night sky.

From code, pass `showsConstellations: true` to `StarFieldView`, `StarFieldBrowser`, `StarFieldScene` or `StarFieldWindow.open`, or run the demo with `--constellations`. Pass `showsConstellationsButton: false` to leave the toggle out of the controls. The figures come from [d3-celestial](https://github.com/ofrohn/d3-celestial) (BSD license, see `Sources/StarCatalog/Resources/constellations-LICENSE.txt`).

### Building a route

The route button turns on route mode: each star you click (or pick from search) becomes the next stop, and the lines and distance tile update as you go. The first stop starts a new route, replacing one passed in from code. Clicking a star that's already on the route asks whether to remove it or visit it again. The tile's undo button removes the last stop, and its clear button, shown whenever a route is on screen, removes the whole route. Turn route mode off to click stars normally; the route stays.

### Hiding the controls

`StarFieldScene`, `StarFieldBrowser` and `StarFieldWindow.open` take `showsRouteBuilder: false` to leave out the route builder, and `showsToolbar: false` to leave out the controls altogether (search, filters, route builder, names, rings and size):

```swift
StarFieldScene(showsRouteBuilder: false)
StarFieldWindow.open(route: ["Sol", "Sirius"], showsToolbar: false)
```

### Search and filters

The magnifying glass (⌘F) opens a search field that suggests stars as you type, by name, alias or HIP/HD number. Return or a click picks one: it's selected and the view glides to it.

The filter button hides stars by distance from the Sun, spectral class (O to M, white dwarfs, other) and brightness (absolute magnitude), and by single stars, stars in double and multiple systems, or both (the default). The selected star and route stops always stay visible. The catalog has no multiplicity column, so a star counts as part of a system if its spectral type lists a companion, or if another star lies within 0.3 ly of it across the sky at a matching distance.

From code, pass a filter, or filter the catalog yourself:

```swift
StarFieldView(filter: StarFilter(distance: 0...50, spectralClasses: [.g, .k]))
StarFieldView(filter: StarFilter(brightestAbsoluteMagnitude: 0, multiplicity: .multiple))
let bright = catalog.stars(matching: StarFilter(brightestAbsoluteMagnitude: 1))
let matches = catalog.search("alpha cen")   // Rigil Kentaurus, Toliman, Proxima Centauri
```

## Planetary systems

`StarCatalog` also models planetary systems: a central star (the Sun, a catalog star, or one described from scratch), bodies (planets, dwarf planets, moons, asteroids, comets) that each orbit a parent, and belts. Build one from Swift values or load it from JSON. Building checks everything and throws one `PlanetarySystemError` listing every problem. Periods that aren't given come from Kepler's third law. The Solar System ships built in.

```swift
let solar = try PlanetarySystem.solarSystem()
if let earth = solar.body(named: "Earth") {
    let days = solar.orbitalPeriod(of: earth) // about 365.25
}
```

### Viewing a planetary system

`PlanetarySystemView` shows one planetary system in 3D on macOS, iPhone and iPad, with the central star at the middle, its bodies as shaded spheres in the body's color (or a default for its kind) and its belts as faint rings. It reuses the star view's camera, gestures and name placement.

```swift
PlanetarySystemView()                          // the built-in Solar System
PlanetarySystemView(system: mySystem, scale: .trueScale, speed: .month)
PlanetarySystemView(selection: $selectedItem)  // read or set the selection (a PlanetarySystemItem)
```

Pass `showsControls: false`, `showsInfoCard: false` or `showsLabels: false` to leave those out. `scale`, `speed`, `isPaused` and `showsLabels` are starting values; the controls change them, and new values from your app replace what the controls set. `PlanetarySystemInfoCard(item:system:)` is the card on its own.

The controls at the top right switch the scale, pause the orbits, set their speed (1 day to 1 year per second; it opens at 1 week per second) and turn names on and off.

- **Compressed scale** (the default) squeezes distances so everything fits, and draws bodies larger than life. Each level is compressed on its own, so moons stay outside their enlarged planet, and a body keeps its true direction from its parent.
- **True scale** keeps real distances (a scene unit is one AU) and real sizes. Tiny bodies are still drawn at least a few points wide so they can be found.

| Action | Mac | iPhone and iPad |
| --- | --- | --- |
| Rotate, zoom, pan, roll | As in the star view | As in the star view |
| Select an item and show its card | Click it | Tap it |
| Deselect | Click empty space | Tap empty space |
| Fly to a body and follow it | Double-click it | Double-tap it |
| Back to the whole system | Double-click empty space | Double-tap empty space |

`PlanetarySystemView` also keeps names clear of regions you pass to `starFieldLabelObstacles(_:)`, as `StarFieldView` does. On the Mac, `PlanetarySystemWindow.open(system:)` shows a system in a window from AppKit code.

The card shows the body's kind, parent, distance, period, radius, mass when known, and the belt it lies in; for the central star, its spectral type, mass, radius and temperature. Names for crowded moons appear when you zoom in or select the moon.

## Data

`Sources/StarCatalog/Resources/stars.csv` is derived from the HYG database (stars within 200 ly). Temperatures come from B-V via the Ballesteros formula, falling back to spectral class and then the catalog color name. Radii are estimates from R ∝ √L / T².

## Requirements

Swift 6.4, macOS 27 or iOS/iPadOS 27. `StarCatalog` is pure Swift and also builds and tests on Linux, which CI uses.
