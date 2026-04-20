import SwiftUI

struct SettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue

    var body: some View {
        TabView {
            GeneralSettingsView(appearanceMode: $appearanceMode)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            PrinterCalibrationSettingsView()
                .tabItem {
                    Label("Printer Calibration", systemImage: "printer")
                }
        }
        .frame(width: 500, height: 420)
    }
}

// MARK: - General Settings

private struct GeneralSettingsView: View {
    @Binding var appearanceMode: String

    var body: some View {
        Form {
            Section {
                Picker("Color Mode", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(mode.rawValue).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .onChange(of: appearanceMode) { _, newValue in
            AppearanceMode(rawValue: newValue)?.apply()
        }
    }
}

// MARK: - Printer Calibration Settings

/// Wrapper to ensure `.sheet(item:)` creates a fresh view every time.
/// Each instance has a unique ID, so SwiftUI never reuses stale state.
struct CalibrationSheetItem: Identifiable {
    let id = UUID()
    let calibration: PrinterCalibration?
}

@MainActor
struct PrinterCalibrationSettingsView: View {
    @ObservedObject private var store = PrinterCalibrationStore.shared
    @State private var sheetItem: CalibrationSheetItem?
    @State private var selectedCalibrationId: UUID?

    var body: some View {
        Form {
            Section {
                Text("Print a calibration test page, measure the 150mm square with a ruler, then enter the measured dimensions to correct for printer scaling inaccuracies.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Print Calibration Test Page") {
                    PrintCoordinator.printCalibrationPage(from: NSApp.keyWindow)
                }
            } header: {
                Text("Calibration")
            }

            Section {
                if store.calibrations.isEmpty {
                    Text("No printer calibrations configured.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    List(selection: $selectedCalibrationId) {
                        ForEach(store.calibrations) { cal in
                            CalibrationRow(calibration: cal)
                                .tag(cal.id)
                                .contextMenu {
                                    Button("Edit...") {
                                        sheetItem = CalibrationSheetItem(calibration: cal)
                                    }
                                    Button("Delete", role: .destructive) {
                                        store.delete(id: cal.id)
                                    }
                                }
                        }
                    }
                    .frame(minHeight: 100)
                }

                HStack {
                    Button("Add Calibration...") {
                        sheetItem = CalibrationSheetItem(calibration: nil)
                    }

                    Spacer()

                    Button("Edit...") {
                        if let id = selectedCalibrationId,
                           let cal = store.calibrations.first(where: { $0.id == id }) {
                            sheetItem = CalibrationSheetItem(calibration: cal)
                        }
                    }
                    .disabled(selectedCalibrationId == nil)

                    Button("Delete") {
                        if let id = selectedCalibrationId {
                            store.delete(id: id)
                            selectedCalibrationId = nil
                        }
                    }
                    .disabled(selectedCalibrationId == nil)
                }
            } header: {
                Text("Printer Profiles")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Printer Calibration")
        .onAppear {
            store.load()
        }
        .sheet(item: $sheetItem) { item in
            CalibrationEditSheet(
                calibration: item.calibration,
                onSave: { cal in
                    store.addOrUpdate(cal)
                    sheetItem = nil
                },
                onCancel: {
                    sheetItem = nil
                }
            )
        }
    }
}

// MARK: - Calibration Row

private struct CalibrationRow: View {
    let calibration: PrinterCalibration

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(calibration.printerName)
                .font(.body)
            HStack(spacing: 12) {
                Text("X: \(String(format: "%.4f", calibration.scaleX))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Y: \(String(format: "%.4f", calibration.scaleY))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(calibration.updatedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Calibration Edit Sheet

private struct CalibrationEditSheet: View {
    let calibration: PrinterCalibration?
    let onSave: (PrinterCalibration) -> Void
    let onCancel: () -> Void

    @State private var printerName: String = ""
    @State private var measuredX: String = "150.00"
    @State private var measuredY: String = "150.00"
    @State private var computedScaleX: Double = 1.0
    @State private var computedScaleY: Double = 1.0

    private var availablePrinters: [String] {
        NSPrinter.printerNames
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(calibration == nil ? "キャリブレーション追加" : "キャリブレーション編集")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("プリンター:")
                        .gridColumnAlignment(.trailing)
                    if availablePrinters.isEmpty {
                        TextField("プリンター名", text: $printerName)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Picker("", selection: $printerName) {
                            Text("選択してください").tag("")
                            ForEach(availablePrinters, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .labelsHidden()
                    }
                }

                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Text("キャリブレーション用 150mm 正方形の実測値を入力してください:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GridRow {
                    Text("実測 X (mm):")
                    TextField("150.00", text: $measuredX)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .onChange(of: measuredX) { _, _ in recalculate() }
                }

                GridRow {
                    Text("実測 Y (mm):")
                    TextField("150.00", text: $measuredY)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .onChange(of: measuredY) { _, _ in recalculate() }
                }

                Divider()
                    .gridCellUnsizedAxes(.vertical)
                    .gridCellColumns(2)

                GridRow {
                    Text("補正倍率 X:")
                    Text(String(format: "%.4f", computedScaleX))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                GridRow {
                    Text("補正倍率 Y:")
                    Text(String(format: "%.4f", computedScaleY))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                let deviation = max(abs(computedScaleX - 1.0), abs(computedScaleY - 1.0)) * 100
                if deviation > 5 {
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        Text("警告: 補正が 5% を超えています。測定値を確認してください。")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            HStack {
                Button("キャンセル") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("保存") {
                    var cal: PrinterCalibration
                    if let existing = calibration {
                        cal = existing
                        cal.printerName = printerName
                        cal.scaleX = computedScaleX
                        cal.scaleY = computedScaleY
                    } else {
                        cal = PrinterCalibration(
                            printerName: printerName,
                            scaleX: computedScaleX,
                            scaleY: computedScaleY
                        )
                    }
                    onSave(cal)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(printerName.isEmpty)
            }
        }
        .padding()
        .frame(width: 420)
        .onAppear {
            if let cal = calibration {
                printerName = cal.printerName
                let mx = 150.0 / cal.scaleX
                let my = 150.0 / cal.scaleY
                measuredX = String(format: "%.2f", mx)
                measuredY = String(format: "%.2f", my)
                computedScaleX = cal.scaleX
                computedScaleY = cal.scaleY
            }
        }
    }

    private func recalculate() {
        if let mx = Double(measuredX), mx > 0 {
            computedScaleX = 150.0 / mx
        }
        if let my = Double(measuredY), my > 0 {
            computedScaleY = 150.0 / my
        }
    }
}
