//
//  StepperView.swift
//
//
//  Created by ErrorErrorError on 3/10/23.
//
//

import SwiftUI

// MARK: - StepperView

public struct StepperView<Label: View>: View {
    let label: (() -> Label)?
    let increment: () -> Void
    let decrement: () -> Void
    var minusDisabled = false
    var plusDisabled = false

    public init(
        label: (() -> Label)? = nil,
        increment: @escaping () -> Void = {},
        decrement: @escaping () -> Void = {}
    ) {
        self.label = label
        self.increment = increment
        self.decrement = decrement
    }

    public var body: some View {
        HStack(spacing: 0) {
            Button {
                decrement()
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light)
                    .impactOccurred()
                #endif
            } label: {
                Image(systemName: "minus")
                    .foregroundColor(minusDisabled ? .gray : .white)
                    .frame(maxHeight: .infinity)
                    .frame(width: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(minusDisabled)

            if let label {
                Divider()
                    .frame(maxHeight: .infinity)
                    .padding([.top, .bottom], 8)
                label()
            }

            Divider()
                .frame(maxHeight: .infinity)
                .padding([.top, .bottom], 8)

            Button {
                increment()
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light)
                    .impactOccurred()
                #endif
            } label: {
                Image(systemName: "plus")
                    .foregroundColor(plusDisabled ? .gray : .white)
                    .frame(maxHeight: .infinity)
                    .frame(width: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(plusDisabled)
        }
        .frame(height: 32)
        .background(Color.gray.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

public extension StepperView {
    init(
        increment: @escaping () -> Void = {},
        decrement: @escaping () -> Void = {}
    ) where Label == EmptyView {
        self.init(
            label: nil,
            increment: increment,
            decrement: decrement
        )
    }

    func minusDisabled(_ disabled: Bool) -> Self {
        var copy = self
        copy.minusDisabled = disabled
        return copy
    }

    func plusDisabled(_ disabled: Bool) -> Self {
        var copy = self
        copy.plusDisabled = disabled
        return copy
    }
}

// MARK: - LabeledStepper_Previews

struct LabeledStepper_Previews: PreviewProvider {
    static var previews: some View {
        StepperView()
    }
}
