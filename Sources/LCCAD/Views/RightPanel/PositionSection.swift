import SwiftUI

struct PositionSection: View {
    @Bindable var editor: EditorViewModel
    let boundingBox: CGRect
    let unit: LengthUnit

    var body: some View {
        PropertySection(title: "Position") {
            HStack(spacing: 8) {
                EditablePropertyField(
                    label: "X",
                    value: unit.fromMillimeters(boundingBox.origin.x),
                    onCommit: { newValue in
                        editor.setSelectedShapePosition(x: unit.toMillimeters(newValue), y: nil)
                    }
                )
                EditablePropertyField(
                    label: "Y",
                    value: unit.fromMillimeters(boundingBox.origin.y),
                    onCommit: { newValue in
                        editor.setSelectedShapePosition(x: nil, y: unit.toMillimeters(newValue))
                    }
                )
            }
        }
    }
}
