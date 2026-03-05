# ScoreWise (Xcode Project)

ScoreWise is an iOS app for high-confidence vendor decisions using weighted scoring and AI guidance.

## Tech Stack
- SwiftUI + MVVM
- SwiftData (local cache/offline drafts)
- Firebase-ready service layer (Auth, Firestore, Storage, Functions)
- Cloud Functions templates for Gemini integration

## Implemented
- Auth screen (Apple/Google/Email UX scaffolding)
- Onboarding survey (8 questions) + decision-style tagging
- Ranking wizard:
  - Context brief first (typed or microphone-transcribed)
  - Optional context files before vendor setup
  - Vendors (2-8)
  - Criteria and weights (3-20) with normalization
  - Score matrix (1-10)
  - Review and run ranking
- Persistent bottom navigation (Home / Compare / Profile)
- Premium visual system with animated transitions and glass-style surfaces
- Ranking engine:
  - Weighted sum scoring
  - Tie detection (< 0.05)
  - Sensitivity checks (top 3 criteria, +10%)
- AI hooks:
  - criteria/weights/draft score suggestions
  - decision chat
  - result insight generation
- Result insights UI with risk flags and overlooked strategic points
- PDF export and share
- SwiftData entities for profile, projects, scores, insights, chat, versions
- Cloud Functions stubs for `suggestRankingInputs`, `decisionChat`, `generateInsights`, `extractVendorFiles`, `exportProjectPDF`
- Unit tests for ranking engine and survey tagging

## Open in Xcode
Open: `ScoreWise/ScoreWise.xcodeproj`

## Firebase Setup
1. Add Firebase iOS SDK packages in Xcode project settings (Auth/Firestore/Functions/Storage).
2. Add `GoogleService-Info.plist` to app target.
3. Enable providers: Apple, Google, Email.
4. Deploy `CloudFunctions/` and set `GEMINI_API_KEY`.
