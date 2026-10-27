import AppKit
import SwiftUI
import TapmixCore
import UniformTypeIdentifiers

struct AutoEQCatalogView: View {
    let profiles: [AutoEQProfile]
    let onSelect: (AutoEQProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [AutoEQProfile] {
        guard !query.isEmpty else { return profiles }
        return profiles.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AutoEQ profiles")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
            }

            TextField("Search headphones", text: $query)
                .textFieldStyle(.roundedBorder)

            List(filtered) { profile in
                Button(profile.name) {
                    onSelect(profile)
                    dismiss()
                }
                .buttonStyle(.plain)
            }

            Text("\(filtered.count) of \(profiles.count) profiles")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 420, height: 460)
    }
}

struct AudioUnitPickerView: View {
    let units: [AudioUnitInfo]
    let selected: AudioUnitSelection?
    let onSelect: (AudioUnitSelection?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [AudioUnitInfo] {
        guard !query.isEmpty else { return units }
        return units.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Audio Unit Effect")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
            }

            TextField("Search installed effects", text: $query)
                .textFieldStyle(.roundedBorder)

            List {
                Button {
                    onSelect(nil)
                    dismiss()
                } label: {
                    HStack {
                        Text("None")
                        Spacer()
                        if selected == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .buttonStyle(.plain)

                ForEach(filtered) { unit in
                    Button {
                        onSelect(unit.selection)
                        dismiss()
                    } label: {
                        HStack {
                            Text(unit.name)
                            Spacer()
                            if unit.selection == selected {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("\(filtered.count) of \(units.count) installed")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 440, height: 470)
    }
}
