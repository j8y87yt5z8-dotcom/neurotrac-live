import SwiftUI
import Charts
import NeuroTracCore

/// Session history: list on the left, details on the right (curves, photos, PDF report).
struct HistoryView: View {
    @ObservedObject var follow: FollowUpModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sessionList
                .frame(width: 300)
            Divider()
            detail
        }
    }

    // MARK: - List

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(tr("Importer les CSV")) { follow.importCSVFolder() }
                Button(tr("Dossier")) { follow.openFollowFolder() }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            if !follow.info.isEmpty {
                Text(follow.info)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }
            Text(tr("\(follow.sessions.count) séance(s)"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            List(follow.sessions, selection: $follow.selectedSessionId) { s in
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.day(s.start) + " — " + (s.muscle.isEmpty ? tr("Muscle ?") : trd(s.muscle)) + " " + trd(s.side).lowercased())
                        .font(.headline)
                    Text(rowDetail(s))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func rowDetail(_ s: SessionRecord) -> String {
        var parts: [String] = []
        if !s.programName.isEmpty { parts.append(s.programName) }
        parts.append(String(format: "%.0f min", s.durationSec / 60))
        if s.maxStimOverall > 0 { parts.append("\(s.maxStimOverall) mA") }
        if !s.photos.isEmpty { parts.append(tr("\(s.photos.count) photo(s)")) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Detail

    private var detail: some View {
        Group {
            if let s = follow.selectedSession {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header(s)
                        editor(s)
                        figures(s)
                        charts
                        photos(s)
                    }
                    .padding(20)
                }
            } else {
                Text(tr("Aucune séance sélectionnée. Les séances s'ajoutent toutes seules quand un programme tourne sur l'appareil."))
                    .foregroundStyle(.secondary)
                    .padding(30)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(_ s: SessionRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Fmt.dateTime(s.start))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            HStack {
                Button(tr("Rapport PDF de cette séance")) { follow.makeSessionReport(s.id) }
                    .buttonStyle(.borderedProminent)
                Button(tr("Ajouter des photos")) { follow.addPhotos(sessionId: s.id) }
                Button(tr("Ouvrir le CSV")) { follow.openCSV(s) }
                Button(tr("Supprimer")) { follow.askDelete = true }
                    .tint(.red)
            }
            if !follow.info.isEmpty {
                Text(follow.info)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(tr("Retirer cette séance de l'historique ?"), isPresented: $follow.askDelete) {
            Button(tr("Retirer de l'historique"), role: .destructive) { follow.deleteSession(s.id) }
            Button(tr("Annuler"), role: .cancel) {}
        } message: {
            Text(tr("Le fichier CSV reste dans le dossier ; la séance ne sera pas réimportée."))
        }
    }

    private func editor(_ s: SessionRecord) -> some View {
        GroupBox(tr("Muscle, côté et note (modifiables)")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker(tr("Muscle"), selection: Binding(get: { s.muscle }, set: { v in follow.updateSession(s.id) { $0.muscle = v } })) {
                        Text("—").tag("")
                        ForEach(muscleList, id: \.self) { Text(trd($0)).tag($0) }
                    }
                    Picker(tr("Côté"), selection: Binding(get: { s.side }, set: { v in follow.updateSession(s.id) { $0.side = v } })) {
                        Text("—").tag("")
                        ForEach(Catalog.sides, id: \.self) { Text(trd($0)).tag($0) }
                    }
                }
                TextField(tr("Sonde / électrodes (type, taille)"), text: Binding(get: { s.probe }, set: { v in follow.updateSession(s.id) { $0.probe = v } }))
                TextField(tr("Électrode de référence (position)"), text: Binding(get: { s.reference }, set: { v in follow.updateSession(s.id) { $0.reference = v } }))
                TextField(tr("Note"), text: Binding(get: { s.note }, set: { v in follow.updateSession(s.id) { $0.note = v } }))
            }
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 230, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .textSelection(.enabled)
            Spacer()
        }
        .font(.callout)
    }

    private func figures(_ s: SessionRecord) -> some View {
        GroupBox(tr("Détails")) {
            VStack(alignment: .leading, spacing: 4) {
                line(tr("Programme (lu sur l'appareil)"), s.programName)
                line(tr("Fréquence / largeur"), [s.frequency, s.width].filter { !$0.isEmpty }.joined(separator: " — "))
                line(tr("Rythme"), s.rhythm)
                line(tr("Rampes"), s.ramps)
                line(tr("Canal(aux)"), trd(s.channel))
                line(tr("Sonde / électrodes"), s.probe)
                line(tr("Électrode de référence"), s.reference)
                line(tr("Durée enregistrée"), Fmt.minutesSeconds(s.durationSec))
                line(tr("Intensité réglée (saisie)"), s.setIntensity.isEmpty ? "" : s.setIntensity + " mA")
                line(tr("Intensité max reçue (canaux 1 à 4)"), s.maxStimOverall > 0 ? s.maxStim.map { String($0) }.joined(separator: " / ") + " mA" : "")
                if s.stimActiveSec >= 0 { line(tr("Temps de stimulation"), Fmt.minutesSeconds(s.stimActiveSec)) }
                if s.stimBursts >= 0 { line(tr("Salves de stimulation"), "\(s.stimBursts)") }
                line(tr("EMG canal 1 (médiane / 95e c. / max)"), s.emgCount > 0 ? Fmt.num(s.emgMedian1) + " / " + Fmt.num(s.emgP95_1) + " / " + Fmt.num(s.emgMax1) + " µV" : "")
                line(tr("EMG canal 2 (médiane / 95e c. / max)"), s.emgCount > 0 ? Fmt.num(s.emgMedian2) + " / " + Fmt.num(s.emgP95_2) + " / " + Fmt.num(s.emgMax2) + " µV" : "")
                if s.alertCount > 0 { line(tr("Coupures signalées"), tr("\(s.alertCount) (électrodes ?)")) }
                line(tr("Origine"), s.source == "import" ? tr("Importée d'un CSV") : (s.source == "auto" ? tr("Enregistrement automatique") : tr("Enregistrement manuel")))
            }
        }
    }

    private var charts: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !follow.emgPreview.isEmpty {
                GroupBox(tr("EMG (µV)")) {
                    Chart {
                        ForEach(follow.emgPreview) { p in
                            LineMark(x: .value(tr("Minutes"), p.minutes), y: .value("µV", p.value))
                                .foregroundStyle(by: .value(tr("Canal"), p.name))
                        }
                    }
                    .frame(height: 180)
                }
            }
            if !follow.stimPreview.isEmpty {
                GroupBox(tr("Stimulation (mA)")) {
                    Chart {
                        ForEach(follow.stimPreview) { p in
                            LineMark(x: .value(tr("Minutes"), p.minutes), y: .value("mA", p.value))
                                .interpolationMethod(.stepEnd)
                                .foregroundStyle(by: .value(tr("Canal"), p.name))
                        }
                    }
                    .frame(height: 140)
                }
            }
        }
    }

    private func photos(_ s: SessionRecord) -> some View {
        GroupBox(tr("Photos de placement")) {
            VStack(alignment: .leading, spacing: 8) {
                if s.photos.isEmpty {
                    Text(tr("Aucune photo. Envoie-les de l'iPhone par AirDrop, puis « Ajouter des photos »."))
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170))], spacing: 10) {
                    ForEach(s.photos, id: \.self) { name in
                        VStack(spacing: 4) {
                            if let img = follow.photoImage(name) {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Text(tr("Photo introuvable")).foregroundStyle(.secondary)
                            }
                            Button(tr("Retirer")) { follow.removePhoto(name, sessionId: s.id) }
                                .font(.caption)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
