// Copyright © 2024–2026 Yuze Pan. 保留一切权利。

//
//  EventDispatcher.swift
//  Deck
//
//  Deck Clipboard Manager - Global keyboard event dispatcher
//

import AppKit
import Carbon

@MainActor
final class EventDispatcher {
    static let shared = EventDispatcher()
    private init() {}
    
    private var monitorToken: Any?
    private var activeMask: NSEvent.EventTypeMask = []
    
    struct Handler {
        let key: String
        let mask: NSEvent.EventTypeMask
        let priority: Int
        let handler: (NSEvent) -> NSEvent?
    }
    
    private var handlers: [Handler] = []
    
    // MARK: - Lifecycle
    
    func start(matching mask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged]) {
        if monitorToken != nil {
            guard activeMask != mask else { return }
            stop()
        }

        activeMask = mask
        
        monitorToken = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self = self else { return event }
            return self.handle(event: event)
        }
        
        log.debug("EventDispatcher started")
    }
    
    func stop() {
        if let token = monitorToken {
            NSEvent.removeMonitor(token)
            monitorToken = nil
            activeMask = []
            log.debug("EventDispatcher stopped")
        }
    }
    
    // MARK: - Handler Registration
    
    func registerHandler(
        matching mask: NSEvent.EventTypeMask,
        key: String,
        priority: Int = 0,
        handler: @escaping (NSEvent) -> NSEvent?
    ) {
        handlers.removeAll { $0.key == key }
        
        let h = Handler(key: key, mask: mask, priority: priority, handler: handler)
        handlers.append(h)
        handlers.sort { $0.priority > $1.priority }
        start(matching: combinedMask())
        
        log.debug("Registered handler '\(key)' with priority \(priority)")
    }
    
    func unregisterHandler(_ key: String) {
        if handlers.contains(where: { $0.key == key }) {
            handlers.removeAll { $0.key == key }
            if handlers.isEmpty {
                stop()
            } else {
                start(matching: combinedMask())
            }
            log.debug("Unregistered handler '\(key)'")
        }
    }

    private func combinedMask() -> NSEvent.EventTypeMask {
        handlers.reduce(into: NSEvent.EventTypeMask()) { partialResult, handler in
            partialResult.formUnion(handler.mask)
        }
    }
    
    // MARK: - Event Dispatching
    
    private func handle(event: NSEvent) -> NSEvent? {
        var currentEvent = event
        
        for h in handlers {
            let eventMask = NSEvent.EventTypeMask(rawValue: 1 << currentEvent.type.rawValue)
            guard h.mask.contains(eventMask) else { continue }
            
            if let next = h.handler(currentEvent) {
                currentEvent = next
            } else {
                return nil
            }
        }
        
        return currentEvent
    }
}

// MARK: - KeyCode Constants

enum KeyCode {
    static let a: UInt16 = UInt16(kVK_ANSI_A)
    static let b: UInt16 = UInt16(kVK_ANSI_B)
    static let e: UInt16 = UInt16(kVK_ANSI_E)
    static let c: UInt16 = UInt16(kVK_ANSI_C)
    static let f: UInt16 = UInt16(kVK_ANSI_F)
    static let h: UInt16 = UInt16(kVK_ANSI_H)
    static let l: UInt16 = UInt16(kVK_ANSI_L)
    static let n: UInt16 = UInt16(kVK_ANSI_N)
    static let v: UInt16 = UInt16(kVK_ANSI_V)
    static let p: UInt16 = UInt16(kVK_ANSI_P)
    static let q: UInt16 = UInt16(kVK_ANSI_Q)
    
    static let escape: UInt16 = UInt16(kVK_Escape)
    static let delete: UInt16 = UInt16(kVK_Delete)
    static let forwardDelete: UInt16 = UInt16(kVK_ForwardDelete)
    static let tab: UInt16 = UInt16(kVK_Tab)
    static let `return`: UInt16 = UInt16(kVK_Return)
    static let keypadEnter: UInt16 = UInt16(kVK_ANSI_KeypadEnter)
    static let space: UInt16 = UInt16(kVK_Space)
    static let comma: UInt16 = UInt16(kVK_ANSI_Comma)
    
    static let leftArrow: UInt16 = UInt16(kVK_LeftArrow)
    static let rightArrow: UInt16 = UInt16(kVK_RightArrow)
    static let upArrow: UInt16 = UInt16(kVK_UpArrow)
    static let downArrow: UInt16 = UInt16(kVK_DownArrow)
    
    // Number keys for quick paste
    static let key1: UInt16 = UInt16(kVK_ANSI_1)
    static let key2: UInt16 = UInt16(kVK_ANSI_2)
    static let key3: UInt16 = UInt16(kVK_ANSI_3)
    static let key4: UInt16 = UInt16(kVK_ANSI_4)
    static let key5: UInt16 = UInt16(kVK_ANSI_5)
    static let key6: UInt16 = UInt16(kVK_ANSI_6)
    static let key7: UInt16 = UInt16(kVK_ANSI_7)
    static let key8: UInt16 = UInt16(kVK_ANSI_8)
    static let key9: UInt16 = UInt16(kVK_ANSI_9)
    static let key0: UInt16 = UInt16(kVK_ANSI_0)

    // Vim navigation keys
    static let j: UInt16 = UInt16(kVK_ANSI_J)
    static let k: UInt16 = UInt16(kVK_ANSI_K)
    static let x: UInt16 = UInt16(kVK_ANSI_X)
    static let y: UInt16 = UInt16(kVK_ANSI_Y)
    static let d: UInt16 = UInt16(kVK_ANSI_D)
    static let slash: UInt16 = UInt16(kVK_ANSI_Slash)
    
    static let specialKeyMap: [UInt16: String] = [
        0x33: "⌫", 0x75: "⌦", 0x24: "↩", 0x4C: "⌅",
        0x31: "Space", 0x30: "⇥",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5",
        0x61: "F6", 0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10",
        0x67: "F11", 0x6F: "F12"
    ]
    
    static func displayString(for keyCode: UInt16, characters: String?) -> String {
        if let special = specialKeyMap[keyCode] {
            return special
        }
        return characters?.uppercased() ?? ""
    }
}
