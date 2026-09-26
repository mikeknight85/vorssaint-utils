// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The ring between a tapped app's IO thread and the AirPlay feed. Frame
/// positions only ever grow, so an all-day stream must stay correct once they
/// pass the 32-bit range (about 12 hours at 48 kHz).
enum AirPlayRingBufferContract {
    static func run(_ suite: TestSuite) {
        roundTrip(suite)
        fullRingDropsNewestFrames(suite)
        positionsPastThirtyTwoBits(suite)
    }

    private static func frames(_ count: Int, from start: Int) -> [Float] {
        (0..<count).flatMap { [Float(start + $0), -Float(start + $0)] }
    }

    private static func roundTrip(_ suite: TestSuite) {
        let ring = AudioRingBuffer(sampleRate: 48_000, capacityFrames: 64)
        let input = frames(10, from: 1)
        input.withUnsafeBufferPointer { ring.write(frames: $0.baseAddress!, frameCount: 10, gain: 0.5) }

        var output = [Float](repeating: 99, count: 16 * 2)
        let read = output.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, frameCount: 16) }
        suite.expect(read == 10, "a read returns only the frames that were written")
        suite.expect(output[0] == 0.5 && output[1] == -0.5 && output[18] == 5 && output[19] == -5,
                     "written frames come back in order with the gain applied")
        suite.expect(output[20...].allSatisfy { $0 == 0 }, "the rest of a short read is silence")
    }

    private static func fullRingDropsNewestFrames(_ suite: TestSuite) {
        let ring = AudioRingBuffer(sampleRate: 48_000, capacityFrames: 8)
        let input = frames(12, from: 1)
        input.withUnsafeBufferPointer { ring.write(frames: $0.baseAddress!, frameCount: 12, gain: 1) }

        var output = [Float](repeating: 0, count: 12 * 2)
        let read = output.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, frameCount: 12) }
        suite.expect(read == 8 && output[14] == 8, "a full ring keeps the oldest frames and drops the overflow")
    }

    private static func positionsPastThirtyTwoBits(_ suite: TestSuite) {
        let start = Int64(Int32.max) - 100
        let ring = AudioRingBuffer(sampleRate: 48_000, capacityFrames: 1 << 10, startingFramePosition: start)
        var output = [Float](repeating: 0, count: 256 * 2)
        var delivered = 0
        var inOrder = true
        // Stream across the old wrap point in IO-sized chunks.
        for chunk in 0..<8 {
            let input = frames(256, from: chunk * 256)
            input.withUnsafeBufferPointer { ring.write(frames: $0.baseAddress!, frameCount: 256, gain: 1) }
            let read = output.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, frameCount: 256) }
            delivered += read
            inOrder = inOrder && output[0] == Float(chunk * 256) && output[510] == Float(chunk * 256 + 255)
        }
        suite.expect(delivered == 8 * 256 && inOrder,
                     "streaming continues without loss once frame positions pass the 32-bit range")
    }
}
