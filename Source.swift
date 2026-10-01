import AppKit
import ApplicationServices
import SwiftUI

private func systemValue(_ name: String) -> String {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "Unknown" }
    var bytes = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return "Unknown" }
    return String(cString: bytes)
}

struct ReproView: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                Text("Header")
                Color.gray
                    .frame(height: 2000)
                    .overlay {
                        VStack(spacing: 0) {
                            ForEach(1...50, id: \.self) { index in
                                Text("Row \(index)")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(index.isMultiple(of: 2) ? Color.black.opacity(0.08) : Color.clear)
                            }
                        }
                        .accessibilityHidden(true)
                    }
                Button("Footer") {}
            }
        }
    }
}

struct InstructionsView: View {
    let controller: AppDelegate

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            let screens = NSScreen.screens.map {
                "\($0.localizedName) (\(Int($0.frame.width))x\(Int($0.frame.height)) pt, \($0.backingScaleFactor)x)"
            }.joined(separator: "\n         ")
            Text("LazyVStack + Accessibility")
                .font(.title2.bold())
            Text("Reading the accessibility tree of an element inside a LazyVStack hangs the app on the next scroll.")
                .fixedSize(horizontal: false, vertical: true)
            Text("""
            macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
            Chip: \(systemValue("machdep.cpu.brand_string"))
            SDK: \(Bundle.main.object(forInfoDictionaryKey: "DTSDKName") as? String ?? "Unknown")
            PID: \(ProcessInfo.processInfo.processIdentifier)
            Screens: \(screens)
            """)
            .font(.system(.callout, design: .monospaced))
            Text("""
            1. Scroll the right panel up and down.
            2. Click "Read Accessibility" once.
            3. Scroll the right panel again. The app stops responding.

            If macOS asks for permission, turn on AccessibilityLazyVStackPoC in System Settings > Privacy & Security > Accessibility, then click the button again.

            Quit and relaunch the app before each run.
            """)
            Button("Read Accessibility", action: controller.readOnce)
            StatusView(label: controller.status)
                .frame(height: 64)
            Text("The right panel is a single LazyVStack: a header, a 2000 pt tall block, and a button.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct StatusView: NSViewRepresentable {
    let label: NSTextField
    func makeNSView(context: Context) -> NSTextField { label }
    func updateNSView(_ nsView: NSTextField, context: Context) {}
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var reader: Process?
    let status = NSTextField(wrappingLabelWithString: "Not read yet.")

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "AccessibilityLazyVStackPoC"
        window.minSize = NSSize(width: 800, height: 600)
        window.isReleasedWhenClosed = false
        status.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        status.textColor = .secondaryLabelColor
        let host = NSHostingView(rootView: HStack(spacing: 0) {
            InstructionsView(controller: self)
            Divider()
            ReproView().frame(width: 320)
        })
        host.sizingOptions = []
        window.contentView = host
        let screen = NSScreen.screens.last!.visibleFrame
        window.setFrameOrigin(NSPoint(x: screen.midX - window.frame.width / 2,
                                      y: screen.midY - window.frame.height / 2))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func readOnce() {
        guard reader == nil else { return }
        guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) else {
            status.stringValue = "Accessibility permission is off. Turn on AccessibilityLazyVStackPoC in System Settings > Privacy & Security > Accessibility, then click again."
            return
        }
        let content = window.contentView!
        let point = window.convertPoint(toScreen: NSPoint(x: content.bounds.maxX - 160,
                                                         y: content.bounds.midY))
        let process = Process(), pipe = Pipe()
        process.executableURL = Bundle.main.executableURL
        process.arguments = ["--ax-read", String(ProcessInfo.processInfo.processIdentifier),
                             String(Double(point.x)), String(Double(NSScreen.screens[0].frame.maxY - point.y))]
        process.standardOutput = pipe
        process.terminationHandler = { [weak self] child in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let result = message.isEmpty ? "The reader exited with status \(child.terminationStatus) and printed nothing." : message
            DispatchQueue.main.async {
                self?.status.stringValue = result
                self?.reader = nil
            }
        }
        reader = process
        status.stringValue = "Reading the accessibility tree…"
        do { try process.run() }
        catch { reader = nil; status.stringValue = "Could not launch the reader." }
    }
}

@main
struct Launcher {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if args.count == 5, args[1] == "--ax-read",
           let pid = Int32(args[2]), let x = Float(args[3]), let y = Float(args[4]),
           NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == Bundle.main.bundleIdentifier {
            var element: AXUIElement?, owner: pid_t = 0
            let system = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(system, 5)
            let error = AXUIElementCopyElementAtPosition(system, x, y, &element)
            if let element { AXUIElementGetPid(element, &owner) }
            print(error == .success && owner == pid
                  ? "Read succeeded. Scroll the right panel again — the app will stop responding."
                  : "Read failed: AX error \(error.rawValue), target PID \(owner).")
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let menu = NSMenu(), item = NSMenuItem(), submenu = NSMenu()
        submenu.addItem(withTitle: "Quit AccessibilityLazyVStackPoC", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu; menu.addItem(item); app.mainMenu = menu
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
