//
//  ContentView.swift
//  Cloudvia
//
//  Created by Mehrdad Nassiri on 2025/4/26.
//

import SwiftUI

@main
struct Cloudvia: App {
    let escKeyHandler = EscKeyHandler.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 750, minHeight: 600)
        }
        
        #if os(macOS)
        Settings {
            SettingsView(viewModel: CloudviaViewModel())
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Cloudvia") {
                    showAbout()
                }
            }
        }
        #endif
    }
    
    private func showAbout() {
        let aboutWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        aboutWindow.center()
        aboutWindow.title = "About Cloudvia"
        aboutWindow.isReleasedWhenClosed = false
        aboutWindow.contentView = NSHostingView(rootView: AboutView())
        aboutWindow.makeKeyAndOrderFront(nil)
    }
}

#Preview {
    ContentView()
}
