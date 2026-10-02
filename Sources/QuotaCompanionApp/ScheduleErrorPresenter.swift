import SwiftUI

struct ScheduleErrorPresenter: View {
    @ObservedObject var secretary: SecretaryModel
    let copy: Copybook
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .ownedAlert(copy.text("日程操作未完成", "Schedule operation failed"), isPresented: Binding(get: { !secretary.error.isEmpty && secretary.editor == nil }, set: { if !$0 { secretary.error = "" } })) {
                Button(copy.text("确定", "OK")) { secretary.error = "" }
            } message: { Text(secretary.error) }
    }
}
