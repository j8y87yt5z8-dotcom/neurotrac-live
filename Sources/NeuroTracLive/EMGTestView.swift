import SwiftUI
import NeuroTracCore

/// Standardized EMG test: rest, then three identical contractions. Same instructions every time.
struct EMGTestView: View {
    @ObservedObject var model: LiveModel
    @ObservedObject var follow: FollowUpModel

    private var cueColor: Color {
        if model.testCue.hasPrefix(trd("CONTRACTE")) { return Color.green }
        if model.testRunning { return Color.blue }
        return Color.secondary
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox(tr("Protocole (identique à chaque test)")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("1. Sur l'appareil, lance un programme EMG seul (sans stimulation) et connecte l'app."))
                        Text(tr("2. Électrodes toujours au même endroit ; choisis le muscle et le côté dans la colonne de gauche."))
                        Text(tr("3. Le test dure \(Int(model.testProtocol.totalSec)) s : \(Int(model.testProtocol.baselineSec)) s de repos, puis \(model.testProtocol.cycles) contractions de \(Int(model.testProtocol.contractSec)) s séparées de \(Int(model.testProtocol.restSec)) s de repos. Un bip marque le début de chaque contraction."))
                        Text(tr("4. L'app mesure le repos, le pic, la moyenne et le temps de tenue, et les range dans l'historique pour la progression."))
                    }
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(tr("Test")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Picker(tr("Canal EMG testé"), selection: $model.testChannel) {
                                Text(tr("Canal 1")).tag(1)
                                Text(tr("Canal 2")).tag(2)
                            }
                            .frame(width: 220)
                            .disabled(model.testRunning)
                            Text(trd(model.muscle) + " — " + trd(model.side.rawValue).lowercased())
                                .font(.headline)
                            Spacer()
                            if model.testRunning {
                                Button(tr("Annuler")) { model.cancelEMGTest() }
                                    .tint(.red)
                            } else {
                                Button(tr("Démarrer le test")) { model.startEMGTest() }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!model.isConnected)
                            }
                        }
                        Text(model.testCue)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(cueColor)
                        if model.testRunning {
                            Text(String(format: trd("Reste %.0f s dans cette phase — EMG actuel : %.1f µV"), model.testRemaining, model.testChannel == 2 ? model.emg2 : model.emg1))
                                .font(.title3)
                                .monospacedDigit()
                            ProgressView(value: min(model.testElapsed, model.testProtocol.totalSec), total: model.testProtocol.totalSec)
                        }
                        if !model.testMessage.isEmpty {
                            Text(model.testMessage)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let r = model.testResult {
                    GroupBox(tr("Dernier résultat")) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 12) {
                                resultTile(tr("Repos"), Fmt.num(r.baseline), "µV")
                                resultTile(tr("Pic (au-dessus du repos)"), Fmt.num(r.peak), "µV")
                                resultTile(tr("Moyenne en contraction"), Fmt.num(r.mean), "µV")
                                resultTile(tr("Tenue moyenne"), Fmt.num(r.holdSec), "s")
                            }
                            ForEach(Array(r.cycles.enumerated()), id: \.offset) { pair in
                                Text(tr("Contraction \(pair.offset + 1) : pic ") + Fmt.num(pair.element.peak) + tr(" µV, moyenne ") + Fmt.num(pair.element.mean) + tr(" µV, tenue ") + Fmt.num(pair.element.holdSec) + " s")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(r.warnings, id: \.self) { w in
                                Text(w).font(.callout).foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                AssessmentView(follow: follow)

                GroupBox(tr("Tests précédents")) {
                    VStack(alignment: .leading, spacing: 4) {
                        if follow.tests.isEmpty {
                            Text(tr("Aucun test enregistré.")).foregroundStyle(.secondary)
                        }
                        ForEach(follow.tests) { t in
                            HStack {
                                Text(Fmt.dateTime(t.date)).frame(width: 190, alignment: .leading)
                                Text(trd(t.muscle) + " " + trd(t.side).lowercased()).frame(width: 190, alignment: .leading)
                                Text(tr("pic ") + Fmt.num(t.peak) + tr(" µV · moy. ") + Fmt.num(t.mean) + tr(" µV · tenue ") + Fmt.num(t.holdSec) + " s")
                                Spacer()
                                Button(tr("Supprimer")) { follow.deleteTest(t.id) }
                                    .font(.caption)
                            }
                            .font(.callout)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
    }

    private func resultTile(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
