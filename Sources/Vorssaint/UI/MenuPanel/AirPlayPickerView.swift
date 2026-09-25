// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVKit
import SwiftUI

/// A compact AirPlay button suitable for the mixer panel header and output switcher.
struct AirPlayPickerButton: View {
    @ObservedObject private var manager = AirPlayRouteManager.shared

    var body: some View {
        if manager.isAvailable {
            Button(action: { manager.presentPicker() }) {
                Image(systemName: manager.isConnected ? "airplayaudio.circle.fill" : "airplayaudio")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(manager.isConnected ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help(manager.activeSpeakerName.map { "AirPlay: \($0)" } ?? "Choose AirPlay speaker…")
        }
    }
}
