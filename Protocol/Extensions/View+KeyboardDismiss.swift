//
//  View+KeyboardDismiss.swift
//  Protocol
//
//  Extensions for dismissing the keyboard throughout the app.
//

import SwiftUI

// MARK: - Keyboard Dismiss Extension

extension View {
    /// Adds a tap gesture that dismisses the keyboard when tapping outside text fields.
    /// Apply this to container views (like NavigationStack or Form) to enable tap-to-dismiss.
    func dismissKeyboardOnTap() -> some View {
        self.onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
    
    /// Adds a toolbar button to dismiss the keyboard.
    /// Apply this to TextField or TextEditor views.
    func keyboardDoneButton() -> some View {
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}

// MARK: - Global Keyboard Dismiss Modifier

/// A view modifier that allows dismissing keyboard by tapping anywhere
struct KeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
    }
}

// MARK: - Hide Keyboard Function

extension UIApplication {
    /// Dismisses the keyboard from anywhere in the app
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
