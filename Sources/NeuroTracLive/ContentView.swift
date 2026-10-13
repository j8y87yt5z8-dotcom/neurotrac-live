import SwiftUI
import Charts
import NeuroTracCore

struct ContentView: View {
    @StateObject private var model = LiveModel()

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar
                .frame(width: 330)
            Divider()
            mainPane
        }
        .frame(minWidth: 1050, minHeight: 720)
    }

    // MARK: - Left column: connection, session sheet, recording, markers

    private var sidebar: some View {
        Form {
            Section(tr("Connexion")) {
                Picker(tr("Appareil"), selection: $model.selectedDevice) {
                    if model.devices.isEmpty { Text(tr("Aucun appareil appairé")).tag("") }
                    ForEach(model.devices) { Text($0.label).tag($0.id) }
                }
                HStack {
                    Button(tr("Actualiser")) { model.refreshDevices() }
                    Button(tr("Réglages Bluetooth")) { model.openBluetoothSettings() }
                    TextField(tr("PIN"), text: $model.pin)
                        .frame(width: 60)
                }
                Toggle(tr("Reconnexion automatique"), isOn: $model.autoReconnect)
                Picker(tr("Langue"), selection: $model.langChoice) {
                    Text("Auto").tag("auto")
                    Text("Français").tag("fr")
                    Text("English").tag("en")
                }
                if model.langChoice != "auto" && model.langChoice != Lang.current.rawValue {
                    Text(tr("Relance l'application pour appliquer la langue partout."))
                        .font(.footnote).foregroundColor(.secondary)
                }
                if model.isBusy {
                    Button(tr("Déconnecter")) { model.disconnect() }
                } else {
                    Button(tr("Connecter")) { model.connect() }
                        .buttonStyle(.borderedProminent)
                }
                Text(model.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(tr("Séance")) {
                Picker(tr("Muscle"), selection: $model.muscle) {
                    ForEach(muscleList, id: \.self) { Text(trd($0)).tag($0) }
                }
                Picker(tr("Côté"), selection: $model.side) {
                    ForEach(Side.allCases) { Text(trd($0.rawValue)).tag($0) }
                }
                Picker(tr("Canal"), selection: $model.channelUse) {
                    ForEach(ChannelUse.allCases) { Text(trd($0.rawValue)).tag($0) }
                }
                Picker(tr("Programme"), selection: $model.program) {
                    ForEach(ProgramKind.allCases) { Text(trd($0.rawValue)).tag($0) }
                }
                TextField(tr("Sonde / électrodes (type, taille)"), text: $model.probe)
                TextField(tr("Électrode de référence (position)"), text: $model.reference)
                TextField(tr("Intensité réglée (mA)"), text: $model.setIntensity)
                TextField(tr("Note"), text: $model.note)
            }

            Section(tr("Enregistrement")) {
                Toggle(tr("Enregistrer automatiquement chaque programme"), isOn: $model.autoRecord)
                if model.isRecording {
                    Button(tr("Arrêter l'enregistrement")) { model.stopRecording() }
                        .tint(.red)
                    Text(tr("Enregistrement en cours…"))
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else {
                    Button(tr("Démarrer l'enregistrement")) { model.startRecording() }
                        .disabled(!model.isConnected)
                }
                if !model.lastSavedText.isEmpty {
                    Text(model.lastSavedText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section(tr("Repères (pendant l'enregistrement)")) {
                TextField(tr("Note du repère"), text: $model.markNote)
                ForEach(["Mouvement", "Vibration", "Contraction visible", "Rien"], id: \.self) { tag in
                    Button(trd(tag)) { model.addMark(tag) }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Main area: values and charts

    private var mainPane: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.tab) {
                Text(tr("Direct")).tag(0)
                Text(tr("Séances")).tag(1)
                Text(tr("Progression")).tag(2)
                Text(tr("Observations")).tag(3)
                Text(tr("Test EMG")).tag(4)
                Text(tr("Patient")).tag(5)
                Text(tr("Debug")).tag(6)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 660)
            .padding(.top, 12)
            switch model.tab {
            case 0: livePane
            case 1: HistoryView(follow: model.follow)
            case 2: ProgressionView(follow: model.follow)
            case 3: ObservationsView(follow: model.follow)
            case 4: EMGTestView(model: model, follow: model.follow)
            case 5: PatientView(follow: model.follow)
            default: DebugView(model: model)
            }
        }
    }

    private var livePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                alertBanner
                statusChips
                recordingInfo
                programPanel
                tiles
                thresholdBox
                emgChart
                stimChart
                eventsBox
                if !model.summaryText.isEmpty {
                    GroupBox(tr("Résumé de la dernière séance")) {
                        Text(model.summaryText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if !model.packetSummary.isEmpty {
                    Text(tr("Paquets reçus — ") + model.packetSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }

    private var statusChips: some View {
        HStack(spacing: 8) {
            switch model.linkState {
            case .connected: chip(tr("Connecté"), .green)
            case .connecting, .handshaking: chip(tr("Connexion…"), .orange)
            case .idle: chip(model.isBusy ? tr("Reconnexion…") : tr("Non connecté"), .gray)
            }
            chip(tr("Mode : ") + trd(model.modeText), .blue)
            chip(tr("Phase : ") + trd(model.workPhase), .purple)
            if model.isRecording { chip(tr("● REC"), .red) }
        }
    }

    private var recordingInfo: some View {
        HStack(spacing: 8) {
            Image(systemName: model.isRecording ? "record.circle.fill" : "circle")
                .foregroundStyle(model.isRecording ? Color.red : Color.secondary)
            Text(tr("Séance en cours d'attribution : ") + trd(model.muscle) + " — " + trd(model.side.rawValue).lowercased()
                 + (model.autoRecord ? tr(" (enregistrement automatique actif)") : tr(" (enregistrement automatique coupé)")))
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var thresholdBox: some View {
        GroupBox(tr("Noter un seuil (muscle et côté de la colonne de gauche)")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker(tr("Réponse obtenue"), selection: $model.thresholdKind) {
                        ForEach(Catalog.thresholdKinds, id: \.self) { Text(trd($0)).tag($0) }
                    }
                    .frame(maxWidth: 360)
                    TextField(tr("mA (vide = valeur lue)"), text: $model.thresholdInput)
                        .frame(width: 150)
                    Text(tr("Lu sur l'appareil : \(model.recentStimMax) mA"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    TextField(tr("Note (électrodes, ce qui bouge…)"), text: $model.thresholdNote)
                    Button(tr("Noter le seuil")) { model.noteThreshold() }
                        .buttonStyle(.borderedProminent)
                }
                if !model.thresholdMessage.isEmpty {
                    Text(model.thresholdMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var alertBanner: some View {
        Group {
            if let a = model.alertText {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(a).font(.headline)
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(12)
                .background(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var programPanel: some View {
        GroupBox(tr("Programme en cours (lu sur l'appareil)")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.progInfo.name)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    Spacer()
                    Text(trd(model.progInfo.status))
                        .font(.headline)
                        .foregroundStyle(model.progInfo.status == "En pause" ? Color.red : Color.secondary)
                }
                HStack(spacing: 12) {
                    tile(tr("Fréquence"), model.progInfo.frequency, "")
                    tile(tr("Largeur d'impulsion"), model.progInfo.width, "")
                    tile(tr("Rythme"), model.progInfo.rhythm, "")
                }
                HStack(spacing: 12) {
                    tile(tr("Rampes montée / descente"), model.progInfo.ramps, "")
                    tile(tr("Durée du programme"), model.progInfo.duration, "")
                    tile(tr("Temps restant"), model.progInfo.remaining, "")
                }
            }
        }
    }

    private var eventsBox: some View {
        GroupBox(tr("Événements")) {
            VStack(alignment: .leading, spacing: 3) {
                if model.events.isEmpty {
                    Text(tr("Aucun pour l'instant.")).foregroundStyle(.secondary)
                }
                ForEach(Array(model.events.suffix(12).reversed())) { e in
                    Text(String(format: "%7.1f s   ", e.t) + e.text)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(e.alert ? Color.red : Color.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.18))
            .clipShape(Capsule())
    }

    private var tiles: some View {
        HStack(spacing: 12) {
            tile(tr("EMG canal 1"), String(format: "%.1f", model.emg1), "µV")
            tile(tr("EMG canal 2"), String(format: "%.1f", model.emg2), "µV")
            tile(tr("Stimulation canal 1"), "\(model.stim[0])", "mA")
            tile(tr("Stimulation canal 2"), "\(model.stim[1])", "mA")
            tile(tr("Compte à rebours ETS"), "\(model.etsCountdown)", "s ?")
        }
    }

    private func tile(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var visibleMarks: [Mark] {
        let r = model.windowRange
        return model.marks.filter { r.contains($0.t) }
    }

    private var emgChart: some View {
        GroupBox(tr("EMG récupéré (µV) — 30 dernières secondes")) {
            Chart {
                ForEach(model.emgPoints) { p in
                    LineMark(x: .value(tr("Temps (s)"), p.t), y: .value("µV", p.ch1))
                        .foregroundStyle(by: .value(tr("Canal"), tr("EMG 1")))
                }
                ForEach(model.emgPoints) { p in
                    LineMark(x: .value(tr("Temps (s)"), p.t), y: .value("µV", p.ch2))
                        .foregroundStyle(by: .value(tr("Canal"), tr("EMG 2")))
                }
                ForEach(visibleMarks) { m in
                    RuleMark(x: .value(tr("Repère"), m.t))
                        .foregroundStyle(Color.orange.opacity(0.7))
                        .annotation(position: .top, alignment: .leading) {
                            Text(trd(m.tag)).font(.caption2).foregroundStyle(.orange)
                        }
                }
            }
            .chartXScale(domain: model.windowRange)
            .frame(height: 230)
        }
    }

    private var stimChart: some View {
        GroupBox(tr("Stimulation ajoutée par l'appareil (valeur par canal) — 30 dernières secondes")) {
            Chart {
                ForEach(model.stimPoints) { p in
                    LineMark(x: .value(tr("Temps (s)"), p.t), y: .value(tr("Valeur"), p.c1))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(by: .value(tr("Canal"), tr("Canal 1")))
                }
                ForEach(model.stimPoints) { p in
                    LineMark(x: .value(tr("Temps (s)"), p.t), y: .value(tr("Valeur"), p.c2))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(by: .value(tr("Canal"), tr("Canal 2")))
                }
                ForEach(model.stimPoints) { p in
                    LineMark(x: .value(tr("Temps (s)"), p.t), y: .value(tr("Valeur"), p.c3))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(by: .value(tr("Canal"), tr("Canal 3")))
                }
                ForEach(model.stimPoints) { p in
                    LineMark(x: .value(tr("Temps (s)"), p.t), y: .value(tr("Valeur"), p.c4))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(by: .value(tr("Canal"), tr("Canal 4")))
                }
            }
            .chartXScale(domain: model.windowRange)
            .frame(height: 170)
        }
    }
}
