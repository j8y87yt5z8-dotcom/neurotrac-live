import SwiftUI
import NeuroTracCore

/// Observation sheet after a session: walking, foot, knee, sensations.
struct ObservationsView: View {
    @ObservedObject var follow: FollowUpModel

    private func scaleBinding(_ key: String) -> Binding<Int> {
        return Binding<Int>(
            get: { follow.draft.scales[key] ?? -1 },
            set: { v in follow.setScale(key, v < 0 ? nil : v) }
        )
    }

    private func flagBinding(_ key: String) -> Binding<Bool> {
        return Binding<Bool>(
            get: { follow.draft.flags[key] ?? false },
            set: { v in
                if v { follow.draft.flags[key] = true } else { follow.draft.flags.removeValue(forKey: key) }
            }
        )
    }

    private func numberBinding(_ key: String) -> Binding<String> {
        return Binding<String>(
            get: {
                if let v = follow.draft.numbers[key] { return String(format: "%g", v) }
                return ""
            },
            set: { text in
                let t = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
                if let v = Double(t) { follow.draft.numbers[key] = v } else { follow.draft.numbers.removeValue(forKey: key) }
            }
        )
    }

    private func summary(_ o: ObservationRecord) -> String {
        var parts: [String] = []
        for it in Catalog.sidedScales {
            let d = o.scales[Catalog.sidedKey(it.key, side: "Droite")]
            let g = o.scales[Catalog.sidedKey(it.key, side: "Gauche")]
            if d != nil || g != nil {
                parts.append(trd(it.label) + tr(" D ") + (d.map { String($0) } ?? "—") + tr(" / G ") + (g.map { String($0) } ?? "—"))
            }
        }
        let flags = Catalog.flags.filter { o.flags[$0.key] == true }.map { trd($0.label) }
        if !flags.isEmpty { parts.append(flags.joined(separator: ", ")) }
        if !o.text.isEmpty { parts.append(o.text) }
        return parts.joined(separator: " — ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox(tr("Nouvelle fiche")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tr("Échelle 0 à 5 : ") + (0..<6).map { trd(Catalog.scaleLabels[$0] ?? "") }.joined(separator: " ; "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(Catalog.sidedScales, id: \.key) { item in
                            HStack {
                                Text(trd(item.label))
                                    .frame(width: 280, alignment: .leading)
                                Picker(tr("Droite"), selection: scaleBinding(Catalog.sidedKey(item.key, side: "Droite"))) {
                                    Text("—").tag(-1)
                                    ForEach(0..<6, id: \.self) { Text("\($0)").tag($0) }
                                }
                                .frame(width: 130)
                                Picker(tr("Gauche"), selection: scaleBinding(Catalog.sidedKey(item.key, side: "Gauche"))) {
                                    Text("—").tag(-1)
                                    ForEach(0..<6, id: \.self) { Text("\($0)").tag($0) }
                                }
                                .frame(width: 130)
                                Spacer()
                            }
                        }
                        Divider()
                        ForEach(Catalog.flags, id: \.key) { item in
                            Toggle(trd(item.label), isOn: flagBinding(item.key))
                        }
                        Divider()
                        ForEach(Catalog.numbers, id: \.key) { item in
                            HStack {
                                Text(trd(item.label))
                                    .frame(width: 280, alignment: .leading)
                                TextField("", text: numberBinding(item.key))
                                    .frame(width: 80)
                                Spacer()
                            }
                        }
                        TextField(tr("Notes libres (sensations dites par l'enfant, contexte…)"),
                                  text: $follow.draft.text, axis: .vertical)
                            .lineLimit(2...6)
                        HStack {
                            Button(tr("Enregistrer la fiche")) { follow.saveDraftObservation() }
                                .buttonStyle(.borderedProminent)
                            Text(follow.draftSaved)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(tr("Fiches précédentes")) {
                    VStack(alignment: .leading, spacing: 8) {
                        if follow.observations.isEmpty {
                            Text(tr("Aucune fiche pour l'instant.")).foregroundStyle(.secondary)
                        }
                        ForEach(follow.observations) { o in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Fmt.dateTime(o.date)).font(.headline)
                                    Text(summary(o)).font(.callout).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(tr("Supprimer")) { follow.deleteObservation(o.id) }
                                    .font(.caption)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
    }
}
