import Foundation

/// The voice in Turkish.
///
/// Register: the informal "sen", in short imperatives. Turkish has no plural after a numeral ("6
/// tur", "185 tekrar"), so there is no rule to follow and every count is a digit. The sentences are
/// built so that no suffix has to attach to the athlete's name or to a number: the benchmark is
/// "Tom Holland skorunu", where the possessive lands on "skor" and the name stays as it is.
/// Sentences end on a word, never on a number: Turkish engines read "12." as an ordinal.
///
/// Written without a native speaker's review; the lines are short so that they can be read that way.
public struct PhrasebookTr: Phrasebook {

    public init() {}

    public let tag = "tr"

    public func say(_ line: VoiceLine) -> String {
        switch line {
        case .count(let reps): return "\(reps)"
        case .movement(let exercise):
            switch exercise {
            case .pullup: return "barfiks"
            case .pushup: return "şınav"
            case .squat: return "squat"
            }
        case .roundDone(let round, let splitMs): return "Tur \(round), süre \(duration(splitMs))"
        case .phoneMoved: return "Telefon kımıldadı. Kadrajı kontrol et."
        case .setUp: return "Kadraja gir, sonra iki yavaş barfiks yap"
        case .go(let calibrated): return calibrated ? "Kalibre edildi. Başla." : "Başla. Barfiks"
        case .resume: return "Devam"
        case .finished(let early): return early ? "Durduruldu." : "Süre doldu."
        case .score(let rounds, let totalReps): return score(rounds, totalReps)
        case .averaging(let roundMs): return "Tur başına ortalama \(duration(roundMs))"
        case .beatBenchmark(let name): return "\(name) skorunu geçtin"
        case .ready: return "Hazır"
        case .fault(let text): return Hint.of(text).map { hint($0) } ?? "Pozisyonunu kontrol et"
        case .clock(let mark, let rounds, let totalReps, let projectedRounds):
            return clock(mark, rounds, totalReps, projectedRounds)
        case .sample: return "Üç. Dört. Beş. Şınav."
        case .volumeCheck: return "Üç"
        case .recordingSoon(let n): return "Kayıt \(n) saniye sonra başlıyor"
        case .recordingStarted: return "Kayıt başladı"
        case .recordingFailed: return "Kayıt başarısız"
        case .adaptiveHeelsFlat: return "Topuklar yerde yapılan çömelmeler için uyarlanmış Cindy etkinleştirildi."
        }
    }

    private func hint(_ hint: Hint) -> String {
        switch hint {
        case .stepIntoFrame: return "Kadraja gir"
        case .finishSetupFirst: return "Önce hazırlığı bitir"
        case .tracking: return "Seni arıyorum"
        case .hangFromBar: return "Çubuğa asıl"
        case .hangVertically: return "Çubuğa dik şekilde asıl"
        case .getOnBar: return "Çubuğu tut"
        case .showBothHands: return "İki elini de göster"
        case .showYourHead: return "Kafanı göster"
        case .armsOutOfFrame: return "Kolların kadrajın dışında"
        case .getHeadOverBar: return "Başını çubuğun üstüne çıkar"
        case .returnToDeadHang: return "Kollarını düzleyip yeniden asıl"
        case .lowerAllTheWay: return "Tamamen aşağı in"
        case .getSetOnFloor: return "Yerde pozisyon al"
        case .getOnFloor: return "Yere geç"
        case .standUpToStart: return "Başlamak için ayağa kalk"
        case .showYourLegs: return "Bacaklarını kameraya göster"
        case .driveUp: return "Yukarı it"
        case .goDown: return "Aşağı in"
        case .losingYou: return "Seni gözden kaybediyorum. Daha fazla ışık yardımcı olur."
        case .tooDark: return "Saymak için çok karanlık. Artı bir düğmesine dokun."
        case .cantSeeYou: return "Seni göremiyorum. Artı bir düğmesine dokun."
        }
    }

    private func clock(_ mark: ClockMark, _ rounds: Int, _ totalReps: Int, _ projected: Int?) -> String {
        switch mark {
        case .tenSecondsLeft: return "On saniye. Bütün gücünle."
        case .oneMinuteLeft: return "Bir dakika kaldı. \(rounds) tur tamamlandı. Başladığın turu bitir."
        case .twoMinutesLeft: return "İki dakika. " + push(rounds, totalReps)
        case .fiveMinutesLeft: return "Beş dakika kaldı. " + pace(rounds, projected)
        case .halfway: return "Yarı yol. " + pace(rounds, projected)
        case .fiveMinutesIn: return "Beş dakika geçti. " + pace(rounds, projected)
        }
    }

    private func pace(_ rounds: Int, _ projected: Int?) -> String {
        if let projected { return "\(rounds) tur tamamlandı. Bu tempoyla \(projected) tur." }
        return "Tempoyu koru."
    }

    private func push(_ rounds: Int, _ totalReps: Int) -> String {
        score(rounds, totalReps) + (rounds < 1 ? ". Devam et." : ". Tempoyu koru.")
    }

    private func score(_ rounds: Int, _ totalReps: Int) -> String {
        rounds < 1 ? "\(totalReps) tekrar" : "\(rounds) tur, toplam \(totalReps) tekrar"
    }

    private func duration(_ ms: Int64) -> String {
        let (m, s) = minutesAndSeconds(ms)
        if m == 0 { return "\(s) saniye" }
        if s == 0 { return "\(m) dakika" }
        return "\(m) dakika \(s) saniye"
    }
}
