//
//  SwiftUIView.swift
//
//
//  Created by ErrorErrorError on 3/9/23.
//
//

import SwiftUI

// MARK: - DismissableModifier

public struct DismissableModifier: ViewModifier {
    let animation: Animation?
    @State
    var dismissed = false

    public func body(content: Content) -> some View {
        if !dismissed {
            content
                .highPriorityGesture(
                    DragGesture()
                        .onEnded { _ in
                            withAnimation(animation) {
                                dismissed = true
                            }
                        }
                )
        }
    }
}

public extension View {
    func dismissable(_ animation: Animation? = nil) -> some View {
        modifier(DismissableModifier(animation: animation))
    }
}
