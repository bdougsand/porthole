//
//  AppDelegate.swift
//  Porthole
//
//  Created by Brian Sanders on 2/19/20.
//  Copyright © 2020 Brian Sanders. All rights reserved.
//

import Cocoa
import SwiftUI
import AVKit
import CoreGraphics


func eventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let windowID = event.getIntegerValueField(.mouseEventWindowUnderMousePointer)
    if refcon != nil {
        let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
        switch type {
        case .mouseMoved:
            appDelegate.windowHovered(CGWindowID(windowID))
        case .leftMouseDown:
            return nil
        case .leftMouseUp:
            appDelegate.windowMouseUp(CGWindowID(windowID))
        default: break
        }
    }
    
    return Unmanaged.passRetained(event)
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!

    var _showingWindowID: CGWindowID!
    var _captureTimer: Timer!
    
    var hoveredWindowID: CGWindowID?
    /// During window selection, holds the hover indicator window
    var _hoverWindow: NSWindow?

    var _eventTap: CFMachPort?
    var _runLoopSource: CFRunLoopSource?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create the SwiftUI view that provides the window contents.
        let contentView = ContentView()

        // Create the window and set the content view. 
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        window.titleVisibility = .hidden
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.collectionBehavior = .canJoinAllSpaces
        
        window.setIsVisible(false)
        
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as NSArray? as? [[CFString: AnyObject]]

        if let windowListInfo = windowListInfo {
            for otherWindow in windowListInfo {
                let windowID = otherWindow[kCGWindowNumber] as! CGWindowID
                let appName = otherWindow[kCGWindowOwnerName] as! String
                debugPrint(appName, windowID)

                if appName != "Safari" {
                    continue
                }

                break
            }
        }
        
        self.beginWindowSelection()
    }
    
    func startCapturingWindow(_ windowID: CGWindowID) {
        if let activeTimer = _captureTimer {
            activeTimer.invalidate()
        }
        
        window.setIsVisible(true)
        _captureTimer = Timer(timeInterval: 0.03, repeats: true) { _ in
            self.updateSnap(windowID: windowID)
        }
        RunLoop.current.add(_captureTimer, forMode: .common)
    }
    
    func updateSnap(windowID: CGWindowID) {
        if let img = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.nominalResolution, .boundsIgnoreFraming]) {
            window.contentView?.layer?.contents = img
            window.aspectRatio = NSSize(width: 1, height: CGFloat(integerLiteral: img.height)/CGFloat(integerLiteral: img.width))
        }
    }
    
    func applicationWillResignActive(_ notification: Notification) {
        /// TODO: Exit window selection if active
        endWindowSelection()
    }
    
    func beginWindowSelection() {
        let tapEvents = CGEventMask((1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue))
//        UnsafeMutableRawPointer.
        guard let eventTap = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: tapEvents, callback: eventCallback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            
            NSLog("Failed to create event tap")
            return
        }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        _eventTap = eventTap
        _runLoopSource = runLoopSource
    }
    
    func endWindowSelection() {
        if let eventTap = _eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), _runLoopSource!, .commonModes)
            
            _eventTap = nil
            _runLoopSource = nil
        }
        
        if let hoverWindow = _hoverWindow {
            hoverWindow.setIsVisible(false)
        }
        
        hoveredWindowID = nil
    }
    
    public func windowHovered(_ windowID: CGWindowID) {
        if hoveredWindowID == windowID || _hoverWindow?.windowNumber == Int(windowID) {
            return
        }
        
        if let windowListInfo = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as NSArray? as? [[CFString: AnyObject]] {
            let windowInfo = windowListInfo[0]
            if let boundsDict = windowInfo[kCGWindowBounds]! as? NSDictionary,
               let bounds = NSRect(dictionaryRepresentation: boundsDict) {
                _hoverWindow?.setFrame(bounds, display: true)
            }
        }
        
        hoveredWindowID = windowID
        
        if _hoverWindow == nil {
            let newWindow = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 100, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
            newWindow.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.3)
            _hoverWindow = newWindow
        }
        
        _hoverWindow?.order(.above, relativeTo: Int(windowID))
        _hoverWindow?.display()
    }
    
    public func windowMouseDown(_ windowID: CGWindowID) {
        
    }
    
    public func windowMouseUp(_ windowID: CGWindowID) {
        if hoveredWindowID != nil {
            debugPrint("Window selection done:", hoveredWindowID)
            _showingWindowID = hoveredWindowID
            self.startCapturingWindow(hoveredWindowID!)
        }
        
        endWindowSelection()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        endWindowSelection()
    }
}

