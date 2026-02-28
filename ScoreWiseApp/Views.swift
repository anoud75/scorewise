import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Speech
import AVFoundation

private enum ClarityPalette {
    static let background = Color(red: 0.96, green: 0.96, blue: 0.95)
    static let surface = Color.white
    static let surfaceSoft = Color(red: 0.95, green: 0.95, blue: 0.94)
    static let ink = Color(red: 0.10, green: 0.10, blue: 0.11)
    static let inkSoft = Color(red: 0.47, green: 0.47, blue: 0.48)
    static let line = Color.black.opacity(0.08)
    static let accent = Color(red: 0.93, green: 0.38, blue: 0.24)
    static let green = Color(red: 0.07, green: 0.64, blue: 0.29)
}

private enum ClarityCopy {
    static let appName = "ScoreWise"
    static let promiseTitle = "Think clearer.\nDecide better."
    static let promiseSubtitle = "A strategic AI that helps you see trade-offs, risks, and blind spots"
}

private enum ClarityType {
    static let heroSerif: Font = .system(size: 31, weight: .bold, design: .serif)
    static let screenSerif: Font = .system(size: 28, weight: .bold, design: .serif)
    static let cardSerif: Font = .system(size: 24, weight: .bold, design: .serif)
    static let sectionSerif: Font = .system(size: 22, weight: .bold, design: .serif)
    static let title: Font = .system(size: 17, weight: .regular)
    static let titleMedium: Font = .system(size: 17, weight: .medium)
    static let body: Font = .system(size: 16, weight: .regular)
    static let bodyMedium: Font = .system(size: 16, weight: .medium)
    static let caption: Font = .system(size: 13, weight: .regular)
    static let smallCaps: Font = .system(size: 12, weight: .semibold)
}

struct RootView: View {
    @EnvironmentObject private var vm: AppViewModel
    @Environment(\.modelContext) private var modelContext

    private var showsTabBar: Bool {
        switch vm.screen {
        case .home, .history, .profile:
            return true
        default:
            return false
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ClarityBackground()

                Group {
                    switch vm.screen {
                    case .launch:
                        LaunchView()
                    case .auth:
                        AuthView()
                    case .onboarding:
                        OnboardingSurveyView()
                    case .postSurveySplash:
                        PostSurveySplashView()
                    case .home:
                        HomeView()
                    case .history:
                        HistoryView()
                    case .ranking:
                        RankingWizardView()
                    case .results:
                        ResultsView()
                    case .profile:
                        ProfileView()
                    }
                }
                .padding(.bottom, showsTabBar ? 86 : 0)

                if showsTabBar {
                    ClarityBottomBar()
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            if vm.screen == .launch {
                vm.bootstrap()
            }
        }
        .onAppear {
            vm.loadRecent(modelContext: modelContext)
        }
        .onChange(of: vm.session?.userID) { _, _ in
            vm.loadRecent(modelContext: modelContext)
        }
        .overlay {
            if let busyMessage = vm.busyMessage {
                VStack {
                    ProgressView(busyMessage)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                        .padding(.top, 12)
                    Spacer()
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { vm.lastError != nil },
            set: { if !$0 { vm.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.lastError ?? "Unknown error")
        }
    }
}

private struct ClarityBackground: View {
    var body: some View {
        ClarityPalette.background
            .ignoresSafeArea()
    }
}

private struct ClarityBottomBar: View {
    @EnvironmentObject private var vm: AppViewModel

    private func isActive(_ target: AppViewModel.Screen) -> Bool {
        vm.screen == target
    }

    var body: some View {
        HStack(spacing: 12) {
            tabButton(icon: "house", label: "Home", screen: .home)
            tabButton(icon: "clock", label: "History", screen: .history)
            tabButton(icon: "person", label: "Profile", screen: .profile)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(ClarityPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(ClarityPalette.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }

    private func tabButton(icon: String, label: String, screen: AppViewModel.Screen) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                vm.screen = screen
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: isActive(screen) ? .semibold : .regular))
                Text(label)
                    .font(.system(size: 12, weight: isActive(screen) ? .semibold : .regular))
            }
            .foregroundStyle(isActive(screen) ? ClarityPalette.ink : ClarityPalette.inkSoft)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

private struct LaunchView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ClarityLogoMark()
                .frame(width: 140, height: 140)
            Text(ClarityCopy.appName)
                .font(.system(size: 38, weight: .bold, design: .serif))
                .foregroundStyle(ClarityPalette.ink)
            Text("Preparing your decision workspace")
                .font(.subheadline)
                .foregroundStyle(ClarityPalette.inkSoft)
            ProgressView()
                .tint(ClarityPalette.ink)
            Spacer()
        }
        .padding(24)
    }
}

private struct AuthView: View {
    private enum Mode {
        case welcome
        case signUp
        case signIn
    }

    @EnvironmentObject private var vm: AppViewModel

    @State private var mode: Mode = .welcome
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var showConfirmPassword = false

    var body: some View {
        VStack {
            switch mode {
            case .welcome:
                welcomeScreen
            case .signUp:
                signUpScreen
            case .signIn:
                signInScreen
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 22)
        .animation(.easeInOut(duration: 0.25), value: mode)
    }

    private var welcomeScreen: some View {
        VStack(spacing: 28) {
            HStack {
                Spacer()

                Button {
                    mode = .signIn
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(ClarityPalette.ink)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 30)

            ClarityLogoMark()
                .frame(width: 168, height: 168)

            VStack(spacing: 14) {
                Text(ClarityCopy.promiseTitle)
                    .font(ClarityType.heroSerif)
                    .foregroundStyle(ClarityPalette.ink)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)

                Text(ClarityCopy.promiseSubtitle)
                    .font(ClarityType.title)
                    .foregroundStyle(ClarityPalette.inkSoft)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button("Start thinking") {
                mode = .signUp
            }
            .buttonStyle(ClarityPrimaryButtonStyle())
        }
    }

    private var signUpScreen: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Step 1 of 3")
                    .font(ClarityType.caption)
                    .foregroundStyle(ClarityPalette.inkSoft)

                Text("Create your\naccount")
                    .font(ClarityType.heroSerif)
                    .foregroundStyle(ClarityPalette.ink)
                    .lineSpacing(-3)

                inputField("First name", text: $firstName)
                inputField("Last name", text: $lastName)
                inputField("Email address", text: $email, keyboard: .emailAddress, capitalization: .never)
                secureField("Password", text: $password, visible: $showPassword)
                secureField("Confirm password", text: $confirmPassword, visible: $showConfirmPassword)

                Button("Create Account") {
                    let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                    guard !email.trimmed.isEmpty, !password.isEmpty, password == confirmPassword, !fullName.isEmpty else {
                        return
                    }
                    vm.createAccount(email: email.trimmed, password: password, fullName: fullName)
                }
                .buttonStyle(ClarityPrimaryButtonStyle())
                .disabled(!canCreateAccount)
                .opacity(canCreateAccount ? 1 : 0.55)

                Button {
                    mode = .signIn
                } label: {
                    Text("Already have an account?") + Text(" Log In").underline()
                }
                .font(ClarityType.body)
                .foregroundStyle(ClarityPalette.ink)
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 6)
        }
    }

    private var signInScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 20)

            Text("Welcome\nback")
                .font(ClarityType.heroSerif)
                .foregroundStyle(ClarityPalette.ink)
                .lineSpacing(-3)

            inputField("Email address", text: $email, keyboard: .emailAddress, capitalization: .never)
            secureField("Password", text: $password, visible: $showPassword)

            Spacer()

            Button("Log In") {
                vm.signInEmail(email: email.trimmed, password: password)
            }
            .buttonStyle(ClarityPrimaryButtonStyle())
            .disabled(email.trimmed.isEmpty || password.isEmpty)
            .opacity(email.trimmed.isEmpty || password.isEmpty ? 0.55 : 1)

