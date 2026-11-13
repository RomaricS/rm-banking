import SwiftUI
import AkweKit

/// 6.2 Invite a partner to a goal.
struct InviteSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let goal: Goal
    @State private var shareAmount = true
    @State private var shareActivity = true
    @State private var link: URL?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HStack(spacing: 14) {
                        Text(String((app.profile?.displayName ?? "A").prefix(1))).font(.system(size: 24, weight: .heavy)).foregroundStyle(Palette.onInverse)
                            .frame(width: 64, height: 64).background(Color(hex: 0x7C9CFF), in: Circle())
                        Image(systemName: "arrow.right").foregroundStyle(Palette.text2).symbolEffect(.pulse)
                        Image(systemName: "plus").font(.system(size: 22, weight: .bold)).foregroundStyle(Palette.partner)
                            .frame(width: 64, height: 64).overlay(Circle().strokeBorder(Palette.partner.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                    }
                    .padding(.top, 8)
                    Text(tr("invite.explain")).font(.system(size: 15)).foregroundStyle(Palette.text2).multilineTextAlignment(.center)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.name).font(.system(size: 15, weight: .bold))
                            Text("\(money(goal.targetAmount, goal.currency, cents: false))\(goal.targetDate.map { " · \($0.monthYear)" } ?? "")").font(.system(size: 13)).foregroundStyle(Palette.text2)
                        }
                        Spacer()
                    }
                    .card(padding: 14, radius: 16, fill: Palette.raised)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(tr("invite.whatTheySee")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text2).padding(.vertical, 8)
                        permission(tr("invite.progress"), tr("invite.progressHint"), fixed: tr("invite.always"))
                        Toggle(isOn: $shareAmount) { label(tr("invite.amount"), tr("invite.amountHint")) }.tint(Palette.positive).frame(minHeight: 56)
                        Toggle(isOn: $shareActivity) { label(tr("invite.activity"), tr("invite.activityHint")) }.tint(Palette.positive).frame(minHeight: 56)
                        permission(tr("invite.private"), tr("invite.privateHint"), fixed: tr("invite.never"))
                    }
                    .padding(.horizontal, 14)
                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(16)
            }
            .background(Palette.sheet)
            .navigationTitle(tr("invite.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("common.cancel")) { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Group {
                    if let link {
                        ShareLink(item: link, message: Text(tr("invite.message", goal.name))) {
                            Label(tr("invite.send"), systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    } else {
                        Button {
                            loading = true
                            Task { link = await app.inviteLink(for: goal, shareAmount: shareAmount, shareActivity: shareActivity); loading = false }
                        } label: { if loading { ProgressView() } else { Text(tr("invite.create")) } }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(16)
            }
        }
    }

    private func label(_ title: String, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(hint).font(.system(size: 12)).foregroundStyle(Palette.text2)
        }
    }

    private func permission(_ title: String, _ hint: String, fixed: String) -> some View {
        HStack {
            label(title, hint)
            Spacer()
            Text(fixed).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text3)
        }
        .frame(minHeight: 56)
    }
}

/// Opened from an invite link (akwe://join?code=… or https://<domain>/join?code=…).
struct JoinGoalSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let code: String
    @State private var preview: AppModel.InvitePreview?
    @State private var funding: GoalFunding = .manual
    @State private var loading = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if loading {
                    ProgressView().frame(maxHeight: .infinity)
                } else if let preview {
                    Image(systemName: "person.2.fill").font(.system(size: 40)).foregroundStyle(Palette.partner).padding(.top, 24)
                    Text(tr("join.title", preview.inviter, preview.goal.name)).font(.system(size: 22, weight: .heavy)).multilineTextAlignment(.center)
                    Text(tr("join.target", money(preview.goal.targetAmount, preview.goal.currency, cents: false))).foregroundStyle(Palette.text2)
                    Picker(tr("goal.howTrack"), selection: $funding) {
                        Text(tr("goal.funding.manual.option")).tag(GoalFunding.manual)
                        Text(tr("goal.funding.earmark.option")).tag(GoalFunding.earmark)
                    }
                    .pickerStyle(.segmented)
                    Text(tr("join.privacy")).font(.system(size: 13)).foregroundStyle(Palette.text2).multilineTextAlignment(.center)
                    Spacer()
                    Button(tr("join.accept")) { Task { await app.joinGoal(code: code, funding: funding); dismiss() } }.buttonStyle(PrimaryButtonStyle())
                } else {
                    EmptyState(icon: "link.badge.plus", title: tr("join.expired"), message: tr("join.expiredHint"))
                }
            }
            .padding(20)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("common.close")) { dismiss() } } }
            .task {
                if app.phase == .ready { preview = await app.previewInvite(code: code) }
                loading = false
            }
        }
        .presentationDetents([.medium, .large])
    }
}
