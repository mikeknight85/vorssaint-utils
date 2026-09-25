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

        let airPlayUID = AirPlayRouteManager.airPlaySentinelUID
        let available: Set<String> = ["BuiltInSpeakerDevice", "ExternalDisplay"]

        let toAirPlay = MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "BuiltInSpeakerDevice",
            selectedUIDs: ["BuiltInSpeakerDevice", airPlayUID],
            availableUIDs: available
        )
        suite.expect(toAirPlay == airPlayUID,
                     "switching from built-in speakers advances to offline AirPlay route")

        let fromAirPlay = MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "AirPlay",
            selectedUIDs: ["BuiltInSpeakerDevice", airPlayUID],
            availableUIDs: available
        )
        suite.expect(fromAirPlay == "BuiltInSpeakerDevice",
                     "switching from active AirPlay advances back to built-in speakers")

        suite.expect(MixerRoutingSupport.isAirPlayUID(airPlayUID) &&
                     MixerRoutingSupport.isAirPlayUID("AirPlay") &&
                     !MixerRoutingSupport.isAirPlayUID("BuiltInSpeakerDevice"),
                     "AirPlay UID predicate distinguishes sentinel and active AirPlay from hardware")
    }
}
