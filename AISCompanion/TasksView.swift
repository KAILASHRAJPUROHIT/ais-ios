import SwiftUI

struct TasksView: View {
    @State private var title = ""
    @State private var status = ""
    private let api = AisApi()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 12) {
                    Text("DISPATCH A TASK")
                        .font(.caption2).foregroundColor(Theme.dim)
                    TextField("Task title", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .padding(10)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent))
                    Button("CREATE TASK") { create() }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    if !status.isEmpty {
                        Text(status).font(.caption).foregroundColor(Theme.dim)
                    }
                    Spacer()
                    Text("""
                    Completion is derived by the backend from evidence. The API
                    rejects a direct status=COMPLETED with HTTP 422, so a task
                    can never be marked done merely by claiming it.
                    """)
                    .font(.caption).foregroundColor(Theme.dim)
                    Spacer()
                }
                .padding(14)
            }
            .navigationTitle("TASKS")
        }
    }

    private func create() {
        status = "CREATING"
        Task {
            do {
                try await api.createTask(title.trimmingCharacters(in: .whitespacesAndNewlines))
                status = "Task created. The backend will run and verify it."
                title = ""
            } catch let e as AisApi.ApiError {
                status = e.isTransportFailure
                    ? "Cannot reach AIS."
                    : "Rejected: \(e.localizedDescription)"
            } catch {
                status = "Failed."
            }
        }
    }
}
