import SwiftUI

struct ContentView: View {
    @Bindable var engine: UsageEngine
    @State private var showSettings = false
    @State private var confirmReset = false

    private var ringColor: Color {
        let f = engine.fraction
        if f >= 1 { return .red }
        if f >= engine.state.thresholdPercent / 100 { return .orange }
        return .green
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    summaryCard

                    HStack(spacing: 12) {
                        tile(title: "واي فاي", icon: "wifi",
                             bytes: Double(engine.state.wifiBytes), tint: .blue)
                        tile(title: "بيانات الجوال", icon: "antenna.radiowaves.left.and.right",
                             bytes: Double(engine.state.cellBytes), tint: .green)
                    }

                    controls
                    footer
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("عداد الاستهلاك")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(engine: engine)
                    .environment(\.layoutDirection, .rightToLeft)
            }
            .confirmationDialog("تصفير العدادات؟", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("تصفير", role: .destructive) { engine.reset() }
                Button("إلغاء", role: .cancel) {}
            }
            .alert(engine.pendingAlert?.title ?? "",
                   isPresented: Binding(get: { engine.pendingAlert != nil },
                                        set: { if !$0 { engine.pendingAlert = nil } })) {
                Button("حسناً", role: .cancel) {}
            } message: {
                Text(engine.pendingAlert?.message ?? "")
            }
        }
    }

    // MARK: - Pieces

    private var summaryCard: some View {
        VStack(spacing: 14) {
            Text(engine.state.source.title)
                .font(.subheadline).foregroundStyle(.secondary)

            ZStack {
                Circle().stroke(Color.gray.opacity(0.2), lineWidth: 16)
                Circle()
                    .trim(from: 0, to: min(engine.fraction, 1))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: engine.fraction)

                VStack(spacing: 4) {
                    Text("\(Int(engine.fraction * 100))%")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(ByteFormat.string(engine.monitoredBytes))
                        .font(.headline).monospacedDigit()
                }
            }
            .frame(width: 190, height: 190)
            .padding(.vertical, 6)

            HStack {
                labeled("الكمية", "\(trim(engine.state.quotaValue)) \(engine.state.quotaUnit.title)")
                Spacer()
                labeled("المتبقي", ByteFormat.string(engine.remainingBytes))
                Spacer()
                labeled("التنبيه عند", "\(Int(engine.state.thresholdPercent))%")
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func tile(title: String, icon: String, bytes: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline).foregroundStyle(tint)
            Text(ByteFormat.string(bytes))
                .font(.title2.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                if engine.state.isRunning {
                    engine.stop()
                } else {
                    engine.start()
                }
            } label: {
                Label(engine.state.isRunning ? "إيقاف" : "تشغيل",
                      systemImage: engine.state.isRunning ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.state.isRunning ? .orange : .green)

            Button(role: .destructive) { confirmReset = true } label: {
                Label("تصفير", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if engine.state.isRunning, let s = engine.state.startedAt {
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text("العداد يعمل منذ")
                    Text(s, style: .relative)
                }
                .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("العداد متوقف").font(.footnote).foregroundStyle(.secondary)
            }
            Text("الاستهلاك المحسوب هو كل ما يمر عبر الشبكة منذ الضغط على «تشغيل».")
                .font(.caption2).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    private func labeled(_ t: String, _ v: String) -> some View {
        VStack(spacing: 2) {
            Text(t).font(.caption).foregroundStyle(.secondary)
            Text(v).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }

    private func trim(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Bindable var engine: UsageEngine
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("الكمية") {
                    HStack {
                        TextField("الكمية", value: $engine.state.quotaValue, format: .number)
                            .keyboardType(.decimalPad)
                            .focused($focused)
                        Picker("الوحدة", selection: $engine.state.quotaUnit) {
                            ForEach(UsageEngine.DataUnit.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                    }
                    Picker("الحساب على", selection: $engine.state.source) {
                        ForEach(UsageEngine.Source.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    VStack(alignment: .leading) {
                        Text("تنبيه عند \(Int(engine.state.thresholdPercent))%  (≈ \(ByteFormat.string(engine.quotaBytes * engine.state.thresholdPercent / 100)))")
                        Slider(value: $engine.state.thresholdPercent, in: 1...99, step: 1)
                    }
                } header: {
                    Text("تنبيه النسبة")
                } footer: {
                    Text("هيجيلك تنبيه إضافي تلقائي عند استهلاك الكمية كاملة (100%).")
                }
            }
            .navigationTitle("الإعدادات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { focused = false; dismiss() }
                }
            }
            .onDisappear { engine.settingsChanged() }
        }
    }
}
