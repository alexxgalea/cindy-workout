import Foundation

/// The words the menu's and the You screen's views drew themselves, with nothing to pin them to the
/// Android screens'. The page models hold the rows and the sentences they build; these are each
/// screen's title and the line under it, and each is the literal in `activity_menu.xml` or
/// `activity_account.xml`. `MenuWordsTests` reads them off the layouts.
public enum MenuWords {
    public static let menuTitle = "Menu"
    public static let menuSubtitle = "Everything that isn't needed mid-workout"
    public static let youTitle = "You"
    public static let youSubtitle = "Your name, photo and badges. They stay on this phone."
}
