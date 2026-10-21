import Foundation

/// The labels the iPhone's sheets drew themselves, with nothing to pin them to the Android
/// sheets'. The models hold the sentences and the labels they build; these are the buttons every
/// sheet shares and the two headings of the voice sheet, and each is the literal in
/// `MenuActivity.kt`, `Dialogs.kt`, `AccountActivity.kt` or `LanguageGroup.kt`.
/// `SheetWordsTests` reads them off the Kotlin.
public enum SheetWords {
    public static let save = "SAVE"
    public static let cancel = "CANCEL"
    public static let done = "DONE"
    public static let notNow = "NOT NOW"
    public static let hearIt = "HEAR IT"
    public static let forget = "FORGET"
    public static let openSettings = "OPEN SETTINGS"
    public static let language = "LANGUAGE"
    public static let volume = "Volume"
}
