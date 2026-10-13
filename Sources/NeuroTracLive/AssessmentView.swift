import SwiftUI
import NeuroTracCore

/// Entry and history of pelvic floor assessments (“test B1 / B2” type).
/// Scores are copied by hand from the assessment done with the device or the clinician.
struct AssessmentView: View {
    @ObservedObject var follow: FollowUpModel

    private var sideChoices: [String] {
        return ["Droite", "Gauche"]
    }

    private var sideBinding: Binding<String> {
        return Binding(
            get: { follow.assessDraft.side == "Gauche" ? "Gauche" : "Droite" },
            set: { follow.assessDraft.side = $0 }
        )
    }

    var body: some View {
        GroupBox(tr("Évaluation du plancher pelvien (scores saisis)")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("Recopie les scores d'une évaluation (par ex. test B1, B2) : contractions rapides, tenues (tonique), endurance, repos avant et après, score global. Ils alimentent les courbes de Progression et le rapport PDF."))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField(tr("Nom (B1, B2…)"), text: $follow.assessDraft.label)
                        .frame(width: 140)
                    DatePicker(tr("Date"), selection: $follow.assessDraft.date, displayedComponents: .date)
                    Picker(tr("Muscle"), selection: $follow.assessDraft.muscle) {
                        ForEach(muscleList, id: \.self) { Text(trd($0)).tag($0) }
                    }
                    if !Catalog.midlineMuscles.contains(follow.assessDraft.muscle) {
                        Picker(tr("Côté"), selection: sideBinding) {
                            ForEach(sideChoices, id: \.self) { Text(trd($0)).tag($0) }
                        }
                    }
                }
                HStack {
                    numberField(tr("Rapides"), $follow.assessDraft.fast)
                    numberField(tr("Tenues (tonique)"), $follow.assessDraft.tonic)
                    numberField(tr("Endurance"), $follow.assessDraft.endurance)
                    numberField(tr("Repos avant"), $follow.assessDraft.baselineBefore)
                    numberField(tr("Repos après"), $follow.assessDraft.baselineAfter)
                    numberField(tr("Score global"), $follow.assessDraft.total)
                }
                TextField(tr("Note (facultatif)"), text: $follow.assessDraft.note)
                HStack {
                    Button(tr("Enregistrer l'évaluation")) { follow.saveAssessment() }
                        .buttonStyle(.borderedProminent)
                    if !follow.assessMessage.isEmpty {
                        Text(follow.assessMessage).font(.callout).foregroundStyle(.secondary)
                    }
                }

                Divider()
                if follow.assessments.isEmpty {
                    Text(tr("Aucune évaluation enregistrée.")).foregroundStyle(.secondary)
                }
                ForEach(follow.assessments) { a in
                    HStack {
                        Text(Fmt.day(a.date)).frame(width: 90, alignment: .leading)
                        Text(a.label).frame(width: 110, alignment: .leading).font(.headline)
                        Text(tr("rapides ") + Fmt.num(a.fast) + tr(" · tenues ") + Fmt.num(a.tonic) + tr(" · endurance ") + Fmt.num(a.endurance) + tr(" · repos ") + Fmt.num(a.baselineBefore) + "/" + Fmt.num(a.baselineAfter) + tr(" · global ") + Fmt.num(a.total))
                        Spacer()
                        Button(tr("Supprimer")) { follow.deleteAssessment(a.id) }
                            .font(.caption)
                    }
                    .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func numberField(_ title: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField("", value: value, format: .number)
                .frame(width: 90)
        }
    }
}