            Button {
                mode = .signUp
            } label: {
                Text("Don't have an account?") + Text(" Sign Up").underline()
            }
            .font(ClarityType.body)
            .foregroundStyle(ClarityPalette.ink)
            .frame(maxWidth: .infinity)
        }
    }

    private var canCreateAccount: Bool {
        !firstName.trimmed.isEmpty && !lastName.trimmed.isEmpty && !email.trimmed.isEmpty && !password.isEmpty && password == confirmPassword
    }

    private func inputField(
        _ placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        capitalization: TextInputAutocapitalization = .sentences
    ) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled()
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .background(ClarityPalette.surfaceSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(ClarityPalette.line, lineWidth: 1)
            )
            .font(ClarityType.body)
    }

    private func secureField(_ placeholder: String, text: Binding<String>, visible: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Group {
                if visible.wrappedValue {
                    TextField(placeholder, text: text)
                } else {
                    SecureField(placeholder, text: text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                visible.wrappedValue.toggle()
            } label: {
                Image(systemName: visible.wrappedValue ? "eye.slash" : "eye")
                    .foregroundStyle(ClarityPalette.inkSoft)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .background(ClarityPalette.surfaceSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ClarityPalette.line, lineWidth: 1)
        )
        .font(ClarityType.body)
    }
}

private struct OnboardingSurveyView: View {
    @EnvironmentObject private var vm: AppViewModel
    @Environment(\.modelContext) private var modelContext

    private let steps = 6
    private let usageOptions = ["Work", "Personal", "Education", "Recruiting", "Hiring", "Career Planning", "Business Strategy", "Investment", "Health & Wellness", "Relationships", "Finance", "Other"]
    private let styleOptions = [
        "I analyze everything deeply (Analytical)",
        "I trust my gut feeling (Intuitive)",
        "It depends on the situation (Balanced)"
    ]
    private let challengeOptions = [
        "I overthink and get stuck in loops",
        "I'm afraid of making the wrong choice",
        "Too many options overwhelm me",
        "I don't have enough information"
    ]
    private let depthOptions = [
        "Quick clarity - just help me decide",
        "Deep analysis - show me everything",
        "Depends on the stakes"
    ]
    private let frequentDecisionOptions = ["Career", "Finance", "Health & Wellness", "Relationships", "Business", "Education", "Lifestyle", "Creativity", "Parenting", "Legal"]

    @State private var stepIndex = 0
    @State private var selectedUsage: Set<String> = []
    @State private var decisionStyle = ""
    @State private var decisionChallenge = ""
    @State private var analysisDepth = ""
    @State private var priorities = ["Growth & learning", "Security & stability", "Freedom & independence", "Relationships & connection", "Achievement & recognition"]
    @State private var selectedDecisionTypes: Set<String> = []

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button {
                    handleSurveyBack()
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(stepIndex == 0 ? Color.gray : ClarityPalette.ink)
                }
                .buttonStyle(.plain)
                .disabled(stepIndex == 0)

                Spacer()
                NotificationBellIcon()
            }
            .padding(.horizontal, 24)

            mainCard
                .padding(.horizontal, 20)
                .shadow(color: .black.opacity(0.05), radius: 14, y: 6)

            Spacer(minLength: 0)
        }
        .padding(.top, 10)
    }

    private var mainCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            progressBars

            Text(String(format: "Q. %02d", stepIndex + 1))
                .font(.system(size: 14, weight: .regular).monospacedDigit())
                .foregroundStyle(ClarityPalette.inkSoft)

            Text(questionTitle)
                .font(ClarityType.screenSerif)
                .lineSpacing(-2)
                .foregroundStyle(ClarityPalette.ink)
                .minimumScaleFactor(0.75)

            Text("This will help us to create the best experience for you")
                .font(ClarityType.title)
                .foregroundStyle(ClarityPalette.inkSoft)

            ScrollView(showsIndicators: false) {
                stepBody
            }

            Spacer(minLength: 2)

            footer
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ClarityPalette.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(ClarityPalette.line, lineWidth: 1)
        )
    }

    private var progressBars: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< steps, id: \.self) { index in
                Capsule()
                    .fill(index <= stepIndex ? ClarityPalette.accent : Color.gray.opacity(0.20))
                    .frame(height: 4)
            }
        }
    }

    private var questionTitle: String {
        switch stepIndex {
        case 0: return "What is your primary usage?"
        case 1: return "How do you usually make decisions?"
        case 2: return "What's your biggest decision challenge?"
        case 3: return "When facing a decision, do you prefer..."
        case 4: return "Rank what matters most to you"
        default: return "What decisions do you face most?"
        }
    }

    @ViewBuilder
    private var stepBody: some View {
        switch stepIndex {
        case 0:
            selectionChips(usageOptions, selected: selectedUsage)
        case 1:
            VStack(spacing: 10) {
                ForEach(styleOptions, id: \.self) { option in
                    Button {
                        decisionStyle = option
                    } label: {
                        singleChoiceRow(option, selected: decisionStyle == option)
                    }
                    .buttonStyle(.plain)
                }
            }
        case 2:
            VStack(spacing: 10) {
                ForEach(challengeOptions, id: \.self) { option in
                    Button {
                        decisionChallenge = option
                    } label: {
                        singleChoiceRow(option, selected: decisionChallenge == option)
                    }
                    .buttonStyle(.plain)
                }
            }
        case 3:
            VStack(spacing: 10) {
                ForEach(depthOptions, id: \.self) { option in
                    Button {
                        analysisDepth = option
                    } label: {
                        singleChoiceRow(option, selected: analysisDepth == option)
                    }
                    .buttonStyle(.plain)
                }
            }
        case 4:
            VStack(alignment: .leading, spacing: 10) {
                Text("DRAG TO REORDER")
                    .font(ClarityType.smallCaps)
                    .kerning(0.6)
                    .foregroundStyle(ClarityPalette.accent)
                ForEach(priorities.indices, id: \.self) { index in
                    HStack(spacing: 10) {
                        Image(systemName: "circle.grid.2x2.fill")
                            .foregroundStyle(ClarityPalette.inkSoft)
                        Text(priorities[index])
                            .font(ClarityType.body)
                        Spacer()
                        Button {
                            movePriority(index, by: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ClarityPalette.inkSoft)
                        .disabled(index == 0)

                        Button {
                            movePriority(index, by: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ClarityPalette.inkSoft)
                        .disabled(index == priorities.count - 1)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(ClarityPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(ClarityPalette.line, lineWidth: 1)
                    )
                }
            }
        default:
            VStack(alignment: .leading, spacing: 12) {
                Text("SELECT ALL THAT APPLY")
                    .font(ClarityType.smallCaps)
                    .kerning(0.6)
                    .foregroundStyle(ClarityPalette.accent)
                selectionChips(frequentDecisionOptions, selected: selectedDecisionTypes)
            }
        }
    }

    private var footer: some View {
        HStack {
            if stepIndex == 0 {
                Text("Select 2")
                    .font(ClarityType.body)
                    .foregroundStyle(ClarityPalette.inkSoft)
                    .frame(maxWidth: .infinity)
            } else if stepIndex == 5 {
                Text("Select at least 2")
                    .font(ClarityType.body)
                    .foregroundStyle(ClarityPalette.inkSoft)
                    .frame(maxWidth: .infinity)
            }

            Button(stepIndex == steps - 1 ? "Done" : "Next") {
                if stepIndex == steps - 1 {
                    finishOnboarding()
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        stepIndex += 1
                    }
                }
            }
            .buttonStyle(ClarityPrimaryButtonStyle())
            .frame(width: 130)
            .disabled(!canContinue)
            .opacity(canContinue ? 1 : 0.45)
        }
    }

    private func handleSurveyBack() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if stepIndex > 0 {
                stepIndex -= 1
            }
        }
    }

    private var canContinue: Bool {
        switch stepIndex {
        case 0: return selectedUsage.count >= 2
        case 1: return !decisionStyle.isEmpty
        case 2: return !decisionChallenge.isEmpty
        case 3: return !analysisDepth.isEmpty
        case 4: return priorities.count >= 3
        default: return selectedDecisionTypes.count >= 2
        }
    }

    private func movePriority(_ index: Int, by offset: Int) {
        let newIndex = index + offset
        guard priorities.indices.contains(index), priorities.indices.contains(newIndex) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            let item = priorities.remove(at: index)
            priorities.insert(item, at: newIndex)
        }
    }

    private func finishOnboarding() {
        var mapped: [String: String] = [:]
        mapped["purpose"] = selectedUsage.first ?? "Work"
        mapped["pace"] = mapPace(from: analysisDepth)
        mapped["risk"] = mapRisk(from: decisionChallenge)
        mapped["evidence"] = mapEvidence(from: analysisDepth)
        mapped["collaboration"] = selectedUsage.contains("Work") || selectedUsage.contains("Business Strategy") ? "Team" : "Solo"
        mapped["focus"] = mapFocus(from: priorities.first)
        mapped["planning"] = mapPlanning(from: analysisDepth)
        mapped["review"] = "Often"

        let answers = SurveyTagger.questions.map { question in
            SurveyAnswer(questionID: question.id, value: mapped[question.id] ?? question.options.first ?? "")
        }

        let context = usageContextFromSelection()
        vm.completeOnboarding(
            context: context,
            answers: answers,
            valuesRanking: priorities,
            interests: Array(selectedDecisionTypes).sorted(),
            modelContext: modelContext
        )
    }

    private func usageContextFromSelection() -> UsageContext {
        if selectedUsage.contains("Work") || selectedUsage.contains("Business Strategy") {
            return .work
        }
        if selectedUsage.contains("Personal") {
            return .personal
        }
        if selectedUsage.contains("Education") {
            return .education
        }
        return .other
    }

    private func mapPace(from value: String) -> String {
        if value.contains("Quick") { return "Very fast" }
        if value.contains("Deep") { return "Very careful" }
        return "Balanced"
    }

    private func mapRisk(from value: String) -> String {
        if value.contains("afraid") || value.contains("wrong") { return "Risk-averse" }
        if value.contains("overwhelm") || value.contains("stuck") { return "Neutral" }
        return "Neutral"
    }

    private func mapEvidence(from value: String) -> String {
        if value.contains("Deep") { return "High" }
        if value.contains("Quick") { return "Low" }
        return "Medium"
    }

    private func mapPlanning(from value: String) -> String {
        if value.contains("Deep") { return "Long-term" }
        if value.contains("Quick") { return "Short-term" }
        return "Mid-term"
    }

    private func mapFocus(from firstPriority: String?) -> String {
        guard let firstPriority else { return "Trust" }
        if firstPriority.lowercased().contains("security") { return "Cost" }
        if firstPriority.lowercased().contains("achievement") { return "Quality" }
        if firstPriority.lowercased().contains("freedom") { return "Speed" }
        return "Trust"
    }

    private func singleChoiceRow(_ text: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Circle()
                .stroke(ClarityPalette.ink, lineWidth: 2)
                .frame(width: 20, height: 20)
                .overlay {
                    if selected {
                        Circle()
                            .fill(ClarityPalette.ink)
                            .frame(width: 10, height: 10)
                    }
                }

            Text(text)
                .font(ClarityType.body)
                .foregroundStyle(ClarityPalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(ClarityPalette.surfaceSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ClarityPalette.line, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func selectionChips(_ options: [String], selected: Set<String>) -> some View {
        FlowLayout(spacing: 12, rowSpacing: 12) {
            ForEach(options, id: \.self) { option in
                let active = selected.contains(option)
                Button(option) {
                    toggleSelection(option)
                }
                .buttonStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 42)
                .padding(.horizontal, 16)
                .background(active ? ClarityPalette.ink : ClarityPalette.surfaceSoft, in: Capsule())
                .foregroundStyle(active ? Color.white : ClarityPalette.ink)
                .overlay(
                    Capsule()
                        .stroke(active ? Color.clear : ClarityPalette.line, lineWidth: 1)
                )
            }
        }
    }

    private func toggleSelection(_ option: String) {
        switch stepIndex {
        case 0:
            if selectedUsage.contains(option) {
                selectedUsage.remove(option)
            } else {
                selectedUsage.insert(option)
            }
        case 5:
            if selectedDecisionTypes.contains(option) {
                selectedDecisionTypes.remove(option)
            } else {
                selectedDecisionTypes.insert(option)
            }
        default:
            break
        }
    }
}

private struct PostSurveySplashView: View {
    @EnvironmentObject private var vm: AppViewModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Circle()
                .fill(ClarityPalette.surface)
                .frame(width: 84, height: 84)
                .overlay(Circle().stroke(ClarityPalette.line, lineWidth: 1))
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(ClarityPalette.ink)
                )

            Text("Welcome, \(firstName(vm.session?.displayName ?? "Julian"))")
                .font(ClarityType.heroSerif)
                .foregroundStyle(ClarityPalette.ink)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)

            Text("Let's think clearly.")
                .font(ClarityType.title)
                .foregroundStyle(ClarityPalette.inkSoft)

            Spacer()

            Button("Start your first decision") {
                vm.continueFromPostSurveySplash()
            }
            .buttonStyle(ClarityPrimaryButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private func firstName(_ full: String) -> String {
        full.split(separator: " ").first.map(String.init) ?? full
    }
}

