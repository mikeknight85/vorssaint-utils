// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The real shortcut switch runs against in-memory outputs. Nothing is routed.
enum SoundOutputSwitchContract {
    struct Device {
        let uid: String
        let canBeDefaultOutput: Bool
    }

    static func run(_ suite: TestSuite) {
        let mixer = Mixer()
        mixer.outputDevices = [Device(uid: "BuiltInSpeakerDevice", canBeDefaultOutput: true),
                               Device(uid: "ExternalDisplay", canBeDefaultOutput: true)]
        mixer.currentOutputDeviceUID = "BuiltInSpeakerDevice"
        suite.expect(mixer.switchToNextSoundOutput(in: ["BuiltInSpeakerDevice"]) && mixer.switchedTo.isEmpty,
                     "the only selected output already playing is not reported as a failed switch")
        suite.expect(!mixer.switchToNextSoundOutput(in: ["USBHeadphones"]) && mixer.switchedTo.isEmpty,
                     "a selection with no connected output still fails")
        suite.expect(mixer.switchToNextSoundOutput(in: ["BuiltInSpeakerDevice", "ExternalDisplay"])
                     && mixer.switchedTo == ["ExternalDisplay"],
                     "two selected outputs still switch to the next one")

        // The AirPlay entry is listed as an output whenever the picker API exists.
        let airPlayUID = AirPlayRouteManager.airPlaySentinelUID
        let available: Set<String> = ["BuiltInSpeakerDevice", "ExternalDisplay", airPlayUID]

        let toAirPlay = MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "BuiltInSpeakerDevice",
            selectedUIDs: ["BuiltInSpeakerDevice", airPlayUID],
            availableUIDs: available
        )
        suite.expect(toAirPlay == airPlayUID,
                     "switching from built-in speakers advances to the AirPlay entry")

        let fromAirPlay = MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: airPlayUID,
            selectedUIDs: ["BuiltInSpeakerDevice", airPlayUID],
            availableUIDs: available
        )
        suite.expect(fromAirPlay == "BuiltInSpeakerDevice",
                     "switching from the AirPlay entry advances back to built-in speakers")

        let withoutPicker = MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "BuiltInSpeakerDevice",
            selectedUIDs: ["BuiltInSpeakerDevice", airPlayUID],
            availableUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"]
        )
        suite.expect(withoutPicker == nil,
                     "an AirPlay entry that is not listed is skipped like any missing output")
    }
}
