//
//  SettingsGroupView.swift
//
//
//  Created by ErrorErrorError on 1/12/23.
//
//

import SwiftUI

// MARK: - SettingsGroupView

public struct SettingsGroupView<Label: View, Items: View>: View {
    let label: () -> Label
    let items: () -> Items

    var spacing = 1.0
    var backgroundColor: Color? = Color(white: 0.3)
    var cornerRadius = 12.0
    var cornerItems = false

    public init(
        @ViewBuilder label: @escaping () -> Label,
        @ViewBuilder items: @escaping () -> Items
    ) {
        self.label = label
        self.items = items
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            label()
            VStack(spacing: spacing) {
                items()
                    .cornerRadius(cornerItems ? cornerRadius : 0)
            }
            .background(backgroundColor)
            .cornerRadius(cornerRadius)
        }
    }
}

public extension SettingsGroupView {
    func cornerRadius(_ cornerRadius: Double, cornerItems: Bool = false) -> Self {
        var view = self
        view.cornerItems = cornerItems
        view.cornerRadius = cornerRadius
        return view
    }

    func backgroundColor(_ color: Color?) -> Self {
        var view = self
        view.backgroundColor = color
        return view
    }

    func spacing(_ spacing: Double) -> Self {
        var view = self
        view.spacing = spacing
        return view
    }
}

// MARK: - GroupLabel

public struct GroupLabel: View {
    let title: String
    let padding = 12.0

    public var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(padding)
            .padding(.vertical, 4)
    }
}

public extension SettingsGroupView {
    init(
        title: String,
        @ViewBuilder items: @escaping () -> Items
    ) where Label == GroupLabel {
        self.init(
            label: { GroupLabel(title: title) },
            items: items
        )
    }

    init(@ViewBuilder items: @escaping () -> Items) where Label == EmptyView {
        self.init(
            label: { EmptyView() },
            items: items
        )
    }
}

// MARK: - SettingsGroupView_Previews

struct SettingsGroupView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsGroupView(title: "Group 1") {
            SettingsRowView(name: "Yes")
            SettingsRowView(
                name: "No",
                text: "haha"
            )
        }
        .previewLayout(.sizeThatFits)
        .padding()
        .background(Color(white: 0.1))
    }
}