private struct HomeView: View {
    @EnvironmentObject private var vm: AppViewModel
    @StateObject private var transcriber = SpeechTranscriber()
    @State private var narrative = ""

    private let contextTags = ["Product / Business", "Career move", "Personal priorities"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 48, height: 48)
                            .overlay(
                                Text(initials(vm.session?.displayName ?? "Julian Mercer"))
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.white)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Good Evening,")
                                .font(ClarityType.caption)
                                .foregroundStyle(ClarityPalette.inkSoft)
                            Text(vm.session?.displayName ?? "Julian Mercer")
                                .font(ClarityType.titleMedium)
                                .foregroundStyle(ClarityPalette.ink)
                        }
                    }

                    Spacer()

                    Button {
                        vm.screen = .profile
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.title3)
                            .foregroundStyle(ClarityPalette.ink)
                            .frame(width: 42, height: 42)
                            .background(ClarityPalette.surface, in: Circle())
                            .overlay(Circle().stroke(ClarityPalette.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                Text("What decision are\nyou stuck with?")
                    .font(ClarityType.heroSerif)
                    .lineSpacing(-2)
                    .foregroundStyle(ClarityPalette.ink)

                Text("Describe the situation. I'll help you see it without emotion or bias.")
                    .font(ClarityType.title)
                    .foregroundStyle(ClarityPalette.inkSoft)

                HStack(spacing: 10) {
                    TextField("Explain the situation briefly...", text: $narrative, axis: .vertical)
                        .lineLimit(2 ... 4)
                        .font(ClarityType.body)
                        .textInputAutocapitalization(.sentences)

                    Button {
                        Task {
                            if transcriber.isRecording {
                                transcriber.stop()
                                if !transcriber.transcript.isEmpty {
                                    if !narrative.isEmpty { narrative += " " }
                                    narrative += transcriber.transcript
                                    transcriber.clearTranscript()
                                }
                            } else {
                                await transcriber.start()
                            }
                        }
                    } label: {
                        Image(systemName: transcriber.isRecording ? "stop.fill" : "mic")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(Color.black, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(ClarityPalette.surfaceSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(ClarityPalette.line, lineWidth: 1)
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(contextTags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 15, weight: .regular))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(ClarityPalette.surfaceSoft, in: Capsule())
                                .overlay(Capsule().stroke(ClarityPalette.line, lineWidth: 1))
                        }
                    }
                }

                if vm.expressModeAvailable {
                    Button {
                        vm.setExpressMode(!vm.expressModeEnabled)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: vm.expressModeEnabled ? "bolt.fill" : "bolt")
                                .font(.system(size: 14, weight: .medium))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Quick clarity")
                                    .font(ClarityType.bodyMedium)
                                Text("Describe, get AI analysis, decide.")
                                    .font(ClarityType.caption)
                                    .foregroundStyle(vm.expressModeEnabled ? Color.white.opacity(0.85) : ClarityPalette.inkSoft)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(vm.expressModeEnabled ? Color.black : ClarityPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(vm.expressModeEnabled ? Color.white : ClarityPalette.ink)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(ClarityPalette.line, lineWidth: vm.expressModeEnabled ? 0 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button("Start Decision") {
                    vm.startNewComparison()
                    vm.activeDraft.contextNarrative = narrative.trimmed
                    vm.activeDraft.title = makeTitle(from: narrative)
                }
                .buttonStyle(ClarityPrimaryButtonStyle())
                .padding(.top, 6)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
    }

    private func initials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        let value = String(letters)
        return value.isEmpty ? "JM" : value.uppercased()
    }

    private func makeTitle(from value: String) -> String {
        let trimmed = value.trimmed
        if trimmed.isEmpty {
            return "Untitled Decision"
        }
        return String(trimmed.prefix(56))
    }
}

private struct RankingWizardView: View {
    private enum Step: Int, CaseIterable {
        case describe = 0
        case clarify
        case options
        case weigh
        case challenge
        case analysis

        var title: String {
            switch self {
            case .describe: return "Describe your situation"
            case .clarify: return "Let me understand better"
            case .options: return "Your options"
            case .weigh: return "Weigh your evidence"
            case .challenge: return "Challenge check"
            case .analysis: return "Clarity's Analysis"
            }
        }
    }

    private enum ImportTarget {
        case context
        case vendor(String)
    }

    private enum LinkTarget {
        case context
        case vendor(String)
    }

    @EnvironmentObject private var vm: AppViewModel

    @StateObject private var transcriber = SpeechTranscriber()
    @State private var step: Step = .describe
    @State private var importTarget: ImportTarget?
    @State private var linkTarget: LinkTarget?
    @State private var showFileImporter = false
    @State private var showLinkSheet = false
    @State private var linkInput = ""
    @State private var linkPreviewTitle = ""
    @State private var linkPreviewHost = ""
    @State private var linkPreviewTrust: AttachmentTrustLevel = .unknown
    @State private var linkValidationMessage = ""
    @State private var isValidatingLink = false
    @State private var fallbackOptionAnswer = ""
    @State private var challengeIndex = 0
    @State private var showTradeoffs = false
    @State private var showBlindSpots = true
    @State private var showGutCheck = false

    private var isExpressMode: Bool {
        vm.expressModeEnabled && vm.expressModeAvailable
    }

    private var totalSteps: Int {
        isExpressMode ? 3 : 7
    }

    private var visibleStepNumber: Int {
        if isExpressMode {
            switch step {
            case .describe: return 1
            case .analysis: return 2
            default: return 2
            }
        }
        return step.rawValue + 1
    }

    private var previewResult: RankingResult {
        vm.activeResult ?? RankingEngine.computeResult(for: vm.activeDraft)
    }

    private var progressFraction: Double {
        Double(visibleStepNumber) / Double(totalSteps)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    switch step {
                    case .describe:
                        describeStep
                    case .clarify:
                        clarifyStep
                    case .options:
                        optionsStep
                    case .weigh:
                        weighStep
                    case .challenge:
                        challengeStep
                    case .analysis:
                        analysisStep
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }

            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .image, .text, .item],
            allowsMultipleSelection: true
        ) { result in
            guard let importTarget else { return }
            guard case let .success(urls) = result else { return }
            let attachments = urls.compactMap { persistImportedFile(from: $0) }
            switch importTarget {
            case .context:
                appendAttachments(attachments, to: .context)
            case let .vendor(vendorID):
                appendAttachments(attachments, to: .vendor(vendorID))
            }
        }
        .sheet(isPresented: $showLinkSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Add a source link")
                        .font(ClarityType.cardSerif)
                        .foregroundStyle(ClarityPalette.ink)

                    Text("Paste a URL. ScoreWise will use the source text as evidence when available.")
                        .font(ClarityType.body)
                        .foregroundStyle(ClarityPalette.inkSoft)

                    ClarityTextInput(title: "https://example.com", text: $linkInput)

                    if !linkPreviewTitle.isEmpty || !linkPreviewHost.isEmpty || !linkValidationMessage.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            if !linkPreviewTitle.isEmpty {
                                Text(linkPreviewTitle)
                                    .font(ClarityType.bodyMedium)
                                    .foregroundStyle(ClarityPalette.ink)
                            }
                            if !linkPreviewHost.isEmpty {
                                HStack(spacing: 8) {
                                    statusPill(linkPreviewTrust.displayName, tone: linkPreviewTrust.tint)
                                    Text(linkPreviewHost)
                                        .font(ClarityType.caption)
                                        .foregroundStyle(ClarityPalette.inkSoft)
                                }
                            }
                            if !linkValidationMessage.isEmpty {
                                Text(linkValidationMessage)
                                    .font(ClarityType.caption)
                                    .foregroundStyle(linkValidationMessage.lowercased().contains("saved") ? ClarityPalette.inkSoft : ClarityPalette.accent)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ClarityPalette.surfaceSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    Spacer()

                    Button(isValidatingLink ? "Checking link..." : "Save Link") {
                        Task { await addLinkAttachment() }
                    }
                    .buttonStyle(ClarityPrimaryButtonStyle())
                    .disabled(normalizedLink(from: linkInput) == nil || isValidatingLink)
                    .opacity(normalizedLink(from: linkInput) == nil || isValidatingLink ? 0.45 : 1)
                }
                .padding(24)
                .onChange(of: linkInput) { _, _ in
                    linkPreviewTitle = ""
                    linkPreviewHost = ""
                    linkPreviewTrust = .unknown
                    linkValidationMessage = ""
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            showLinkSheet = false
                            resetLinkComposer()
                        }
                    }
                }
            }
            .presentationDetents([.height(320)])
        }
        .onChange(of: step) { _, newStep in
            if newStep == .clarify {
                vm.prepareClarifyingQuestions()
            }
            if newStep == .challenge, vm.activeDraft.biasChallenges.isEmpty {
                vm.prepareBiasChallenges(preferredOption: previewResult.rankedVendors.first?.vendorName)
            }
            if newStep == .analysis {
                vm.computeResult(navigateToResults: false)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    handleBack()
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(ClarityPalette.ink)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("New Decision")
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(ClarityPalette.ink)

                Spacer()

                Button {
                    vm.screen = .home
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(ClarityPalette.ink)
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text("Step \(visibleStepNumber) of \(totalSteps)")
                    .font(ClarityType.title)
                    .foregroundStyle(ClarityPalette.inkSoft)

                Spacer()

                if step == .challenge && !isExpressMode {
                    Button("Skip") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            step = .analysis
                        }
                    }
                    .buttonStyle(.plain)
                    .font(ClarityType.body)
                    .foregroundStyle(ClarityPalette.inkSoft)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.22))
                    Capsule()
                        .fill(ClarityPalette.accent)
                        .frame(width: proxy.size.width * progressFraction)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var footer: some View {
        HStack {
            Spacer()

            Button(nextButtonTitle) {
                handleNext()
            }
            .buttonStyle(ClarityPrimaryButtonStyle())
            .frame(width: step == .challenge ? 248 : (step == .analysis ? 138 : 100))
            .disabled(!canProceed)
            .opacity(canProceed ? 1 : 0.45)
        }
    }

    private var nextButtonTitle: String {
        if isExpressMode && step == .describe {
            return "Analyze"
        }
        if step == .challenge {
            return challengeIndex < max(vm.activeDraft.biasChallenges.count - 1, 0) ? "Submit & Next Challenge" : "Submit & Continue"
        }
        if step == .analysis {
            return "Final Summary"
        }
        return "Next"
    }

    private func handleBack() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if step == .describe {
                vm.screen = .home
            } else {
                step = Step(rawValue: step.rawValue - 1) ?? .describe
            }
        }
    }

    private var canProceed: Bool {
        switch step {
        case .describe:
            return !vm.activeDraft.contextNarrative.trimmed.isEmpty
        case .clarify:
            if isExpressMode { return true }
            return vm.activeDraft.clarifyingQuestions.count == 3 && vm.activeDraft.clarifyingQuestions.allSatisfy { !$0.answer.trimmed.isEmpty }
        case .options:
            return vm.activeDraft.vendors.count >= 2 && vm.activeDraft.vendors.allSatisfy { !$0.name.trimmed.isEmpty }
        case .weigh:
            return vm.activeDraft.criteria.count >= 3
        case .challenge:
            guard vm.activeDraft.biasChallenges.indices.contains(challengeIndex) else { return false }
            return !vm.activeDraft.biasChallenges[challengeIndex].response.trimmed.isEmpty
        case .analysis:
            return true
        }
    }

    private func handleNext() {
        switch step {
        case .describe where isExpressMode:
            vm.runExpressAnalysis()
            withAnimation(.easeInOut(duration: 0.2)) {
                step = .analysis
            }
        case .clarify:
            vm.suggestOptionsFromClarifyingAnswers()
            withAnimation(.easeInOut(duration: 0.2)) {
                step = .options
            }
        case .weigh:
            vm.prepareBiasChallenges(preferredOption: previewResult.rankedVendors.first?.vendorName)
            withAnimation(.easeInOut(duration: 0.2)) {
                step = .challenge
            }
        case .challenge:
            if challengeIndex < max(vm.activeDraft.biasChallenges.count - 1, 0) {
                challengeIndex += 1
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    step = .analysis
                }
            }
        case .analysis:
            vm.computeResult(navigateToResults: true)
        default:
            withAnimation(.easeInOut(duration: 0.2)) {
                step = Step(rawValue: step.rawValue + 1) ?? .analysis
            }
        }
    }

    private var describeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Describe your\nsituation")
                .font(ClarityType.heroSerif)
                .lineSpacing(-2)
                .foregroundStyle(ClarityPalette.ink)

            Text("What's the decision you're facing? Be as specific as you can.")
                .font(ClarityType.title)
                .foregroundStyle(ClarityPalette.inkSoft)

            ZStack(alignment: .bottomTrailing) {
                TextEditor(text: $vm.activeDraft.contextNarrative)
                    .font(ClarityType.body)
                    .frame(minHeight: 230)
                    .scrollContentBackground(.hidden)
                    .padding(14)
                    .background(ClarityPalette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(ClarityPalette.line, lineWidth: 1)
                    )

                Button {
                    Task {
                        if transcriber.isRecording {
                            transcriber.stop()
                            if !transcriber.transcript.isEmpty {
                                if !vm.activeDraft.contextNarrative.isEmpty {
                                    vm.activeDraft.contextNarrative += " "
                                }
                                vm.activeDraft.contextNarrative += transcriber.transcript
                                transcriber.clearTranscript()
                            }
                        } else {
                            await transcriber.start()
                        }
                    }
                } label: {
                    Image(systemName: transcriber.isRecording ? "stop.fill" : "mic")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.black, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(14)
            }

            HStack {
                Text("\(vm.activeDraft.contextNarrative.count) characters")
                    .font(ClarityType.caption)
                    .foregroundStyle(ClarityPalette.inkSoft)
                Spacer()
                Button {
                    linkTarget = .context
                    showLinkSheet = true
                } label: {
                    Label("Add link", systemImage: "link")
                        .font(ClarityType.caption.weight(.medium))
                        .foregroundStyle(ClarityPalette.inkSoft)
                }
                .buttonStyle(.plain)

                Button {
                    importTarget = .context
                    showFileImporter = true
                } label: {
                    Label("Add file", systemImage: "paperclip")
                        .font(ClarityType.caption.weight(.medium))
                        .foregroundStyle(ClarityPalette.inkSoft)
                }
                .buttonStyle(.plain)
            }

            if !vm.activeDraft.contextAttachments.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(vm.activeDraft.contextAttachments, id: \.id) { attachment in
                        attachmentStatusRow(attachment)
                    }
                }
            }

            Text(vm.activeDraft.usageContext.rawValue.capitalized)
                .font(ClarityType.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(ClarityPalette.surfaceSoft, in: Capsule())
        }
    }

    private var clarifyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Let me understand\nbetter")
                .font(ClarityType.heroSerif)
                .lineSpacing(-2)
                .foregroundStyle(ClarityPalette.ink)

            Text("Answer these to help me see the full picture")
                .font(ClarityType.title)
                .foregroundStyle(ClarityPalette.inkSoft)

            if vm.activeDraft.clarifyingQuestions.isEmpty {
                ProgressView("Generating questions...")
                    .font(ClarityType.body)
                    .foregroundStyle(ClarityPalette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                ForEach(vm.activeDraft.clarifyingQuestions) { item in
                    questionCard(item.question) {
                        ClarityTextInput(
                            title: "Type your answer...",
                            text: Binding(
                                get: {
                                    vm.activeDraft.clarifyingQuestions.first(where: { $0.id == item.id })?.answer ?? ""
                                },
                                set: { vm.updateClarifyingAnswer(questionID: item.id, answer: $0) }
                            )
                        )
                    }
                }
            }
        }
    }

    private var optionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your options")
                .font(ClarityType.heroSerif)
                .foregroundStyle(ClarityPalette.ink)

            Text("Here's what I see on the table. Edit or add more.")
                .font(ClarityType.title)
                .foregroundStyle(ClarityPalette.inkSoft)

            ForEach(vm.activeDraft.vendors.indices, id: \.self) { index in
                let vendor = vm.activeDraft.vendors[index]
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(optionBadge(index))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(ClarityPalette.ink)
                            .frame(width: 32, height: 32)
                            .background(ClarityPalette.surfaceSoft, in: Circle())

                        TextField("Option \(optionBadge(index))", text: Binding(
                            get: { vm.activeDraft.vendors[index].name },
                            set: { vm.activeDraft.vendors[index].name = $0 }
                        ), axis: .vertical)
                        .lineLimit(2 ... 3)
                        .font(ClarityType.body)

                        HStack(spacing: 12) {
                            Image(systemName: "pencil")
                                .foregroundStyle(ClarityPalette.inkSoft)

                            Button {
                                if vm.activeDraft.vendors.count > 2 {
                                    let removedID = vendor.id
                                    vm.activeDraft.vendors.remove(at: index)
                                    vm.activeDraft.scores.removeAll { $0.vendorID == removedID }
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(vm.activeDraft.vendors.count > 2 ? ClarityPalette.inkSoft : Color.gray)
                            }
                            .buttonStyle(.plain)
                            .disabled(vm.activeDraft.vendors.count <= 2)
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            importTarget = .vendor(vendor.id)
                            showFileImporter = true
                        } label: {
                            Label("Add file", systemImage: "paperclip")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ClarityPalette.inkSoft)

                        Button {
                            linkTarget = .vendor(vendor.id)
                            showLinkSheet = true
                        } label: {
                            Label("Add link", systemImage: "link")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ClarityPalette.inkSoft)

                        Spacer()

                        if !vm.activeDraft.vendors[index].attachments.isEmpty {
                            Text("\(vm.activeDraft.vendors[index].attachments.count)")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(ClarityPalette.surfaceSoft, in: Capsule())
                        }
                    }

                    if !vm.activeDraft.vendors[index].attachments.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(vm.activeDraft.vendors[index].attachments, id: \.id) { attachment in
                                attachmentStatusRow(attachment)
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ClarityPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(ClarityPalette.line, lineWidth: 1)
                )
            }

            if vm.activeDraft.vendors.count < 8 {
                Button {
                    vm.activeDraft.vendors.append(VendorDraft(name: "", notes: "", attachments: []))
                } label: {
                    Label("Add another option", systemImage: "plus")
                        .font(ClarityType.titleMedium)
                        .foregroundStyle(ClarityPalette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(ClarityPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(ClarityPalette.line, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            questionCard("If neither of these existed, what would you do?") {
                ClarityTextInput(title: "Type your answer...", text: $fallbackOptionAnswer)
            }
        }
    }

    private var weighStep: some View {
        let totalWeight = vm.activeDraft.criteria.reduce(0) { $0 + $1.weightPercent }
        let balanced = abs(totalWeight - 100) < 0.2

        return VStack(alignment: .leading, spacing: 14) {
            Text("Weigh your evidence")
                .font(ClarityType.heroSerif)
                .foregroundStyle(ClarityPalette.ink)

            Text("Score each option against what matters most")
                .font(ClarityType.title)
                .foregroundStyle(ClarityPalette.inkSoft)

            HStack(spacing: 8) {
                Image(systemName: balanced ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(balanced ? ClarityPalette.green : ClarityPalette.accent)
                Text("Total weight: \(totalWeight, specifier: "%.0f")%")
                    .font(ClarityType.bodyMedium)
                Text(balanced ? "- balanced" : "- needs adjustment")
                    .font(ClarityType.bodyMedium)
                    .foregroundStyle(balanced ? ClarityPalette.green : ClarityPalette.accent)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("CRITERION")
                            .frame(width: 180, alignment: .leading)
                        Text("WEIGHT")
                            .frame(width: 80, alignment: .leading)
                        ForEach(vm.activeDraft.vendors, id: \.id) { vendor in
                            Text(vendor.name.trimmed.isEmpty ? "OPTION" : vendor.name)
                                .frame(width: 92, alignment: .leading)
                                .lineLimit(1)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ClarityPalette.inkSoft)

                    ForEach(vm.activeDraft.criteria.indices, id: \.self) { row in
                        let criterion = vm.activeDraft.criteria[row]
                        HStack(spacing: 8) {
                            TextField("Criterion", text: Binding(
                                get: { vm.activeDraft.criteria[row].name },
                                set: { vm.activeDraft.criteria[row].name = $0 }
                            ))
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .frame(width: 180)
                            .background(ClarityPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ClarityPalette.line, lineWidth: 1))

                            TextField("0", text: weightTextBinding(for: criterion.id))
                                .keyboardType(.decimalPad)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 11)
                                .frame(width: 80)
                                .background(ClarityPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ClarityPalette.line, lineWidth: 1))

                            ForEach(vm.activeDraft.vendors, id: \.id) { vendor in
                                TextField("0", text: scoreTextBinding(vendorID: vendor.id, criterionID: criterion.id))
                                    .keyboardType(.decimalPad)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 11)
                                    .frame(width: 92)
                                    .background(ClarityPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ClarityPalette.line, lineWidth: 1))
                            }
                        }
                    }
                }
            }

            Button {
                vm.activeDraft.criteria.append(
                    CriterionDraft(name: "", detail: "", category: "General", weightPercent: 10)
                )
            } label: {
                Label("Add Criterion", systemImage: "plus")
                    .font(ClarityType.titleMedium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .background(ClarityPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ClarityPalette.line, lineWidth: 1))

            Text("WEIGHTED SCORES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ClarityPalette.inkSoft)

            VStack(spacing: 10) {
                ForEach(previewResult.rankedVendors, id: \.vendorID) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(item.vendorName.trimmed.isEmpty ? "Option" : item.vendorName)
                                .font(ClarityType.body)
                                .foregroundStyle(ClarityPalette.ink)
                            Spacer()
                            Text("\(item.totalScore, specifier: "%.1f")/10")
                                .font(ClarityType.titleMedium)
                            if previewResult.rankedVendors.first?.vendorID == item.vendorID {
                                Text("Leading")
                                    .font(ClarityType.smallCaps)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(ClarityPalette.accent.opacity(0.12), in: Capsule())
                                    .foregroundStyle(ClarityPalette.accent)
                            }
                        }

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.gray.opacity(0.22))
                                Capsule()
                                    .fill(ClarityPalette.accent)
                                    .frame(width: proxy.size.width * max(0, min(1, item.totalScore / 10)))
                            }
                        }
                        .frame(height: 8)
                    }
                    .padding(14)
                    .background(ClarityPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ClarityPalette.line, lineWidth: 1))
                }
            }
        }
    }

    private var challengeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            if vm.activeDraft.biasChallenges.isEmpty {
                ProgressView("Generating challenge prompts...")
                    .font(ClarityType.body)
                    .foregroundStyle(ClarityPalette.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 320, alignment: .center)
            } else {
                TabView(selection: $challengeIndex) {
                    ForEach(Array(vm.activeDraft.biasChallenges.enumerated()), id: \.element.id) { index, card in
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(ClarityPalette.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(ClarityPalette.line, lineWidth: 1)
                            )
                            .overlay {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack(spacing: 10) {
                                        Image(systemName: challengeIcon(for: card.type))
                                            .foregroundStyle(ClarityPalette.inkSoft)
                                            .frame(width: 34, height: 34)
                                            .background(ClarityPalette.surfaceSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        Text(challengeLabel(for: card.type))
                                            .font(.system(size: 11, weight: .semibold, design: .serif))
                                            .foregroundStyle(ClarityPalette.inkSoft)
                                    }

                                    Text(card.question)
                                        .font(ClarityType.sectionSerif)
                                        .foregroundStyle(ClarityPalette.ink)

                                    TextEditor(text: Binding(
                                        get: {
                                            vm.activeDraft.biasChallenges.first(where: { $0.id == card.id })?.response ?? ""
                                        },
                                        set: { vm.updateBiasChallengeResponse(challengeID: card.id, response: $0) }
                                    ))
                                    .font(ClarityType.body)
                                    .frame(height: 110)
                                    .padding(12)
                                    .scrollContentBackground(.hidden)
                                    .background(ClarityPalette.surfaceSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .padding(16)
                            }
                            .padding(.horizontal, 2)
                            .tag(index)
                    }
                }
                .frame(height: 355)
                .tabViewStyle(.page(indexDisplayMode: .always))
            }
        }
    }

    private var analysisStep: some View {
        let winner = previewResult.rankedVendors.first
        let confidenceText: String = previewResult.confidenceScore >= 0.75 ? "HIGH CONFIDENCE" : "MEDIUM CONFIDENCE"
        let recommendation = vm.activeInsight?.winnerReasoning
            ?? (winner?.vendorName.trimmed.isEmpty == false ? winner?.vendorName ?? "Option A" : "Option A")

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 16) {
                Text("RECOMMENDATION")
                    .font(ClarityType.smallCaps)
                    .foregroundStyle(ClarityPalette.inkSoft)

                Text(recommendation)
                    .font(ClarityType.sectionSerif)
                    .foregroundStyle(ClarityPalette.ink)

                Text(confidenceText)
                    .font(ClarityType.smallCaps)
                    .foregroundStyle(ClarityPalette.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(ClarityPalette.green.opacity(0.12), in: Capsule())

                Divider()

                analysisRow(
                    title: "KEY TRADE-OFFS",
                    expanded: $showTradeoffs,
                    lines: insightLines(from: vm.activeInsight?.summary, fallback: [
                        "Higher scoring options may trade off flexibility.",
                        "Lower-risk options can limit upside growth."
                    ])
                )

                analysisRow(
                    title: "BLIND SPOTS TO WATCH",
                    expanded: $showBlindSpots,
                    lines: vm.activeInsight?.riskFlags ?? ["Weight choices may over-index recent events."]
                )

                analysisRow(
                    title: "GUT CHECK",
                    expanded: $showGutCheck,
                    lines: insightLines(from: vm.activeInsight?.sensitivityFindings.first, fallback: [
                        "If this result feels wrong instantly, revisit the highest-weight criterion."
                    ])
                )

                Text("YOUR NEXT STEP")
                    .font(ClarityType.smallCaps)
                    .foregroundStyle(ClarityPalette.inkSoft)

                Text(vm.activeInsight?.overlookedStrategicPoints.first ?? "Schedule a concrete action within 48 hours to validate this recommendation.")
                    .font(ClarityType.body)
                    .foregroundStyle(ClarityPalette.ink)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ClarityPalette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(ClarityPalette.accent.opacity(0.35), lineWidth: 1)
                    )
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ClarityPalette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(ClarityPalette.line, lineWidth: 1)
            )
        }
    }

    private func analysisRow(title: String, expanded: Binding<Bool>, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expanded.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(ClarityType.smallCaps)
                        .foregroundStyle(ClarityPalette.inkSoft)
                    Spacer()
                    Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .foregroundStyle(ClarityPalette.inkSoft)
                }
            }
            .buttonStyle(.plain)

            if expanded.wrappedValue {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(lines, id: \.self) { line in
                        Text("• \(line)")
                            .font(ClarityType.body)
                            .foregroundStyle(ClarityPalette.inkSoft)
                    }
                }
            }
        }
    }

    private func insightLines(from text: String?, fallback: [String]) -> [String] {
        let lines = text?
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "• ", with: "").replacingOccurrences(of: "- ", with: "") }
            .filter { !$0.isEmpty } ?? []
        return lines.isEmpty ? fallback : lines
    }

    private func challengeLabel(for type: BiasChallengeType) -> String {
        switch type {
        case .friendTest:
            return "THE FRIEND TEST"
        case .tenTenTen:
            return "THE 10-10-10 RULE"
        case .preMortem:
            return "THE PRE-MORTEM"
        case .worstCase:
            return "THE WORST CASE"
        case .inversion:
            return "THE INVERSION"
        case .inactionCost:
            return "THE INACTION COST"
        case .valuesCheck:
            return "THE VALUES CHECK"
        }
    }

    private func challengeIcon(for type: BiasChallengeType) -> String {
        switch type {
        case .friendTest:
            return "person.2"
        case .tenTenTen:
            return "clock"
        case .preMortem:
            return "exclamationmark.triangle"
        case .worstCase:
            return "bolt.shield"
        case .inversion:
            return "arrow.uturn.backward"
        case .inactionCost:
            return "pause.circle"
        case .valuesCheck:
            return "heart.text.square"
        }
    }

    private func normalizedLink(from raw: String) -> URL? {
        let trimmed = raw.trimmed
        guard !trimmed.isEmpty else { return nil }
        if let direct = URL(string: trimmed), let scheme = direct.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return direct
        }
        return URL(string: "https://\(trimmed)")
    }

    private func addLinkAttachment() async {
        guard let target = linkTarget, let url = normalizedLink(from: linkInput) else { return }
        guard !attachmentExists(for: url, target: target) else {
            linkValidationMessage = "This link is already attached."
            return
        }
        isValidatingLink = true
        defer { isValidatingLink = false }

        var attachment = VendorAttachment(
            fileName: url.host ?? url.absoluteString,
            contentType: "public.url",
            cloudPath: url.absoluteString,
            kind: .link,
            status: .pending,
            trustLevel: .unknown,
            sourceHost: url.host ?? ""
        )

        do {
            if let evidence = try await vm.services.extractor.extractEvidence(for: [attachment]).first {
                attachment = attachment.applyingPreview(evidence)
                linkPreviewTitle = evidence.titleHint
                linkPreviewHost = evidence.sourceHost
                linkPreviewTrust = evidence.trustLevel
                linkValidationMessage = evidence.validationMessage

                if evidence.status == .unreadable {
                    return
                }
            }
        } catch {
            linkValidationMessage = "This link could not be validated right now."
            return
        }

        appendAttachments([attachment], to: target)
        resetLinkComposer()
        showLinkSheet = false
    }

    private func persistImportedFile(from sourceURL: URL) -> VendorAttachment? {
        let secured = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if secured {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ImportedSources", isDirectory: true)

        guard let baseDirectory else { return nil }
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        let destinationURL = baseDirectory.appendingPathComponent("\(UUID().uuidString)-\(sourceURL.lastPathComponent)")
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return VendorAttachment(
                fileName: sourceURL.lastPathComponent,
                contentType: UTType(filenameExtension: sourceURL.pathExtension)?.identifier ?? "application/octet-stream",
                cloudPath: destinationURL.path,
                kind: .file,
                status: .pending,
                trustLevel: .uploaded,
                titleHint: sourceURL.lastPathComponent,
                validationMessage: "Attached file ready for analysis."
            )
        } catch {
            vm.lastError = "Failed to import \(sourceURL.lastPathComponent)."
            return nil
        }
    }

    private func appendAttachments(_ attachments: [VendorAttachment], to target: LinkTarget) {
        let deduped = attachments.filter { attachment in
            !existingAttachments(for: target).contains(where: { $0.cloudPath.caseInsensitiveCompare(attachment.cloudPath) == .orderedSame })
        }
        guard !deduped.isEmpty else { return }

        switch target {
        case .context:
            vm.activeDraft.contextAttachments.append(contentsOf: deduped)
        case let .vendor(vendorID):
            guard let index = vm.activeDraft.vendors.firstIndex(where: { $0.id == vendorID }) else { return }
            vm.activeDraft.vendors[index].attachments.append(contentsOf: deduped)
        }
        vm.activeDraft.lastUpdatedAt = .now
    }

    private func existingAttachments(for target: LinkTarget) -> [VendorAttachment] {
        switch target {
        case .context:
            return vm.activeDraft.contextAttachments
        case let .vendor(vendorID):
            return vm.activeDraft.vendors.first(where: { $0.id == vendorID })?.attachments ?? []
        }
    }

    private func attachmentExists(for url: URL, target: LinkTarget) -> Bool {
        existingAttachments(for: target).contains { $0.cloudPath.caseInsensitiveCompare(url.absoluteString) == .orderedSame }
    }

    private func resetLinkComposer() {
        linkInput = ""
        linkPreviewTitle = ""
        linkPreviewHost = ""
        linkPreviewTrust = .unknown
        linkValidationMessage = ""
        linkTarget = nil
    }

    private func attachmentStatusRow(_ attachment: VendorAttachment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(attachment.titleHint.nonEmpty ?? attachment.fileName)
                .font(ClarityType.caption.weight(.medium))
                .foregroundStyle(ClarityPalette.ink)
                .lineLimit(1)

            HStack(spacing: 8) {
                statusPill(attachment.kind == .link ? "Link" : "File", tone: .neutral)
                statusPill(attachment.trustLevel.displayName, tone: attachment.trustLevel.tint)
                statusPill(attachment.status.displayName, tone: attachment.status.tint)
            }

            if attachment.sourceHost.nonEmpty != nil || attachment.validationMessage.nonEmpty != nil {
                Text([attachment.sourceHost.nonEmpty, attachment.validationMessage.nonEmpty].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(ClarityPalette.inkSoft)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ClarityPalette.surfaceSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statusPill(_ text: String, tone: StatusTone) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tone.background, in: Capsule())
    }

    private func optionBadge(_ index: Int) -> String {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        if letters.indices.contains(index) {
            return String(letters[index])
        }
        return "?"
    }

    private func questionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(ClarityPalette.ink)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ClarityPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ClarityPalette.line, lineWidth: 1)
        )
    }

    private func weightTextBinding(for criterionID: String) -> Binding<String> {
        Binding(
            get: {
                guard let criterion = vm.activeDraft.criteria.first(where: { $0.id == criterionID }) else {
                    return "0"
                }
                return String(format: "%.0f", criterion.weightPercent)
            },
            set: { newValue in
                guard let index = vm.activeDraft.criteria.firstIndex(where: { $0.id == criterionID }) else { return }
                let numeric = Double(newValue.filter { "0123456789.".contains($0) }) ?? 0
                vm.activeDraft.criteria[index].weightPercent = numeric
            }
        )
    }

    private func scoreTextBinding(vendorID: String, criterionID: String) -> Binding<String> {
        Binding(
            get: {
                let score = vm.activeDraft.scores.first { $0.vendorID == vendorID && $0.criterionID == criterionID }?.score ?? 0
                return score == 0 ? "" : String(format: "%.1f", score)
            },
            set: { newValue in
                let numeric = min(max(Double(newValue.filter { "0123456789.".contains($0) }) ?? 0, 0), 10)
                if let idx = vm.activeDraft.scores.firstIndex(where: { $0.vendorID == vendorID && $0.criterionID == criterionID }) {
                    vm.activeDraft.scores[idx].score = numeric
                    vm.activeDraft.scores[idx].source = .manual
                } else {
                    vm.activeDraft.scores.append(
                        ScoreDraft(vendorID: vendorID, criterionID: criterionID, score: numeric, source: .manual, confidence: 1, evidenceSnippet: "Manual")
                    )
                }
            }
        )
    }
}

