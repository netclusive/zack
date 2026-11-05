import Darwin
import Foundation
import Synchronization
import os

/// Pause and play through MediaRemote, a non-public macOS framework, loaded on first use. Without the framework or
/// its command (a macOS update may remove either) it does nothing.
public final class MediaRemoteCommands: PlaybackCommands {
    public static let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

    private typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool

    private enum Lookup {
        case pending
        case found(SendCommand)
        case missing
    }

    /// MediaRemote's command numbers.
    private static let playCommand: UInt32 = 0
    private static let pauseCommand: UInt32 = 1

    private let frameworkPath: String
    private let lookup = Mutex(Lookup.pending)
    private let logger = Logger(subsystem: Signposts.subsystem, category: "media")

    public init(frameworkPath: String = MediaRemoteCommands.frameworkPath) {
        self.frameworkPath = frameworkPath
    }

    public func pause() {
        send(Self.pauseCommand)
    }

    public func play() {
        send(Self.playCommand)
    }

    /// Loads the framework if needed; false if it or its command is missing.
    var isAvailable: Bool { sendCommand() != nil }

    private func send(_ command: UInt32) {
        // Always true, even when nothing plays, so it is not checked.
        _ = sendCommand()?(command, nil)
    }

    private func sendCommand() -> SendCommand? {
        lookup.withLock { lookup -> SendCommand? in
            switch lookup {
            case .found(let function):
                return function
            case .missing:
                return nil
            case .pending:
                // Never closed: the function stays in use while the app runs.
                guard let handle = dlopen(frameworkPath, RTLD_LAZY),
                    let symbol = dlsym(handle, "MRMediaRemoteSendCommand")
                else {
                    lookup = .missing
                    logger.error("media remote unavailable")
                    return nil
                }
                let function = unsafeBitCast(symbol, to: SendCommand.self)
                lookup = .found(function)
                return function
            }
        }
    }
}
