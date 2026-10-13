import SwiftUI
import NeuroTracCore

/// Patient sheet: everything is editable and saved automatically on the Mac.
struct PatientView: View {
    @ObservedObject var follow: FollowUpModel

    var body: some View {
        Form {
            Section(tr("Identité")) {
                TextField(tr("Prénom"), text: $follow.patient.firstName)
                TextField(tr("Nom"), text: $follow.patient.lastName)
                TextField(tr("Date de naissance (aaaa-mm-jj)"), text: $follow.patient.birthDate)
                if !follow.ageText.isEmpty {
                    Text(tr("Âge : ") + follow.ageText)
                        .foregroundStyle(.secondary)
                }
                TextField(tr("Sexe"), text: $follow.patient.sex)
                TextField(tr("Adresse"), text: $follow.patient.address)
                TextField(tr("Téléphone"), text: $follow.patient.phone)
            }
            Section(tr("Médical")) {
                TextField(tr("Taille (cm)"), text: $follow.patient.heightCm)
                TextField(tr("Poids (kg)"), text: $follow.patient.weightKg)
                TextField(tr("Atteinte (ex. spina bifida, MMC)"), text: $follow.patient.diagnosis)
                TextField(tr("Niveau lésionnel (ex. L2-L3)"), text: $follow.patient.lesionLevel)
                TextField(tr("Soignants (kiné, médecin…)"), text: $follow.patient.referents, axis: .vertical)
                    .lineLimit(2...5)
                TextField(tr("Notes"), text: $follow.patient.notes, axis: .vertical)
                    .lineLimit(3...8)
            }
            Section(tr("Données")) {
                Text(tr("Tout est enregistré automatiquement dans Documents/NeuroTracLive/Suivi (fichiers JSON lisibles). Une copie de sécurité (.bak) est gardée à chaque modification."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(tr("Ouvrir le dossier du suivi")) { follow.openFollowFolder() }
                ForEach(follow.warnings, id: \.self) { w in
                    Text(w).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }
}