private struct ResultsView: View {
    @EnvironmentObject private var vm: AppViewModel
    @Environment(\.modelContext) private var modelContext

    @State private var exportedURL: URL?

    private var result: RankingResult? {
        vm.activeResult
    }

    private var winner: VendorResult? {
        result?.rankedVendors.first
    }

    private var fallbackBullets: [String] {
        [
            "Strength aligns with your top weighted criteria",
            "Risk profile is acceptable under your constraints"
        ]
    }

    private var insightBullets: [String] {
        let source = vm.activeInsight?.summary
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "• ", with: "").replacingOccurrences(of: "- ", with: "") }
            .filter { !$0.isEmpty } ?? fallbackBullets
        return Array(source.prefix(3))
    }

    private var resultsStepLabel: String {
        vm.expressModeEnabled && vm.expressModeAvailable ? "Step 3 of 3" : "Step 7 of 7"
    }

    private var decisionSelected: Bool {
        vm.activeDraft.decisionStatus == .decided
    }

    private var reminderEnabled: Binding<Bool> {
        Binding(
            get: { vm.activeDraft.followUpDate != nil },
            set: { vm.setFollowUpReminder(enabled: $0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if let result, let winner {
                        summaryCard(result: result, winner: winner)

                        Button {
                            Task {
                                exportedURL = await vm.exportPDF()
                            }
                        } label: {
                            Label("Share as image", systemImage: "square.and.arrow.up")
                                .font(ClarityType.titleMedium)
                                .foregroundStyle(ClarityPalette.ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(ClarityPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(ClarityPalette.line, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)

                        Button("Return to home") {
                            vm.saveCurrentProject(modelContext: modelContext)
                            vm.screen = .home
                        }
                        .buttonStyle(.plain)
                        .font(ClarityType.body)
                        .foregroundStyle(ClarityPalette.inkSoft)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    vm.screen = .ranking
                } label: {
                    Image(systemName: "arrow.left")
                        .foregroundStyle(ClarityPalette.ink)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Decision Summary")
                    .font(.system(size: 24, weight: .semibold, design: .serif))

                Spacer()

                Button {
                    vm.screen = .home
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(ClarityPalette.ink)
                }
                .buttonStyle(.plain)
            }

            Text(resultsStepLabel)
                .font(ClarityType.title)
                .foregroundStyle(ClarityPalette.inkSoft)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.2))
                    Capsule().fill(ClarityPalette.accent).frame(width: proxy.size.width)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private func summaryCard(result: RankingResult, winner: VendorResult) -> some View {
        let confidenceHigh = result.confidenceScore > 0.7
        let title = vm.activeDraft.title.trimmed.isEmpty ? "Decision Summary" : vm.activeDraft.title
        let recommendation = vm.activeInsight?.winnerReasoning ?? winner.vendorName

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(vm.activeDraft.usageContext.rawValue.capitalized)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(ClarityPalette.surfaceSoft, in: Capsule())
                Spacer()
                Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(ClarityPalette.inkSoft)
            }

            Text(title)
                .font(ClarityType.cardSerif)
                .foregroundStyle(ClarityPalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            (Text("AI Recommendation: ").font(ClarityType.bodyMedium)
                + Text(recommendation).font(ClarityType.body))
                .foregroundStyle(ClarityPalette.ink)

            HStack(spacing: 8) {
                Text("Confidence:")
                    .font(ClarityType.body)
                    .foregroundStyle(ClarityPalette.inkSoft)
                Circle()
                    .fill(confidenceHigh ? ClarityPalette.green : ClarityPalette.accent)
                    .frame(width: 8, height: 8)
                Text(confidenceHigh ? "High" : "Medium")
                    .font(ClarityType.bodyMedium)
                    .foregroundStyle(confidenceHigh ? ClarityPalette.green : ClarityPalette.accent)
            }

            VStack(alignment: .leading, spacing: 10) {
                let scoreText = String(format: "%.1f", winner.totalScore)
                bullet("Your weighted analysis scored this option \(scoreText)/10, highest among all options")
                ForEach(insightBullets, id: \.self) { point in
                    bullet(point)
                }
            }

            Divider()

            Text("Your decision:")
                .font(ClarityType.bodyMedium)
                .foregroundStyle(ClarityPalette.ink)

            HStack(spacing: 10) {
                Button("I've decided ✓") {
                    vm.setDecisionOutcome(decided: true)
                }
                .buttonStyle(decisionChoiceStyle(selected: decisionSelected))

                Button("Still thinking 🤔") {
                    vm.setDecisionOutcome(decided: false)
                }
                .buttonStyle(decisionChoiceStyle(selected: !decisionSelected))
            }

            HStack {
                Text("Remind me to review in 30 days")
                    .font(ClarityType.body)
                    .foregroundStyle(ClarityPalette.inkSoft)
                Spacer()
                Toggle("", isOn: reminderEnabled)
                    .labelsHidden()
                    .tint(ClarityPalette.accent)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ClarityPalette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(ClarityPalette.line, lineWidth: 1)
        )
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .foregroundStyle(ClarityPalette.accent)
                .font(.subheadline.weight(.bold))
                .padding(.top, 5)
            Text(text)
                .font(ClarityType.body)
                .foregroundStyle(ClarityPalette.inkSoft)
        }
    }

    private func decisionChoiceStyle(selected: Bool) -> ClarityChoiceButtonStyle {
        ClarityChoiceButtonStyle(selected: selected)
    }
}

private struct HistoryView: View {
    @EnvironmentObject private var vm: AppViewModel
    @State private var selectedFilter = "All"

    private let filters = ["All", "Work", "Personal", "Decided"]

    private var items: [HistoryRow] {
        let rows: [HistoryRow]
        if vm.recentProjects.isEmpty {
            rows = [
                HistoryRow(id: "sample-career", title: "Should I stay at my current job or accept the offer?", context: "Career", date: Date.now.addingTimeInterval(-86400), confidence: "High confidence", status: "Decided ✓"),
                HistoryRow(id: "sample-personal", title: "Should I move to a new city for better opportunities?", context: "Personal", date: Date.now.addingTimeInterval(-86400 * 7), confidence: "Medium confidence", status: "Still thinking")
            ]
        } else {
            rows = vm.recentProjects.map {
                HistoryRow(
                    id: $0.id,
                    title: $0.title,
                    context: $0.usageContextRaw.capitalized,
                    date: $0.updatedAt,
                    confidence: $0.confidenceScore >= 0.75 ? "High confidence" : "Medium confidence",
                    status: $0.confidenceScore >= 0.75 ? "Decided ✓" : "Still thinking"
                )
            }
        }

        switch selectedFilter {
        case "Work":
            return rows.filter { $0.context == "Work" || $0.context == "Career" }
        case "Personal":
            return rows.filter { $0.context == "Personal" || $0.context == "Relationships" }
        case "Decided":
            return rows.filter { $0.status.contains("Decided") }
        default:
            return rows
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your Decisions")
                    .font(ClarityType.heroSerif)
                    .foregroundStyle(ClarityPalette.ink)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters, id: \.self) { filter in
                            Button(filter) {
                                selectedFilter = filter
                            }
                            .buttonStyle(.plain)
                            .font(ClarityType.bodyMedium)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(selectedFilter == filter ? Color.black : ClarityPalette.surfaceSoft, in: Capsule())
                            .foregroundStyle(selectedFilter == filter ? Color.white : ClarityPalette.ink)
                            .overlay(
                                Capsule().stroke(selectedFilter == filter ? Color.clear : ClarityPalette.line, lineWidth: 1)
                            )
                        }
                    }
                }

                VStack(spacing: 12) {
                    ForEach(items, id: \.id) { item in
                        Button {
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(item.context)
                                        .font(ClarityType.caption.weight(.medium))
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 6)
                                        .background(ClarityPalette.surfaceSoft, in: Capsule())
                                    Spacer()
                                    Text(item.status)
                                        .font(ClarityType.caption.weight(.medium))
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 6)
                                        .background(item.status.contains("Decided") ? ClarityPalette.green.opacity(0.12) : ClarityPalette.surfaceSoft, in: Capsule())
                                        .foregroundStyle(item.status.contains("Decided") ? ClarityPalette.green : ClarityPalette.inkSoft)
                                }

                                Text(item.title)
                                    .font(.system(size: 18, weight: .bold, design: .serif))
                                    .foregroundStyle(ClarityPalette.ink)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(item.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(ClarityType.body)
                                    .foregroundStyle(ClarityPalette.inkSoft)

                                Text(item.confidence)
                                    .font(ClarityType.body)
                                    .foregroundStyle(ClarityPalette.inkSoft)
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ClarityPalette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(ClarityPalette.line, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
    }

    private struct HistoryRow: Identifiable {
        let id: String
        let title: String
        let context: String
        let date: Date
        let confidence: String
        let status: String
    }
}

private struct ProfileView: View {
    @EnvironmentObject private var vm: AppViewModel

    private var completedCount: Int {
        vm.recentProjects.filter { $0.confidenceScore >= 0.75 }.count
    }

    private var confidencePercent: Int {
        guard !vm.recentProjects.isEmpty else { return 94 }
        let avg = vm.recentProjects.map(\.confidenceScore).reduce(0, +) / Double(vm.recentProjects.count)
        return Int((avg * 100).rounded())
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Profile")
                    .font(ClarityType.heroSerif)
                    .foregroundStyle(ClarityPalette.ink)

                VStack(spacing: 14) {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 84, height: 84)
                        .overlay(
                            Text(initials(vm.session?.displayName ?? "Julian Mercer"))
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                        )

                    Text(vm.session?.displayName ?? "Julian Mercer")
                        .font(ClarityType.cardSerif)
                        .foregroundStyle(ClarityPalette.ink)

                    Text(vm.session?.email ?? "julian.mercer@email.com")
                        .font(ClarityType.body)
                        .foregroundStyle(ClarityPalette.inkSoft)

                    Text("Member since Jan 2026")
                        .font(ClarityType.body)
                        .foregroundStyle(ClarityPalette.inkSoft)

                    Divider()

                    HStack {
                        stat("\(max(12, vm.recentProjects.count))", label: "Decisions")
                        Spacer()
                        stat("\(max(8, completedCount))", label: "Completed")
                        Spacer()
                        stat("\(max(94, confidencePercent))%", label: "Confidence")
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .background(ClarityPalette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(ClarityPalette.line, lineWidth: 1)
                )

                sectionHeader("PREFERENCES")
                settingsGroup {
                    settingRow(icon: "bell", title: "Notifications", value: "Enabled", divider: true)
                    settingRow(icon: "sparkles", title: "Decision style", value: "Analytical", divider: false)
                }

                sectionHeader("ACCOUNT")
                settingsGroup {
                    settingRow(icon: "shield", title: "Privacy & Security", value: "", divider: true)
                    settingRow(icon: "questionmark.circle", title: "Help & Support", value: "", divider: false)
                }

                Button {
                    vm.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(ClarityType.titleMedium)
                        .foregroundStyle(ClarityPalette.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(ClarityPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(ClarityPalette.line, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Text("Clarity v1.0.0")
                    .font(ClarityType.caption)
                    .foregroundStyle(ClarityPalette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
    }

    private func stat(_ value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundStyle(ClarityPalette.ink)
            Text(label)
                .font(ClarityType.caption)
                .foregroundStyle(ClarityPalette.inkSoft)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .kerning(0.8)
            .foregroundStyle(ClarityPalette.inkSoft)
            .padding(.leading, 4)
    }

    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(ClarityPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(ClarityPalette.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    private func settingRow(icon: String, title: String, value: String, divider: Bool) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(ClarityPalette.inkSoft)
                .frame(width: 22)
            Text(title)
                .font(ClarityType.body)
                .foregroundStyle(ClarityPalette.ink)
            Spacer()
            if !value.isEmpty {
                Text(value)
                    .font(ClarityType.body)
                    .foregroundStyle(ClarityPalette.inkSoft)
            }
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ClarityPalette.inkSoft)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if divider {
                Divider()
                    .padding(.leading, 54)
            }
        }
    }

    private func initials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        let value = String(letters)
        return value.isEmpty ? "JM" : value.uppercased()
    }
}

private struct ChatAssistantSheet: View {
    @EnvironmentObject private var vm: AppViewModel
    let phase: String

    @State private var prompt = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(vm.chatMessages) { message in
                            HStack {
                                if message.role == "assistant" {
                                    Text(message.content)
                                        .font(.body)
                                        .padding(12)
                                        .background(ClarityPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(ClarityPalette.line, lineWidth: 1)
                                        )
                                    Spacer(minLength: 48)
                                } else {
                                    Spacer(minLength: 48)
                                    Text(message.content)
                                        .font(.body)
                                        .padding(12)
                                        .background(Color.black.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                HStack(spacing: 10) {
                    TextField("Ask for evidence-based guidance...", text: $prompt, axis: .vertical)
                        .lineLimit(1 ... 3)
                        .font(.body)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(ClarityPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(ClarityPalette.line, lineWidth: 1)
                        )

                    Button("Send") {
                        let text = prompt
                        prompt = ""
                        vm.askChat(text, phase: phase)
                    }
                    .buttonStyle(ClarityPrimaryButtonStyle())
                    .frame(width: 84)
                    .disabled(prompt.trimmed.isEmpty)
                    .opacity(prompt.trimmed.isEmpty ? 0.45 : 1)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .navigationTitle("Decision Assistant")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ClarityLogoMark: View {
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let cell = size / 3.4
            let startX = (geo.size.width - (cell * 3)) / 2
            let startY = (geo.size.height - (cell * 3)) / 2

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: startX + cell, y: startY))
                    path.addLine(to: CGPoint(x: startX + cell, y: startY + cell * 3))
                    path.move(to: CGPoint(x: startX + cell * 2, y: startY))
                    path.addLine(to: CGPoint(x: startX + cell * 2, y: startY + cell * 3))

                    path.move(to: CGPoint(x: startX, y: startY + cell))
                    path.addLine(to: CGPoint(x: startX + cell * 3, y: startY + cell))
                    path.move(to: CGPoint(x: startX, y: startY + cell * 2))
                    path.addLine(to: CGPoint(x: startX + cell * 3, y: startY + cell * 2))
                }
                .stroke(Color.black.opacity(0.78), lineWidth: 2)

                Group {
                    Circle().stroke(Color.black.opacity(0.78), lineWidth: 2)
                        .frame(width: cell * 0.62, height: cell * 0.62)
                        .position(x: startX + cell * 0.5, y: startY + cell * 1.5)
                    Circle().stroke(Color.black.opacity(0.78), lineWidth: 2)
                        .frame(width: cell * 0.62, height: cell * 0.62)
                        .position(x: startX + cell * 0.5, y: startY + cell * 2.5)
                    Circle().stroke(Color.black.opacity(0.78), lineWidth: 2)
                        .frame(width: cell * 0.62, height: cell * 0.62)
                        .position(x: startX + cell * 2.5, y: startY + cell * 0.5)
                    Circle().stroke(Color.black.opacity(0.78), lineWidth: 2)
                        .frame(width: cell * 0.62, height: cell * 0.62)
                        .position(x: startX + cell * 2.5, y: startY + cell * 1.5)
                }

                Group {
                    crossMark(at: CGPoint(x: startX + cell * 0.5, y: startY + cell * 0.5), size: cell * 0.48)
                    crossMark(at: CGPoint(x: startX + cell * 1.5, y: startY + cell * 0.5), size: cell * 0.48)
                    crossMark(at: CGPoint(x: startX + cell * 1.5, y: startY + cell * 1.5), size: cell * 0.48)
                    crossMark(at: CGPoint(x: startX + cell * 1.5, y: startY + cell * 2.5), size: cell * 0.48)
                    crossMark(at: CGPoint(x: startX + cell * 2.5, y: startY + cell * 2.5), size: cell * 0.48)
                }

                Rectangle()
                    .fill(ClarityPalette.accent)
                    .frame(width: 2, height: cell * 2.8)
                    .position(x: startX + cell * 1.5, y: startY + cell * 1.4)
            }
        }
    }

    private func crossMark(at center: CGPoint, size: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.78))
                .frame(width: 2, height: size)
                .rotationEffect(.degrees(45))
            Rectangle()
                .fill(Color.black.opacity(0.78))
                .frame(width: 2, height: size)
                .rotationEffect(.degrees(-45))
        }
        .position(center)
    }
}

private struct ClarityPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ClarityType.titleMedium)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.black.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct ClarityOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.medium))
            .foregroundStyle(ClarityPalette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(ClarityPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(ClarityPalette.line, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct ClarityChoiceButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ClarityType.bodyMedium)
            .foregroundStyle(selected ? Color.white : ClarityPalette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(selected ? Color.black : ClarityPalette.surfaceSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(ClarityPalette.line, lineWidth: selected ? 0 : 1)
            )
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}

private struct ClarityTextInput: View {
    let title: String
    @Binding var text: String

    var body: some View {
        TextField(title, text: $text, axis: .vertical)
            .lineLimit(2 ... 4)
            .font(ClarityType.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(ClarityPalette.surfaceSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(ClarityPalette.line, lineWidth: 1)
            )
    }
}

private struct NotificationBellIcon: View {
    var body: some View {
        Circle()
            .fill(ClarityPalette.surface)
            .frame(width: 38, height: 38)
            .overlay(Circle().stroke(ClarityPalette.line, lineWidth: 1))
            .overlay {
                Image(systemName: "bell")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(ClarityPalette.ink)
            }
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(ClarityPalette.accent)
                    .frame(width: 9, height: 9)
                    .offset(x: 4, y: -2)
            }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += rowHeight + rowSpacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }

        return CGSize(width: maxWidth, height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + rowSpacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct FlexibleChipLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let items: Data
    let spacing: CGFloat
    let content: (Data.Element) -> Content

    init(items: Data, spacing: CGFloat = 8, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.items = items
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            let rows = makeRows()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.self) { element in
                        content(element)
                    }
                }
            }
        }
    }

    private func makeRows() -> [[Data.Element]] {
        // Keep chips readable in compact iPhone widths by capping count per row.
        let maxPerRow = 2
        var rows: [[Data.Element]] = [[]]

        for element in items {
            if rows[rows.count - 1].count >= maxPerRow {
                rows.append([element])
            } else {
                rows[rows.count - 1].append(element)
            }
        }

        return rows
    }
}

