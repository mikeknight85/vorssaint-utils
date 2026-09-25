// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVKit
import Combine
import Foundation
import ObjectiveC

/// Bridges macOS native AirPlay output routing into Vorssaint.
///
/// Discovers and connects AirPlay devices using the system's trusted routing
/// stack (`AVOutputContext` / `AVRoutePickerView`), bypassing Core Audio HAL's
/// inability to enumerate offline AirPlay endpoints.
final class AirPlayRouteManager: ObservableObject {
    static let shared = AirPlayRouteManager()

    /// Virtual UID used by Vorssaint to represent an AirPlay output route.
    static let airPlaySentinelUID = "vorssaint.output.airplay"

    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var activeSpeakerName: String?

    private var routingContext: NSObject?
    private weak var activePickerView: NSView?
    private var pollTimer: Timer?

    private typealias MsgSendClass = @convention(c) (AnyClass, Selector) -> AnyObject?
    private typealias MsgSendObj = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
    private typealias MsgSendObjReturn = @convention(c) (AnyObject, Selector) -> AnyObject?

    private let msgSendSym = dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend")

    private init() {
        dlopen("/System/Library/Frameworks/AVKit.framework/AVKit", RTLD_NOW)
        dlopen("/System/Library/Frameworks/AVFoundation.framework/AVFoundation", RTLD_NOW)
        self.isAvailable = NSClassFromString("AVOutputContext") != nil
        setupContext()
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    private func setupContext() {
        guard let cls = NSClassFromString("AVOutputContext"), let sym = msgSendSym else { return }
        let msgClass = unsafeBitCast(sym, to: MsgSendClass.self)
        let sharedSys = sel_registerName("sharedSystemAudioContext")
        let defaultShared = sel_registerName("defaultSharedOutputContext")

        if let ctx = (msgClass(cls, sharedSys) ?? msgClass(cls, defaultShared)) as? NSObject {
            self.routingContext = ctx
            refreshActiveDevice()
        }
    }

    /// Creates and binds an `AVRoutePickerView` to the routing context.
    func makeRoutePickerView(isActive: Bool = true) -> NSView? {
        guard let context = routingContext, let sym = msgSendSym else { return nil }
        let picker = AVRoutePickerView()
        let msgObj = unsafeBitCast(sym, to: MsgSendObj.self)
        let setCtxSel = sel_registerName("setOutputContextID:")

        if let ctxID = context.value(forKey: "ID") as? String, picker.responds(to: setCtxSel) {
            msgObj(picker, setCtxSel, ctxID as AnyObject)
        }
        if isActive {
            self.activePickerView = picker
        }
        return picker
    }

    /// Returns true if an active picker view exists to anchor `presentPicker`.
    var canPresentPicker: Bool {
        activePickerView != nil
    }

    private var fallbackWindow: NSWindow?

    /// Programmatically opens the system route picker anchored to the active picker view,
    /// or anchors a lightweight popup at the mouse cursor if no UI picker is currently mounted.
    func presentPicker() {
        if let picker = activePickerView, picker.window != nil, let button = findButton(in: picker) {
            button.performClick(nil)
            return
        }

        fallbackWindow?.close()
        fallbackWindow = nil

        let mouseLoc = NSEvent.mouseLocation
        let window = NSWindow(
            contentRect: NSRect(x: mouseLoc.x - 10, y: mouseLoc.y - 10, width: 20, height: 20),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating

        if let picker = makeRoutePickerView(isActive: false) {
            picker.frame = NSRect(x: 0, y: 0, width: 20, height: 20)
            window.contentView?.addSubview(picker)
            window.orderFront(nil)
            self.fallbackWindow = window
            if let button = findButton(in: picker) {
                button.performClick(nil)
            }
        }
    }

    private func findButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton { return button }
        for subview in view.subviews {
            if let found = findButton(in: subview) { return found }
        }
        return nil
    }

    /// Refreshes the currently connected AirPlay device name and status.
    func refreshActiveDevice() {
        guard let context = routingContext, let sym = msgSendSym else { return }
        let msgObjReturn = unsafeBitCast(sym, to: MsgSendObjReturn.self)

        var name: String? = nil
        let outputDevicesSel = sel_registerName("outputDevices")
        if context.responds(to: outputDevicesSel),
           let devices = msgObjReturn(context, outputDevicesSel) as? [NSObject] {
            let names = devices.compactMap { dev -> String? in
                guard let n = dev.value(forKey: "name") as? String, !n.isEmpty, !n.hasPrefix("APEndpoint") else {
                    return nil
                }
                return n
            }
            if !names.isEmpty {
                name = names.joined(separator: " + ")
            }
        }

        if name == nil {
            let outputDevSel = sel_registerName("outputDevice")
            if context.responds(to: outputDevSel),
               let dev = msgObjReturn(context, outputDevSel) as? NSObject,
               let n = dev.value(forKey: "name") as? String,
               !n.isEmpty, !n.hasPrefix("APEndpoint") {
                name = n
            }
        }

        let outputDevSel = sel_registerName("outputDevice")
        let hasDevice = context.responds(to: outputDevSel) && msgObjReturn(context, outputDevSel) != nil
        let connected = hasDevice && name != nil

        if self.isConnected != connected {
            self.isConnected = connected
        }
        if self.activeSpeakerName != name {
            self.activeSpeakerName = name
        }
    }

    private func startPolling() {
        // Poll device name every 1.5 seconds on the main queue
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshActiveDevice()
        }
    }

    /// Binds an audio object (such as AVSampleBufferAudioRenderer) to the routing context.
    func bindOutputContext(to audioObject: AnyObject) -> Bool {
        guard let context = routingContext, let sym = msgSendSym else { return false }
        let setCtxSel = sel_registerName("setOutputContext:")
        guard audioObject.responds(to: setCtxSel) else { return false }
        let msgObj = unsafeBitCast(sym, to: MsgSendObj.self)
        msgObj(audioObject, setCtxSel, context)
        return true
    }
}
