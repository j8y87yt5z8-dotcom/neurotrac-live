import SwiftUI
import Charts
import NeuroTracCore

/// Progression over time, right versus left, and PDF report for a period.
struct ProgressionView: View {
    @ObservedObject var follow: FollowUpModel

    private var mythresholds: [ThresholdRecord] {
        return follow.thresholds.filter { $0.muscle == follow.progressMuscle }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox(tr("Indicateur")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Picker(tr("Indicateur"), selection: $follow.progressMetric) {
                                ForEach(ProgressStats.metrics) { m in
                                    Text(m.label).tag(m.id)
                                }
                            }
                            Picker(tr("Muscle"), selection: $follow.progressMuscle) {
                                ForEach(muscleList, id: \.self) { Text(trd($0)).tag($0) }
                            }
                            .disabled(!follow.currentMetric.usesMuscle)
                        }
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox(follow.currentMetric.label + " (" + follow.currentMetric.unit + ")") {
                    VStack(alignment: .leading, spacing: 8) {
                        if follow.chartPoints.isEmpty {
                            Text(tr("Aucune mesure pour cet indicateur. Les seuils se notent dans l'onglet Direct, les tests dans l'onglet Test EMG, les observations dans l'onglet Observations."))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 20)
                        } else {
                            Chart {
                                ForEach(follow.chartPoints) { p in
                                    LineMark(x: .value(tr("Date"), p.date), y: .value(follow.currentMetric.unit, p.value))
                                        .foregroundStyle(by: .value(tr("Côté"), p.side))
                                    PointMark(x: .value(tr("Date"), p.date), y: .value(follow.currentMetric.unit, p.value))
                                        .foregroundStyle(by: .value(tr("Côté"), p.side))
                                }
                            }
                            .chartForegroundStyleScale([trd("Droite"): Color.blue, trd("Gauche"): Color.orange, trd(Catalog.noSide): Color.teal])
                            .frame(height: 280)
                        }
                        ForEach(follow.progressSides, id: \.self) { side in
                            Text(follow.trendText(side: side)).font(.callout)
                        }
                        Text(tr("Une tendance n'a de sens que si le placement, le programme et l'appareil restent les mêmes. À interpréter avec le kiné ou le médecin."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox(tr("Seuils notés — ") + trd(follow.progressMuscle)) {
                    VStack(alignment: .leading, spacing: 4) {
                        if mythresholds.isEmpty {
                            Text(tr("Aucun seuil noté pour ce muscle.")).foregroundStyle(.secondary)
                        }
                        ForEach(mythresholds) { t in
                            HStack {
                                Text(Fmt.dateTime(t.date))
                                    .frame(width: 190, alignment: .leading)
                                Text(trd(t.side)).frame(width: 60, alignment: .leading)
                                Text(Fmt.num(t.mA) + " mA").frame(width: 70, alignment: .leading)
                                Text(trd(t.kind)).frame(width: 160, alignment: .leading)
                                Text(t.note).foregroundStyle(.secondary)
                                Spacer()
                                Button(tr("Supprimer")) { follow.deleteThreshold(t.id) }
                                    .font(.caption)
                            }
                            .font(.callout)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(tr("Rapport PDF de suivi")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Picker(tr("Période"), selection: $follow.periodChoice) {
                                ForEach(0..<FollowUpModel.periodLabels.count, id: \.self) { i in
                                    Text(FollowUpModel.periodLabels[i]).tag(i)
                                }
                            }
                            .frame(maxWidth: 320)
                            Button(tr("Créer le PDF")) { follow.makePeriodReport() }
                                .buttonStyle(.borderedProminent)
                        }
                        Text(tr("Le PDF contient la fiche patient, le résumé, les courbes droite/gauche, les tests EMG, la dernière fiche d'observations et la liste des séances. Il est enregistré dans Documents/NeuroTracLive/Rapports."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !follow.info.isEmpty {
                            Text(follow.info).font(.footnote)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private var hint: String {
        switch follow.progressMetric {
        case "threshold":
            return tr("Courant nécessaire pour obtenir une réponse (vibration, mouvement…). Une baisse = moins de courant nécessaire pour la même réponse.")
        case "stim_max":
            return tr("Intensité la plus haute reçue de l'appareil pendant chaque séance.")
        case "emg_median", "emg_p95":
            return tr("EMG du canal choisi pour la séance, valeur centrale (médiane) ou haute (95e centile) : moins sensibles aux parasites que le maximum. Comparable seulement à placement et tâche identiques.")
        case "emg_mean", "emg_max":
            return tr("Moyenne et maximum sont tirés par quelques valeurs parasites (pics de stimulation) : préfère la médiane ou le 95e centile.")
        case "stim_bursts":
            return tr("Nombre de fois où l'appareil a envoyé du courant pendant la séance (reprise du courant après une pause d'au moins 0,6 s). En ETS, c'est le nombre de déclenchements obtenus ; le nombre de cycles possibles dépend du programme.")
        case "assess_total", "assess_fast", "assess_tonic", "assess_endurance", "assess_base_before", "assess_base_after":
            return tr("Scores d'évaluation saisis dans l'onglet Test EMG (évaluation du plancher pelvien). L'interprétation revient à l'équipe soignante.")
        case "test_peak", "test_mean", "test_hold":
            return tr("Résultats du test EMG standardisé : le plus fiable pour comparer d'une séance à l'autre.")
        default:
            return tr("Échelle de 0 à 5 saisie dans la fiche d'observations.")
        }
    }
}