@MainActor
final class SpeechTranscriber: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording = false

    private let speechRecognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func start() async {
        guard await requestPermissions() else { return }
        stop()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            try audioEngine.start()
            isRecording = true
        } catch {
            stop()
            return
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.transcript = result.bestTranscription.formattedString
            }
            if error != nil || (result?.isFinal == true) {
                self.stop()
            }
        }
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
    }

    func clearTranscript() {
        transcript = ""
    }

    private func requestPermissions() async -> Bool {
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        let micAuthorized = await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
        }

        return speechAuthorized && micAuthorized
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nonEmpty: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }
}

private struct StatusTone {
    var foreground: Color
    var background: Color

    static let neutral = StatusTone(foreground: ClarityPalette.inkSoft, background: ClarityPalette.surface)
    static let green = StatusTone(foreground: ClarityPalette.green, background: ClarityPalette.green.opacity(0.12))
    static let orange = StatusTone(foreground: ClarityPalette.accent, background: ClarityPalette.accent.opacity(0.12))
    static let gray = StatusTone(foreground: ClarityPalette.inkSoft, background: ClarityPalette.surface)
}

private extension AttachmentTrustLevel {
    var displayName: String {
        switch self {
        case .uploaded:
            return "Uploaded"
        case .official:
            return "Official"
        case .known:
            return "Known"
        case .external:
            return "External"
        case .unknown:
            return "Unknown"
        }
    }

    var tint: StatusTone {
        switch self {
        case .uploaded:
            return .neutral
        case .official:
            return .green
        case .known:
            return .neutral
        case .external:
            return .orange
        case .unknown:
            return .gray
        }
    }
}

private extension AttachmentValidationStatus {
    var displayName: String {
        switch self {
        case .pending:
            return "Pending"
        case .ready:
            return "Readable"
        case .needsReview:
            return "Review"
        case .unreadable:
            return "Unreadable"
        }
    }

    var tint: StatusTone {
        switch self {
        case .pending:
            return .neutral
        case .ready:
            return .green
        case .needsReview:
            return .orange
        case .unreadable:
            return .gray
        }
    }
}

private extension VendorAttachment {
    func applyingPreview(_ evidence: ExtractedAttachmentEvidence) -> VendorAttachment {
        var copy = self
        copy.status = evidence.status
        copy.trustLevel = evidence.trustLevel
        copy.sourceHost = evidence.sourceHost
        copy.titleHint = evidence.titleHint
        copy.validationMessage = evidence.validationMessage
        return copy
    }
}
