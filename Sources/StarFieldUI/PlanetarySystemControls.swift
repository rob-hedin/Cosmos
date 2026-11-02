import StarCatalog
import SwiftUI

/// The controls laid over a Planetary System view: the scale switch, pause, speed and the names toggle.
struct PlanetarySystemControls: View {
    @Binding var scale: PlanetarySystemScale
    @Binding var speed: SimulationSpeed
    @Binding var isPaused: Bool
    @Binding var showsLabels: Bool

    var body: some View {
        // Where the full controls don't fit, as on a phone, they show only their icons.
        ViewThatFits(in: .horizontal) {
            controls(compact: false)
            controls(compact: true)
        }
    }

    private func controls(compact: Bool) -> some View {
        HStack(spacing: 10) {
            if compact {
                Toggle("True scale", systemImage: "ruler", isOn: isTrueScale)
                    .toggleStyle(.button)
                    .labelStyle(.iconOnly)
                    .help("True scale: real distances and sizes")
            } else {
                Picker("Scale", selection: $scale) {
                    Text("Compressed").tag(PlanetarySystemScale.compressed)
                    Text("True scale").tag(PlanetarySystemScale.trueScale)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Compress distances and sizes so everything fits, or show them true to scale")
            }
            Button(isPaused ? "Play" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill") {
                isPaused.toggle()
            }
            .labelStyle(.iconOnly)
            .help(isPaused ? "Resume the orbits" : "Pause the orbits")
            Menu {
                Picker("Speed", selection: $speed) {
                    ForEach(SimulationSpeed.presets, id: \.self) { preset in
                        Text("\(preset.displayName)/s").tag(preset)
                    }
                }
            } label: {
                if compact {
                    Label("Speed", systemImage: "speedometer")
                        .labelStyle(.iconOnly)
                } else {
                    Label("\(speed.displayName)/s", systemImage: "speedometer")
                }
            }
            .fixedSize()
            .help("How fast the orbits run, per real second")
            Toggle("Names", systemImage: "textformat", isOn: $showsLabels)
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .help("Names of the star and bodies")
        }
        .padding(8)
        .background(.regularMaterial, in: .capsule)
    }

    private var isTrueScale: Binding<Bool> {
        Binding {
            scale == .trueScale
        } set: {
            scale = $0 ? .trueScale : .compressed
        }
    }
}
