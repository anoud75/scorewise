# Tasks: Clarity AI Chat-First Decision Coach

**Input**: Approved implementation plan for the Clarity AI chat-first decision coach flow
**Prerequisites**: Existing iOS app in `ScoreWise/ScoreWiseApp/`, Cloud Functions in `ScoreWise/CloudFunctions/`

**Tests**: Include targeted unit and UI-adjacent flow tests because the plan explicitly requires acceptance coverage for chat flow, matrix setup, resume behavior, and fallback visibility.

**Organization**: Tasks are grouped by user story so each story can be implemented and validated independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this belongs to (`[US1]`, `[US2]`, `[US3]`)

## Path Conventions

- iOS app code: `ScoreWise/ScoreWiseApp/`
- Cloud Functions backend: `ScoreWise/CloudFunctions/`
- Existing test target: `ScoreWise/ScoreWiseTests/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare the repository for a chat-first flow and prompt-driven backend without touching behavior yet.

- [ ] T001 Create feature task tracking and implementation notes in `ScoreWise/tasks.md`
- [ ] T002 Audit current decision flow entry points and route ownership in `ScoreWise/ScoreWiseApp/AppCore.swift`
- [ ] T003 [P] Audit current wizard UI reuse points and obsolete step framing in `ScoreWise/ScoreWiseApp/Views.swift`
- [ ] T004 [P] Audit current AI prompt/backend callable usage in `ScoreWise/ScoreWiseApp/Services.swift` and `ScoreWise/CloudFunctions/src/index.ts`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Introduce the shared models, routing, persistence, and service contracts required by all user stories.

**⚠️ CRITICAL**: No user story work should start before this phase is complete.

- [ ] T005 Extend `AppViewModel.Screen` and related navigation state for chat-first routing in `ScoreWise/ScoreWiseApp/AppCore.swift`
- [ ] T006 Add or normalize chat-first state (`decisionChatMessages`, `decisionChatPhase`, `isChatTyping`, `pendingFreeformReply`, `aiModeLabel`, `matrixSetupReady`) in `ScoreWise/ScoreWiseApp/AppCore.swift`
- [ ] T007 Add/finish chat-first model support for transcript, CTA, frameworks, and matrix setup in `ScoreWise/ScoreWiseApp/Models.swift`
- [ ] T008 [P] Extend `ChatThreadEntity` and `ChatMessageEntity` persistence fields needed for resume behavior in `ScoreWise/ScoreWiseApp/Models.swift`
- [ ] T009 Add new AI service contract methods (`startDecisionConversation`, `continueDecisionConversation`, `finalizeConversationForMatrix`) in `ScoreWise/ScoreWiseApp/Services.swift`
- [ ] T010 [P] Add persistence helpers for saving/loading decision chat threads and messages in `ScoreWise/ScoreWiseApp/Services.swift`
- [ ] T011 Add app-level flow helpers (`beginDecisionConversation`, `sendFreeformChatReply`, `selectChatOption`, `skipChatQuestion`, `completeChatAndPrepareMatrix`, `resumeDecision`) in `ScoreWise/ScoreWiseApp/AppCore.swift`
- [ ] T012 Add test coverage for chat-first state transitions and routing in `ScoreWise/ScoreWiseTests/DecisionChatFlowTests.swift`

**Checkpoint**: The app can hold the new chat-first state and compile against the new AI interface before UI work begins.

---

## Phase 3: User Story 1 - Start a decision through adaptive coaching chat (Priority: P1) 🎯 MVP

**Goal**: A user types a situation on Home, enters a dedicated Clarity AI chat, and receives adaptive framework questions instead of the old wizard intro.

**Independent Test**: From Home, entering a brief narrative opens `DecisionChatView`, shows the first user message plus an AI follow-up question with exactly four options, and supports select/skip/freeform replies.

### Tests for User Story 1

- [ ] T013 [P] [US1] Add unit tests for adaptive chat turn creation and exact-4-option enforcement in `ScoreWise/ScoreWiseTests/DecisionChatAIServiceTests.swift`
- [ ] T014 [P] [US1] Add unit tests for Home-to-chat routing and transcript bootstrapping in `ScoreWise/ScoreWiseTests/DecisionChatFlowTests.swift`

### Implementation for User Story 1

- [ ] T015 [US1] Replace Home submit behavior to seed a draft and route into `.decisionChat` in `ScoreWise/ScoreWiseApp/Views.swift` and `ScoreWise/ScoreWiseApp/AppCore.swift`
- [ ] T016 [US1] Create `DecisionChatView` shell with top bar, transcript list, fixed composer, and helper footer in `ScoreWise/ScoreWiseApp/Views.swift`
- [ ] T017 [P] [US1] Build reusable chat UI components (`DecisionAIMessageBubble`, `DecisionUserMessageBubble`, `DecisionOptionCard`, `DecisionTypingIndicator`, `DecisionChatComposer`) in `ScoreWise/ScoreWiseApp/Views.swift`
- [ ] T018 [US1] Implement chat message rendering, auto-scroll, typing delay, and haptic selection feedback in `ScoreWise/ScoreWiseApp/Views.swift`
- [ ] T019 [US1] Implement `LocalDecisionIntelligence.startConversation` and framework-aware question selection fallback in `ScoreWise/ScoreWiseApp/Services.swift`
- [ ] T020 [US1] Implement `LocalDecisionIntelligence.continueConversation` so later questions adapt to prior answers and stop after 4–6 turns in `ScoreWise/ScoreWiseApp/Services.swift`
- [ ] T021 [US1] Implement `FirebaseFunctionsAIService.startDecisionConversation` and `continueDecisionConversation` with local fallback and visible degraded mode labeling in `ScoreWise/ScoreWiseApp/Services.swift`
- [ ] T022 [US1] Persist each chat turn and restore incomplete chat sessions in `ScoreWise/ScoreWiseApp/AppCore.swift` and `ScoreWise/ScoreWiseApp/Services.swift`
- [ ] T023 [US1] Remove Home routing into the old wizard intro while keeping the wizard code available for downstream reuse in `ScoreWise/ScoreWiseApp/AppCore.swift` and `ScoreWise/ScoreWiseApp/Views.swift`

**Checkpoint**: User Story 1 is complete when chat is the primary entry flow and feels like a real conversation rather than a fixed wizard.

---

## Phase 4: User Story 2 - Turn the conversation into editable options and criteria (Priority: P1)

**Goal**: After the chat finishes, the app auto-fills options and criteria from the conversation and routes the user into the matrix workflow without old step framing.

**Independent Test**: Completing the AI chat transition leads to Options with real option names inferred from the conversation, then Criteria with specific suggested criteria tied to goals/constraints/tensions.

### Tests for User Story 2

- [ ] T024 [P] [US2] Add unit tests for `finalizeConversationForMatrix` and `DecisionBrief` extraction preserving actual option names in `ScoreWise/ScoreWiseTests/DecisionMatrixSetupTests.swift`
- [ ] T025 [P] [US2] Add unit tests for criteria generation based on conversation-derived brief data in `ScoreWise/ScoreWiseTests/DecisionCriteriaSuggestionTests.swift`

### Implementation for User Story 2

- [ ] T026 [US2] Implement `LocalDecisionIntelligence.finalizeConversation` and backend-aligned matrix setup output in `ScoreWise/ScoreWiseApp/Services.swift`
- [ ] T027 [US2] Implement `FirebaseFunctionsAIService.finalizeConversationForMatrix` with visible fallback mode handling in `ScoreWise/ScoreWiseApp/Services.swift`
- [ ] T028 [US2] Wire the chat CTA (`Set Up Your Options`) to finalize the conversation and merge `DecisionBrief`, suggested options, and suggested criteria into `activeDraft` in `ScoreWise/ScoreWiseApp/AppCore.swift`
- [ ] T029 [US2] Reuse the current options screen as the first downstream screen and auto-prefill chat-derived options in `ScoreWise/ScoreWiseApp/Views.swift`
- [ ] T030 [US2] Remove visible old `Step X of 7` framing from options, criteria, rating, and results when entering from the chat-first flow in `ScoreWise/ScoreWiseApp/Views.swift`
- [ ] T031 [US2] Update criteria suggestion logic to prefer conversation-derived tensions/goals/constraints over category-only heuristics in `ScoreWise/ScoreWiseApp/Services.swift`
- [ ] T032 [US2] Update results generation to reference actual option names, top weighted criteria, and conversation context in `ScoreWise/ScoreWiseApp/Services.swift`
- [ ] T033 [US2] Add or fix delete/edit/add option interactions so the prefilling remains editable without losing attachments or notes in `ScoreWise/ScoreWiseApp/AppCore.swift` and `ScoreWise/ScoreWiseApp/Views.swift`

**Checkpoint**: User Story 2 is complete when the conversation cleanly hands off to editable options/criteria and the final explanation references the actual decision.

---

## Phase 5: User Story 3 - Prompt-driven backend and trustworthy AI mode handling (Priority: P2)

**Goal**: Replace the thin backend prompt setup with a task-specific prompt architecture and make AI mode explicit instead of silently pretending fallback is full AI.

**Independent Test**: Backend prompt files exist, new callable contracts return structured conversation turns and matrix setup data, and the app visibly labels offline fallback when backend AI is unavailable.

### Tests for User Story 3

- [ ] T034 [P] [US3] Add unit tests for fallback labeling and structured conversation response decoding in `ScoreWise/ScoreWiseTests/DecisionBackendContractTests.swift`
- [ ] T035 [P] [US3] Add backend prompt contract tests for structured conversation outputs in `ScoreWise/CloudFunctions/src/index.test.ts`

### Implementation for User Story 3

- [ ] T036 [US3] Replace the global prompt in `ScoreWise/CloudFunctions/prompts/system.txt` with the new Clarity AI identity, tone, and hard rules
- [ ] T037 [P] [US3] Add `start_conversation.txt` in `ScoreWise/CloudFunctions/prompts/start_conversation.txt`
- [ ] T038 [P] [US3] Add `continue_conversation.txt` in `ScoreWise/CloudFunctions/prompts/continue_conversation.txt`
- [ ] T039 [P] [US3] Add `finalize_matrix_setup.txt` in `ScoreWise/CloudFunctions/prompts/finalize_matrix_setup.txt`
- [ ] T040 [P] [US3] Add `generate_insights.txt` in `ScoreWise/CloudFunctions/prompts/generate_insights.txt`
- [ ] T041 [US3] Refactor `ScoreWise/CloudFunctions/src/index.ts` to load prompt files and expose `startDecisionConversation`, `continueDecisionConversation`, and `finalizeConversationForMatrix`
- [ ] T042 [US3] Update backend payload shaping and response parsing to enforce exactly four options for question turns in `ScoreWise/CloudFunctions/src/index.ts`
- [ ] T043 [US3] Surface AI mode state (`Clarity AI` vs `Offline guidance`) inline in the chat UI in `ScoreWise/ScoreWiseApp/Views.swift` and `ScoreWise/ScoreWiseApp/AppCore.swift`
- [ ] T044 [US3] Remove silent fallback behavior for the primary decision flow and replace it with explicit degraded-mode messaging in `ScoreWise/ScoreWiseApp/Services.swift`

**Checkpoint**: User Story 3 is complete when the backend prompt system and app behavior align with the premium coaching contract and fallback is transparent.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Tighten quality, visual consistency, and shipping readiness across the whole feature.

- [ ] T045 [P] Verify DM Sans / DM Serif usage, title sizing, chat spacing, and bubble/card geometry in `ScoreWise/ScoreWiseApp/Views.swift` and `ScoreWise/ScoreWiseApp/DesignSystem.swift`
- [ ] T046 [P] Add conversation resume coverage for incomplete and complete drafts in `ScoreWise/ScoreWiseTests/DecisionResumeTests.swift`
- [ ] T047 Audit user-facing copy so branding and helper text consistently say `Clarity AI` in `ScoreWise/ScoreWiseApp/Views.swift`, `ScoreWise/ScoreWiseApp/Info.plist`, and `ScoreWise/CloudFunctions/prompts/*.txt`
- [ ] T048 Perform compile-stability cleanup in `ScoreWise/ScoreWiseApp/Services.swift` and `ScoreWise/ScoreWiseApp/Views.swift` to break up Swift compiler-hostile expressions
- [ ] T049 Run end-to-end manual validation for Home → Chat → Options → Criteria → Rating → Results and document findings in `ScoreWise/README.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1: Setup**: no dependencies
- **Phase 2: Foundational**: depends on Phase 1 and blocks all story work
- **Phase 3: US1**: depends on Phase 2
- **Phase 4: US2**: depends on Phase 3 because it consumes completed chat output
- **Phase 5: US3**: depends on Phase 2 and can overlap with late US1/US2 work where interfaces are already stable
- **Phase 6: Polish**: depends on all desired user stories

### User Story Dependencies

- **US1 (P1)**: primary MVP, no dependency on other stories after Foundational
- **US2 (P1)**: depends on US1 because chat must produce matrix setup data first
- **US3 (P2)**: depends on Foundational; backend prompt files and explicit fallback can be developed in parallel with late US1/US2 integration

### Within Each User Story

- Tests first where practical
- Service contracts before ViewModel wiring
- ViewModel wiring before final UI hookup
- Chat finalization before matrix prefill
- Backend prompt loading before strict callable rollout

---

## Parallel Opportunities

- Phase 2:
  - T008 and T010 can run in parallel
- US1:
  - T013 and T014 can run in parallel
  - T017 and T019 can run in parallel after T015/T016 shell work begins
- US2:
  - T024 and T025 can run in parallel
  - T031 and T033 can run in parallel once matrix setup exists
- US3:
  - T037, T038, T039, and T040 can run in parallel
  - T034 and T035 can run in parallel
- Polish:
  - T045, T046, and T047 can run in parallel

---

## Parallel Example: User Story 1

```bash
# Tests in parallel
Task: "T013 [US1] Add unit tests for adaptive chat turn creation and exact-4-option enforcement in ScoreWise/ScoreWiseTests/DecisionChatAIServiceTests.swift"
Task: "T014 [US1] Add unit tests for Home-to-chat routing and transcript bootstrapping in ScoreWise/ScoreWiseTests/DecisionChatFlowTests.swift"

# UI components and local AI fallback in parallel
Task: "T017 [US1] Build reusable chat UI components in ScoreWise/ScoreWiseApp/Views.swift"
Task: "T019 [US1] Implement LocalDecisionIntelligence.startConversation and framework-aware question selection fallback in ScoreWise/ScoreWiseApp/Services.swift"
```

---

## Implementation Strategy

### MVP First

1. Complete Phase 1
2. Complete Phase 2
3. Complete Phase 3 (US1)
4. Validate Home → Chat flow independently
5. Complete Phase 4 (US2) to restore full decision usefulness

### Incremental Delivery

1. Chat-first entry and adaptive question flow
2. Matrix setup handoff and downstream reuse
3. Backend prompt architecture and explicit AI mode handling
4. Polish, resume hardening, and compile stability cleanup

### Practical Execution Order

1. `ScoreWise/ScoreWiseApp/Services.swift`
2. `ScoreWise/ScoreWiseApp/AppCore.swift`
3. `ScoreWise/ScoreWiseApp/Views.swift`
4. `ScoreWise/CloudFunctions/prompts/*.txt`
5. `ScoreWise/CloudFunctions/src/index.ts`
6. `ScoreWise/ScoreWiseTests/*.swift`

---

## Notes

- `[P]` means different files or isolated tasks with no incomplete dependencies
- The old wizard should remain in code only as a temporary downstream reuse mechanism
- No user-facing silent fallback is allowed in the final flow
- The app should prefer backend AI, but it must be honest when degraded to offline guidance
