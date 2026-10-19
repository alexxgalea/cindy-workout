import Photos
import CindyCore

/// Where a film goes: Photos, with add-only access and no album.
///
/// Android writes to `Movies/Cindy`. On iOS an album needs full access to the whole library, and
/// saving without one needs only permission to add, a smaller thing to ask for a feature the athlete
/// has to tap. The film is moved into Photos rather than copied, so nothing is left in the app's
/// own folder.
enum FilmLibrary {

    static func access() -> FilmAccess {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited: return .allowed
        case .notDetermined: return .undecided
        default: return .refused
        }
    }

    /// Asks, and calls `done` on the main queue with the answer.
    static func requestAccess(_ done: @escaping (FilmAccess) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in
            DispatchQueue.main.async { done(access()) }
        }
    }

    /// Adds the film at `url` to Photos and calls `done` on the main queue. A film that was not
    /// saved is deleted, so a failure leaves nothing behind.
    static func save(_ url: URL, done: @escaping (Bool) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = true
            PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: options)
        }, completionHandler: { saved, _ in
            if !saved { try? FileManager.default.removeItem(at: url) }
            DispatchQueue.main.async { done(saved) }
        })
    }
}
