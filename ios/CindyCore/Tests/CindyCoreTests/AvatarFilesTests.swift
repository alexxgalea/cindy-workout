import XCTest
@testable import CindyCore

/// The photo's file handling, ported from the file tests of `AccountScreenTest.kt`; the rest of
/// `AvatarStore` (decoding, turning upright, cutting the square) is the platform's, and the
/// arithmetic it uses is `AvatarTests`.
final class AvatarFilesTests: XCTestCase {

    private func files() -> (AvatarFiles, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AvatarFilesTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return (AvatarFiles(directory: directory), directory)
    }

    /// removing the photo takes a half-written copy with it
    func testRemovingThePhotoTakesAHalfWrittenCopyWithIt() throws {
        let (photo, directory) = files()
        try Data(count: 16).write(to: directory.appendingPathComponent("avatar.jpg"))
        let stray = directory.appendingPathComponent("avatar.jpg.partial")
        try Data(count: 4).write(to: stray)

        XCTAssertTrue(photo.clear())

        XCTAssertFalse(photo.exists)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stray.path), "a stray partial would ride along in the backup")
    }

    /// Any bytes do: whether there is a photo is whether there is a file.
    func testWhetherThereIsAPhotoIsWhetherThereIsAFile() throws {
        let (photo, directory) = files()
        XCTAssertFalse(photo.exists)
        XCTAssertNil(photo.load())

        try Data(count: 16).write(to: directory.appendingPathComponent("avatar.jpg"))

        XCTAssertTrue(photo.exists)
        XCTAssertEqual(photo.load(), Data(count: 16))
    }

    /// A folder with the photo's name is not a photo, and clearing nothing succeeds.
    func testAFolderIsNotAPhotoAndClearingNothingSucceeds() throws {
        let (photo, directory) = files()
        XCTAssertTrue(photo.clear())
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("avatar.jpg"), withIntermediateDirectories: true)
        XCTAssertFalse(photo.exists)
    }

    /// A new photo goes in beside the old one and replaces it whole; no partial is left behind.
    func testANewPhotoReplacesTheOldOneWholeAndLeavesNoPartial() {
        let (photo, directory) = files()
        XCTAssertTrue(photo.store(Data([1, 2, 3])))
        XCTAssertEqual(photo.load(), Data([1, 2, 3]))

        XCTAssertTrue(photo.store(Data([9, 8])))

        XCTAssertEqual(photo.load(), Data([9, 8]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("avatar.jpg.partial").path))
    }

    /// A store that cannot be written leaves the photo that was there as it was.
    func testAStoreThatCannotBeWrittenLeavesThePhotoThatWasThereAsItWas() throws {
        let (photo, directory) = files()
        XCTAssertTrue(photo.store(Data([1, 2, 3])))
        // The partial's name taken by a folder, so the write beside the photo fails.
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("avatar.jpg.partial"),
                                                withIntermediateDirectories: true)
        // Not clearing first: that would remove the folder, and the point is a failure.
        XCTAssertFalse(photo.store(Data([7])))
        XCTAssertEqual(photo.load(), Data([1, 2, 3]))
    }

    /// The directory is made if it is not there yet.
    func testTheDirectoryIsMadeIfItIsNotThereYet() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AvatarFilesTests-new-\(UUID().uuidString)/inner")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let photo = AvatarFiles(directory: directory)
        XCTAssertTrue(photo.store(Data([5])))
        XCTAssertTrue(photo.exists)
    }
}
