import SwiftUI
import NeuroTracCore

/// Debug mode: everything the device sends, packet by packet.
/// Read-only: nothing is sent to the device from this screen.
struct DebugView: View {
    @ObservedObject var model: LiveModel

    private var filteredRows: [DebugRow] {
        let f = model.debugFilter.trimmingCharacters(in: .whitespaces)
        let rows: [DebugRow]
        if f.isEmpty {
            rows = model.debugRows
        } else {
            let ids = Set(f.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Int($0) })
            rows = model.debugRows.filter { $0.packetId == -1 || ids.contains($0.packetId) }
        }
        return Array(rows.suffix(150).reversed())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                statsTable
                stream
            }
            .padding(20)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        GroupBox(tr("Outils")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField(tr("Annoter ce moment (ex. « programme NMES lancé »)"), text: $model.debugNote)
                        .onSubmit { model.addDebugNote() }
                    Button(tr("Annoter")) { model.addDebugNote() }
                }
                HStack {
                    TextField(tr("Filtrer par n° de paquet (ex. 11, 202)"), text: $model.debugFilter)
                        .frame(maxWidth: 300)
                    Toggle(tr("Figer l'affichage"), isOn: $model.debugPaused)
                    Spacer()
                    Button(tr("Copier le résumé")) { model.copyToPasteboard(model.debugSummary()) }
                    Button(tr("Ouvrir le dossier des fichiers")) { model.openDataFolder() }
                }
                Text(tr("Chaque trame reçue est enregistrée avec l'heure dans le fichier « trames_….log » (dossier Documents/NeuroTracLive), annotations comprises. Envoie-moi ce fichier après un essai."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Table by packet type

    private func hexText(_ s: PacketStat, latest: Double) -> Text {
        var out = Text("")
        for (i, b) in s.last.enumerated() {
            let h = String(format: "%02X ", b)
            var t = Text(h)
            if let lc = s.lastChangeT[i], latest - lc < 3 {
                t = t.foregroundColor(.red).bold()          // just changed
            } else if s.changed.contains(i) {
                t = t.foregroundColor(.orange)              // has already changed
            }
            out = out + t
        }
        return out
    }

    private var statsTable: some View {
        GroupBox(tr("Paquets par type — orange : l'octet a déjà changé, rouge : changé il y a moins de 3 s")) {
            VStack(alignment: .leading, spacing: 4) {
                if model.debugStats.isEmpty {
                    Text(tr("Aucun paquet reçu pour l'instant."))
                        .foregroundStyle(.secondary)
                }
                let latest = model.debugStats.map { $0.lastT }.max() ?? 0
                ForEach(model.debugStats, id: \.id) { s in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("n°\(s.id)")
                            .frame(width: 52, alignment: .leading)
                            .bold()
                        Text(DebugTracker.isKnown(id: s.id) ? tr("connu") : tr("INCONNU"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(DebugTracker.isKnown(id: s.id) ? Color.secondary : Color.purple)
                            .frame(width: 60, alignment: .leading)
                        Text("\(s.count)")
                            .frame(width: 60, alignment: .trailing)
                        Text(String(format: "%.1f/s", s.rate))
                            .frame(width: 60, alignment: .trailing)
                        hexText(s, latest: latest)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                    .font(.system(.caption, design: .monospaced))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Latest frames stream

    private var stream: some View {
        GroupBox(tr("Dernières trames (les plus récentes en haut)")) {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(filteredRows) { r in
                    if let n = r.note {
                        Text(String(format: trd("%8.2f  ▶ NOTE : "), r.t) + n)
                            .foregroundStyle(.blue)
                            .bold()
                    } else {
                        Text(String(format: "%8.2f  n°%-4d ", r.t, r.packetId) + r.hex)
                            .foregroundStyle(r.known ? Color.primary : Color.purple)
                    }
                }
            }
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
