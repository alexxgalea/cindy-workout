import SwiftUI
import CindyCore

/// Asks for what the estimates need: body weight for the lifted and burned figures, birth year and
/// sex for the heart-rate zones and the calories read off a pulse. Kept on the phone in
/// `BodyProfile`, and each field can be left blank. P13 gives these their full sheets.
struct BodyDetailsSheet: View {
    let profile: BodyProfile
    let asksWeight: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var weight = ""
    @State private var birthYear = ""
    @State private var sex: Sex = .unstated

    var body: some View {
        Form {
            if asksWeight {
                Section {
                    TextField("Weight in kg", text: $weight).keyboardType(.decimalPad)
                } footer: {
                    Text("Only used to estimate what you lifted and burned. It stays on this phone.")
                }
            } else {
                Section {
                    TextField("Birth year", text: $birthYear).keyboardType(.numberPad)
                    Picker("Sex", selection: $sex) {
                        Text("Not stated").tag(Sex.unstated)
                        Text("Female").tag(Sex.female)
                        Text("Male").tag(Sex.male)
                    }
                } footer: {
                    Text("Used for heart-rate zones and the calories read off your pulse. It stays on this phone.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .safeAreaInset(edge: .bottom) {
            Button("SAVE") { save(); dismiss() }
                .buttonStyle(PrimaryButton())
                .padding(20)
        }
        .onAppear {
            if profile.bodyWeightKg > 0 { weight = String(profile.bodyWeightKg) }
            if profile.birthYear > 0 { birthYear = String(profile.birthYear) }
            sex = profile.sex ?? .unstated
        }
    }

    private func save() {
        if asksWeight {
            profile.bodyWeightKg = Double(weight.replacingOccurrences(of: ",", with: ".")) ?? 0
        } else {
            profile.birthYear = Int(birthYear) ?? 0
            profile.sex = sex
        }
    }
}
