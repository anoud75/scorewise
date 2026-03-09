import * as admin from "firebase-admin";
import { onCall } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import mammoth from "mammoth";
import * as XLSX from "xlsx";
import { promises as fs } from "fs";
import * as path from "path";
import { request as httpsRequest } from "node:https";

admin.initializeApp();

const geminiApiKey = defineSecret("GEMINI_API_KEY");
const fastModel = process.env.GEMINI_MODEL_FAST ?? "gemini-2.5-flash-lite";
const reasoningModel = process.env.GEMINI_MODEL_REASONING ?? "gemini-2.5-flash";
const challengeQuestionMaxLength = 120;

type DecisionOptionType = "candidate" | "offer" | "school" | "vendor" | "generic_choice";
type DecisionOption = {
  id: string;
  label: string;
  type: DecisionOptionType;
  description?: string;
  aiSuggested: boolean;
};

type ExtractionUploadRef = {
  attachmentId?: string;
  fileName?: string;
  contentType?: string;
  base64?: string;
};

type KnowledgeDomain = "general_decision" | "recruitment_selection" | "career_path";
type EvidenceUsage = "question" | "criterion" | "risk" | "bias" | "recommendation";

type KnowledgeCard = {
  id: string;
  domain: KnowledgeDomain;
  principle: string;
  whenToApply: string;
  questionTemplates: string[];
  criteriaSeeds: string[];
  biasSignals: string[];
  constraintPatterns: string[];
  source: {
    fileName: string;
    sectionLabel: string;
  };
};

type EvidenceCitation = {
  cardId: string;
  sourceLabel: string;
  usedFor: EvidenceUsage;
};

let knowledgeCardsCache: KnowledgeCard[] | null = null;

async function readPromptFile(fileName: string) {
  const filePath = path.join(process.cwd(), "prompts", fileName);
  return fs.readFile(filePath, "utf8");
}

function renderPrompt(template: string, values: Record<string, string>) {
  return Object.entries(values).reduce((text, [key, value]) => {
    return text.split(`{{${key}}}`).join(value);
  }, template);
}

async function askGeminiJSON(
  model: string,
  systemPrompt: string,
  prompt: string,
  temperature = 0.2
) {
  const apiKey = geminiApiKey.value();
  if (!apiKey) {
    throw new Error("GEMINI_API_KEY is not configured.");
  }

  const requestBody = {
    systemInstruction: {
      parts: [{ text: systemPrompt }]
    },
    contents: [
      {
        role: "user",
        parts: [{ text: prompt }]
      }
    ],
    generationConfig: {
      temperature,
      responseMimeType: "application/json"
    }
  };

  const responseText = await postJSON(
    `/v1beta/models/${model}:generateContent?key=${encodeURIComponent(apiKey)}`,
    requestBody
  );
  const parsed = JSON.parse(responseText) as GeminiGenerateContentResponse;
  const candidateText = parsed.candidates?.[0]?.content?.parts
    ?.map((part) => part.text ?? "")
    .join("")
    .trim() ?? "{}";

  return JSON.parse(extractJSONObject(candidateText));
}

function postJSON(pathname: string, body: unknown): Promise<string> {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(body);
    const request = httpsRequest({
      hostname: "generativelanguage.googleapis.com",
      path: pathname,
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(payload)
      }
    }, (response) => {
      const chunks: Buffer[] = [];
      response.on("data", (chunk) => chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)));
      response.on("end", () => {
        const text = Buffer.concat(chunks).toString("utf8");
        const statusCode = response.statusCode ?? 500;
        if (statusCode < 200 || statusCode >= 300) {
          reject(new Error(`Gemini request failed (${statusCode}): ${text}`));
          return;
        }
        resolve(text);
      });
    });

    request.on("error", reject);
    request.write(payload);
    request.end();
  });
}

function extractJSONObject(text: string) {
  const match = text.match(/\{[\s\S]*\}/);
  return match?.[0] ?? "{}";
}

function normalizeWhitespace(value: string): string {
  return value.replace(/\s+/g, " ").trim();
}

function tokenizeForRetrieval(value: string): string[] {
  return normalizeWhitespace(value.toLowerCase())
    .replace(/[^a-z0-9\s]/g, " ")
    .split(" ")
    .map((token) => token.trim())
    .filter((token) => token.length >= 3);
}

function normalizeDomain(raw: string): KnowledgeDomain {
  if (raw === "recruitment_selection" || raw === "career_path") {
    return raw;
  }
  return "general_decision";
}

function sourceLabel(source: KnowledgeCard["source"]): string {
  return `${normalizeWhitespace(source.fileName)} — ${normalizeWhitespace(source.sectionLabel)}`;
}

function parseKnowledgeCard(raw: unknown, index: number): KnowledgeCard | null {
  if (typeof raw !== "object" || raw === null) {
    return null;
  }
  const record = raw as Record<string, unknown>;
  const id = normalizeWhitespace(typeof record.id === "string" ? record.id : `card_${index + 1}`);
  const principle = normalizeWhitespace(typeof record.principle === "string" ? record.principle : "");
  const whenToApply = normalizeWhitespace(typeof record.whenToApply === "string" ? record.whenToApply : "");
  const domain = normalizeDomain(normalizeWhitespace(typeof record.domain === "string" ? record.domain : ""));
  if (!id || !principle || !whenToApply) {
    return null;
  }

  const sourceRaw = (typeof record.source === "object" && record.source !== null)
    ? record.source as Record<string, unknown>
    : {};
  const fileName = normalizeWhitespace(typeof sourceRaw.fileName === "string" ? sourceRaw.fileName : "Knowledge source");
  const sectionLabel = normalizeWhitespace(typeof sourceRaw.sectionLabel === "string" ? sourceRaw.sectionLabel : "General principle");

  const parseList = (value: unknown) => Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string").map(normalizeWhitespace).filter(Boolean)
    : [];

  return {
    id,
    domain,
    principle,
    whenToApply,
    questionTemplates: parseList(record.questionTemplates),
    criteriaSeeds: parseList(record.criteriaSeeds),
    biasSignals: parseList(record.biasSignals),
    constraintPatterns: parseList(record.constraintPatterns),
    source: {
      fileName,
      sectionLabel
    }
  };
}

async function loadKnowledgeCards(): Promise<KnowledgeCard[]> {
  if (knowledgeCardsCache) {
    return knowledgeCardsCache;
  }
  const filePath = path.join(process.cwd(), "prompts", "knowledge_cards.json");
  const raw = await fs.readFile(filePath, "utf8");
  const parsed = JSON.parse(raw);
  if (!Array.isArray(parsed)) {
    knowledgeCardsCache = [];
    return knowledgeCardsCache;
  }
  knowledgeCardsCache = parsed
    .map((item, index) => parseKnowledgeCard(item, index))
    .filter((card): card is KnowledgeCard => card !== null);
  return knowledgeCardsCache;
}

function preferredKnowledgeDomain(contextBlob: string, usageContext: string): KnowledgeDomain {
  const combined = `${usageContext} ${contextBlob}`.toLowerCase();
  if (combined.includes("candidate") || combined.includes("recruit") || combined.includes("hiring") || combined.includes("staffing")) {
    return "recruitment_selection";
  }
  if (combined.includes("career") || combined.includes("offer") || combined.includes("salary") || combined.includes("job")) {
    return "career_path";
  }
  return "general_decision";
}

function retrieveKnowledgeCards(
  cards: KnowledgeCard[],
  params: {
    contextNarrative: string;
    usageContext: string;
    userProfile: unknown;
    phase: string;
    topK: number;
  }
): KnowledgeCard[] {
  const contextBlob = [
    params.contextNarrative,
    params.usageContext,
    JSON.stringify(params.userProfile ?? {}),
    params.phase
  ].join(" ");
  const preferredDomain = preferredKnowledgeDomain(contextBlob, params.usageContext);
  const queryTokens = tokenizeForRetrieval(contextBlob);
  const tokenSet = new Set(queryTokens);
  const shouldPrioritizeRisk = params.phase.includes("analysis") || params.phase.includes("result");
  const shouldPrioritizeQuestions = params.phase.includes("clarify") || params.phase.includes("collect");

  return cards
    .map((card) => {
      const docTokens = tokenizeForRetrieval(
        [
          card.principle,
          card.whenToApply,
          card.questionTemplates.join(" "),
          card.criteriaSeeds.join(" "),
          card.biasSignals.join(" "),
          card.constraintPatterns.join(" ")
        ].join(" ")
      );
      let score = 0;
      for (const token of docTokens) {
        if (tokenSet.has(token)) {
          score += 1;
        }
      }
      if (card.domain === preferredDomain) {
        score += 6;
      }
      if (card.domain === "general_decision") {
        score += 1;
      }
      if (shouldPrioritizeRisk && card.biasSignals.length > 0) {
        score += 1;
      }
      if (shouldPrioritizeQuestions && card.questionTemplates.length > 0) {
        score += 1;
      }
      return { card, score };
    })
    .sort((a, b) => b.score - a.score)
    .slice(0, Math.max(1, Math.min(params.topK, cards.length)))
    .map((entry) => entry.card);
}

function knowledgePromptBlock(cards: KnowledgeCard[]): string {
  if (cards.length === 0) {
    return "No external knowledge cards retrieved.";
  }
  const lines = cards.map((card) => {
    const questionHint = card.questionTemplates.slice(0, 2).join(" | ");
    const criteriaHint = card.criteriaSeeds.slice(0, 3).join(", ");
    const biasHint = card.biasSignals.slice(0, 2).join(", ");
    return [
      `- [${card.id}] (${card.domain}) ${card.principle}`,
      `  apply: ${card.whenToApply}`,
      `  question templates: ${questionHint}`,
      `  criteria seeds: ${criteriaHint}`,
      `  bias signals: ${biasHint}`,
      `  source: ${sourceLabel(card.source)}`
    ].join("\n");
  });
  return lines.join("\n");
}

function defaultCitations(cards: KnowledgeCard[], usedFor: EvidenceUsage, limit = 4): EvidenceCitation[] {
  return cards.slice(0, Math.max(1, limit)).map((card) => ({
    cardId: card.id,
    sourceLabel: sourceLabel(card.source),
    usedFor
  }));
}

function normalizeEvidenceUsage(raw: string): EvidenceUsage {
  if (raw === "question" || raw === "criterion" || raw === "risk" || raw === "bias") {
    return raw;
  }
  return "recommendation";
}

function parseCitations(raw: unknown, cards: KnowledgeCard[], fallbackUsage: EvidenceUsage): EvidenceCitation[] {
  const byId = new Map(cards.map((card) => [card.id, card]));
  if (!Array.isArray(raw)) {
    return defaultCitations(cards, fallbackUsage);
  }
  const parsed = raw.map((item) => {
    if (typeof item !== "object" || item === null) {
      return null;
    }
    const record = item as Record<string, unknown>;
    const cardId = normalizeWhitespace(typeof record.cardId === "string" ? record.cardId : "");
    if (!cardId) {
      return null;
    }
    const card = byId.get(cardId);
    const source = normalizeWhitespace(typeof record.sourceLabel === "string" ? record.sourceLabel : "");
    const usedForRaw = normalizeWhitespace(typeof record.usedFor === "string" ? record.usedFor : "");
    return {
      cardId,
      sourceLabel: card ? sourceLabel(card.source) : (source || "Knowledge source"),
      usedFor: normalizeEvidenceUsage(usedForRaw)
    } satisfies EvidenceCitation;
  }).filter((item): item is EvidenceCitation => item !== null);

  if (parsed.length > 0) {
    return parsed.slice(0, 6);
  }
  return defaultCitations(cards, fallbackUsage);
}

function detectConstraintSignals(cards: KnowledgeCard[], contextBlob: string): string[] {
  const lowerContext = contextBlob.toLowerCase();
  const findings: string[] = [];
  for (const card of cards) {
    for (const pattern of card.constraintPatterns) {
      const token = pattern.toLowerCase();
      if (token.length < 3) {
        continue;
      }
      if (lowerContext.includes(token)) {
        findings.push(`${card.id}: possible hard constraint related to "${pattern}" (${sourceLabel(card.source)})`);
        break;
      }
    }
  }
  return findings.slice(0, 6);
}

function makeOptionId(label: string, index: number): string {
  const base = label
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 32);
  return base ? `opt_${base}` : `opt_${index + 1}`;
}

function isGenericPlaceholder(label: string): boolean {
  const normalized = normalizeWhitespace(label).toLowerCase();
  return normalized.startsWith("vendor ") ||
    normalized.startsWith("option ") ||
    normalized.startsWith("candidate ") ||
    normalized === "option" ||
    normalized === "vendor";
}

function inferOptionType(label: string, context: string): DecisionOptionType {
  const lower = label.toLowerCase();
  const contextLower = context.toLowerCase();
  if (contextLower.includes("candidate") || contextLower.includes("recruit") || contextLower.includes("hiring")) {
    return "candidate";
  }
  if (lower.includes("offer") || lower.includes("current job") || lower.includes("role")) {
    return "offer";
  }
  if (lower.includes("candidate")) {
    return "candidate";
  }
  if (lower.includes("school") || lower.includes("university") || lower.includes("college")) {
    return "school";
  }
  if (lower.includes("vendor") || lower.includes("provider")) {
    return "vendor";
  }
  return "generic_choice";
}

function sanitizeOptions(raw: unknown, context: string): DecisionOption[] {
  if (!Array.isArray(raw)) {
    return [];
  }

  const parsed = raw
    .map((item, index): DecisionOption | null => {
      if (typeof item !== "object" || item === null) {
        return null;
      }
      const record = item as Record<string, unknown>;
      const labelRaw = typeof record.label === "string"
        ? record.label
        : (typeof record.title === "string" ? record.title : "");
      const label = normalizeWhitespace(labelRaw);
      if (!label) {
        return null;
      }
      const typeRaw = typeof record.type === "string" ? record.type : "";
      const type = (["candidate", "offer", "school", "vendor", "generic_choice"] as const).includes(typeRaw as DecisionOptionType)
        ? (typeRaw as DecisionOptionType)
        : inferOptionType(label, context);
      const description = typeof record.description === "string" ? normalizeWhitespace(record.description) : undefined;
      return {
        id: typeof record.id === "string" && normalizeWhitespace(record.id) ? normalizeWhitespace(record.id) : makeOptionId(label, index),
        label,
        type,
        description,
        aiSuggested: typeof record.aiSuggested === "boolean" ? record.aiSuggested : true
      };
    })
    .filter((item): item is DecisionOption => item !== null);

  const deduped: DecisionOption[] = [];
  const seen = new Set<string>();
  for (const option of parsed) {
    const key = option.label.toLowerCase();
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    deduped.push(option);
  }

  const nonGenericCount = deduped.filter((option) => !isGenericPlaceholder(option.label)).length;
  const filtered = nonGenericCount >= 2
    ? deduped.filter((option) => !isGenericPlaceholder(option.label))
    : deduped;

  const contextLower = context.toLowerCase();
  const recruiterMode = contextLower.includes("candidate") || contextLower.includes("recruit") || contextLower.includes("hiring");
  return filtered
    .map((option) => recruiterMode ? { ...option, type: "candidate" as const } : option)
    .slice(0, 8);
}

function clampSingleSentence(text: string, maxLength = challengeQuestionMaxLength): string {
  const compact = normalizeWhitespace(text);
  const firstSentence = compact.split(/[.!?]/)[0] ?? compact;
  const trimmed = normalizeWhitespace(firstSentence);
  if (trimmed.length <= maxLength) {
    return trimmed;
  }
  return trimmed.slice(0, maxLength).trim();
}

function enforceStructuredContent(content: string): string {
  const compact = normalizeWhitespace(content);
  if (
    compact.includes("Recommendation") &&
    compact.includes("Why this option leads") &&
    compact.includes("Risks to consider") &&
    compact.includes("Confidence level") &&
    compact.includes("Next step")
  ) {
    return content.trim();
  }
  return [
    "Recommendation",
    compact || "Need more context",
    "",
    "Why this option leads",
    "This direction best matches the weighted evidence and constraints currently provided.",
    "",
    "Risks to consider",
    "One or two assumptions still need validation before final commitment.",
    "",
    "Confidence level",
    "Medium",
    "",
    "Next step",
    "Run one concrete validation check this week, then finalize."
  ].join("\n");
}

function enforceCitationAwareStructuredContent(content: string, citations: EvidenceCitation[]): string {
  if (citations.length > 0) {
    return enforceStructuredContent(content);
  }
  return [
    "Recommendation",
    "Current recommendation is provisional because supporting evidence citations are missing.",
    "",
    "Why this option leads",
    "Direction is based on partial context and should be validated with stronger evidence.",
    "",
    "Risks to consider",
    "Key assumptions are weakly supported and could change the ranking.",
    "",
    "Confidence level",
    "Low (insufficient cited evidence)",
    "",
    "Next step",
    "Add concrete evidence and regenerate analysis before finalizing."
  ].join("\n");
}

function hasLowVarianceScores(payload: unknown): boolean {
  if (typeof payload !== "object" || payload === null) {
    return false;
  }
  const record = payload as Record<string, unknown>;
  const scoresRaw = Array.isArray(record.draftScores) ? record.draftScores as Array<Record<string, unknown>> : [];
  if (scoresRaw.length < 4) {
    return false;
  }

  const criterionMap = new Map<string, number[]>();
  for (const item of scoresRaw) {
    if (typeof item !== "object" || item === null) {
      continue;
    }
    const criterionID = typeof item.criterionID === "string" ? item.criterionID : "";
    const score = typeof item.score === "number" ? item.score : Number(item.score ?? NaN);
    if (!criterionID || !Number.isFinite(score)) {
      continue;
    }
    const existing = criterionMap.get(criterionID) ?? [];
    existing.push(score);
    criterionMap.set(criterionID, existing);
  }

  if (criterionMap.size == 0) {
    return false;
  }

  let lowVarianceCriteria = 0;
  let checkedCriteria = 0;
  for (const scores of criterionMap.values()) {
    if (scores.length < 2) {
      continue;
    }
    checkedCriteria += 1;
    const min = Math.min(...scores);
    const max = Math.max(...scores);
    if ((max - min) < 0.25) {
      lowVarianceCriteria += 1;
    }
  }

  if (checkedCriteria == 0) {
    return false;
  }
  return lowVarianceCriteria / checkedCriteria >= 0.6;
}

const conversationQuestionWordLimit = 25;
const conversationOptionWordLimit = 15;
const conversationTransitionWordLimit = 30;

type ConversationCallableResponse = {
  message: {
    content: string;
    options: string[];
    allowSkip: boolean;
    allowsFreeformReply: boolean;
    framework: string | null;
    cta: { title: string; action: string } | null;
    isTransition: boolean;
  };
  conversationState: {
    phase: string;
    frameworksUsed: string[];
  };
};

function wordCount(value: string): number {
  const normalized = normalizeWhitespace(value);
  if (!normalized) {
    return 0;
  }
  return normalized.split(" ").filter(Boolean).length;
}

function clampWords(value: string, maxWords: number): string {
  const normalized = normalizeWhitespace(value);
  if (!normalized) {
    return "";
  }
  const words = normalized.split(" ").filter(Boolean);
  if (words.length <= maxWords) {
    return normalized;
  }
  return words.slice(0, maxWords).join(" ").trim();
}

function parseStringOptions(raw: unknown): string[] {
  if (!Array.isArray(raw)) {
    return [];
  }
  return raw.map((item) => {
    if (typeof item === "string") {
      return normalizeWhitespace(item);
    }
    if (typeof item === "object" && item !== null) {
      const record = item as Record<string, unknown>;
      const text = typeof record.text === "string"
        ? record.text
        : (typeof record.label === "string" ? record.label : "");
      return normalizeWhitespace(text);
    }
    return "";
  }).filter(Boolean);
}

function toConversationResponse(raw: unknown): ConversationCallableResponse {
  const fallbackQuestionOptions = [
    "Protect downside risk",
    "Maximize long-term upside",
    "Keep flexibility first",
    "Need more evidence"
  ];
  const fallbackQuestion = "Which factor matters most for this decision right now?";
  const fallbackTransition = "I have enough context to set up your decision matrix.";

  if (typeof raw !== "object" || raw === null) {
    return {
      message: {
        content: fallbackQuestion,
        options: fallbackQuestionOptions,
        allowSkip: true,
        allowsFreeformReply: true,
        framework: "valuesAlignment",
        cta: null,
        isTransition: false
      },
      conversationState: {
        phase: "collecting",
        frameworksUsed: ["valuesAlignment"]
      }
    };
  }

  const payload = raw as Record<string, unknown>;
  const messageRaw = (payload.message ?? {}) as Record<string, unknown>;
  const stateRaw = (payload.conversationState ?? {}) as Record<string, unknown>;
  const isTransition = Boolean(messageRaw.isTransition);
  const ctaRaw = (messageRaw.cta ?? null) as Record<string, unknown> | null;
  const cta = ctaRaw && typeof ctaRaw === "object"
    ? {
      title: normalizeWhitespace(typeof ctaRaw.title === "string" ? ctaRaw.title : "Set Up Your Options"),
      action: normalizeWhitespace(typeof ctaRaw.action === "string" ? ctaRaw.action : "setupOptions")
    }
    : null;

  const contentRaw = typeof messageRaw.content === "string" ? messageRaw.content : "";
  const contentFallback = isTransition ? fallbackTransition : fallbackQuestion;
  const content = normalizeWhitespace(contentRaw) || contentFallback;
  const options = isTransition ? [] : parseStringOptions(messageRaw.options);
  const frameworksUsedRaw = Array.isArray(stateRaw.frameworksUsed) ? stateRaw.frameworksUsed : [];
  const frameworksUsed = frameworksUsedRaw
    .filter((item): item is string => typeof item === "string")
    .map(normalizeWhitespace)
    .filter(Boolean);
  const frameworkRaw = typeof messageRaw.framework === "string" ? normalizeWhitespace(messageRaw.framework) : "";
  const framework = frameworkRaw || (frameworksUsed[frameworksUsed.length - 1] ?? null);

  return {
    message: {
      content,
      options: options.length > 0 ? options : (isTransition ? [] : fallbackQuestionOptions),
      allowSkip: typeof messageRaw.allowSkip === "boolean" ? messageRaw.allowSkip : !isTransition,
      allowsFreeformReply: typeof messageRaw.allowsFreeformReply === "boolean" ? messageRaw.allowsFreeformReply : !isTransition,
      framework: isTransition ? null : framework,
      cta: isTransition ? (cta ?? { title: "Set Up Your Options", action: "setupOptions" }) : null,
      isTransition
    },
    conversationState: {
      phase: normalizeWhitespace(typeof stateRaw.phase === "string" ? stateRaw.phase : (isTransition ? "transitionReady" : "collecting")) || (isTransition ? "transitionReady" : "collecting"),
      frameworksUsed
    }
  };
}

function exceedsConversationLimits(payload: ConversationCallableResponse): boolean {
  if (payload.message.isTransition) {
    return wordCount(payload.message.content) > conversationTransitionWordLimit;
  }
  if (wordCount(payload.message.content) > conversationQuestionWordLimit) {
    return true;
  }
  if (payload.message.options.length !== 4) {
    return true;
  }
  return payload.message.options.some((option) => wordCount(option) > conversationOptionWordLimit);
}

function clampConversationPayload(payload: ConversationCallableResponse): ConversationCallableResponse {
  const fallbackQuestionOptions = [
    "Protect downside risk",
    "Maximize long-term upside",
    "Keep flexibility first",
    "Need more evidence"
  ];

  if (payload.message.isTransition) {
    return {
      message: {
        content: clampWords(payload.message.content, conversationTransitionWordLimit) || "I have enough context to set up your decision matrix.",
        options: [],
        allowSkip: false,
        allowsFreeformReply: false,
        framework: null,
        cta: payload.message.cta ?? { title: "Set Up Your Options", action: "setupOptions" },
        isTransition: true
      },
      conversationState: {
        phase: "transitionReady",
        frameworksUsed: payload.conversationState.frameworksUsed
      }
    };
  }

  const normalizedOptions = payload.message.options
    .slice(0, 4)
    .map((option) => clampWords(option, conversationOptionWordLimit))
    .filter(Boolean);
  while (normalizedOptions.length < 4) {
    normalizedOptions.push(fallbackQuestionOptions[normalizedOptions.length]);
  }

  const clampedFramework = payload.message.framework ? normalizeWhitespace(payload.message.framework) : null;
  const frameworksUsed = payload.conversationState.frameworksUsed.filter(Boolean);
  if (clampedFramework && !frameworksUsed.includes(clampedFramework)) {
    frameworksUsed.push(clampedFramework);
  }

  return {
    message: {
      content: clampWords(payload.message.content, conversationQuestionWordLimit) || "Which factor matters most for this decision right now?",
      options: normalizedOptions,
      allowSkip: true,
      allowsFreeformReply: true,
      framework: clampedFramework ?? "valuesAlignment",
      cta: null,
      isTransition: false
    },
    conversationState: {
      phase: "collecting",
      frameworksUsed
    }
  };
}

async function guardedConversationResponse(
  model: string,
  systemPrompt: string,
  prompt: string
): Promise<ConversationCallableResponse> {
  const firstPassRaw = await askGeminiJSON(model, systemPrompt, prompt, 0.2);
  const firstPassParsed = toConversationResponse(firstPassRaw);
  if (!exceedsConversationLimits(firstPassParsed)) {
    return clampConversationPayload(firstPassParsed);
  }

  const repairPrompt = [
    prompt,
    "",
    "REPAIR INSTRUCTION:",
    "- Fix the previous output to strictly satisfy word limits and shape.",
    `- Question content max ${conversationQuestionWordLimit} words.`,
    `- Each option max ${conversationOptionWordLimit} words.`,
    `- Transition content max ${conversationTransitionWordLimit} words.`,
    "- If unsure, return a transition turn.",
    "Previous output JSON:",
    JSON.stringify(firstPassRaw)
  ].join("\n");

  const repairedRaw = await askGeminiJSON(model, systemPrompt, repairPrompt, 0.1);
  return clampConversationPayload(toConversationResponse(repairedRaw));
}

function forcedTransitionResponse(frameworksUsed: string[]): ConversationCallableResponse {
  return {
    message: {
      content: "I have enough context to build your decision matrix.",
      options: [],
      allowSkip: false,
      allowsFreeformReply: false,
      framework: null,
      cta: { title: "Set Up Your Options", action: "setupOptions" },
      isTransition: true
    },
    conversationState: {
      phase: "transitionReady",
      frameworksUsed
    }
  };
}

const aiFunctionOptions = {
  secrets: [geminiApiKey]
};

export const suggestRankingInputs = onCall(aiFunctionOptions, async (request) => {
  const systemPrompt = await readPromptFile("system.txt");
  const { projectId, vendors, extractedText, usageContext, contextNarrative, userProfile } = request.data;
  const knowledgeCards = await loadKnowledgeCards();
  const retrievedCards = retrieveKnowledgeCards(knowledgeCards, {
    contextNarrative: String(contextNarrative ?? ""),
    usageContext: String(usageContext ?? ""),
    userProfile,
    phase: "matrix_setup",
    topK: 6
  });
  const constraintSignals = detectConstraintSignals(
    retrievedCards,
    `${String(contextNarrative ?? "")}\n${JSON.stringify(extractedText ?? [])}`
  );
  const optionSummary = Array.isArray(vendors)
    ? vendors.map((vendor: Record<string, unknown>) => `${String(vendor.id ?? "")}:${String(vendor.name ?? "")}`).join(" | ")
    : "";
  const knowledgeBlock = knowledgePromptBlock(retrievedCards);
  const prompt = [
    "You are constructing a weighted decision matrix for this specific case.",
    `Project: ${projectId ?? ""}`,
    `Situation: ${contextNarrative ?? ""}`,
    `Usage context: ${usageContext ?? "unknown"}`,
    `Options: ${optionSummary}`,
    `User profile: ${JSON.stringify(userProfile ?? {})}`,
    `Evidence: ${JSON.stringify(extractedText ?? [])}`,
    `Detected hard-constraint signals: ${JSON.stringify(constraintSignals)}`,
    "",
    "RETRIEVED KNOWLEDGE CARDS (cite card IDs in your output):",
    knowledgeBlock,
    "",
    "STEP 1 — CRITERIA (3-20):",
    "- Criteria must be MECE (non-overlapping and collectively complete for this case).",
    "- Include at least one risk/downside criterion.",
    "- Include at least one reversibility/exit-cost criterion.",
    "- Weights must reflect this user's stated priorities.",
    "",
    "STEP 2 — SCORES (1-10):",
    "- Score each option against each criterion.",
    "- If direct evidence is weak or missing, reduce confidence clearly.",
    "- Do not assign identical scores unless evidence truly supports parity.",
    "- If two options are close, still differentiate at criterion level when evidence exists.",
    "- Keep evidenceSnippet concrete and tied to provided context.",
    "",
    "Return valid JSON only with this exact shape:",
    "{",
    '  "criteria": [{"name":"", "detail":"", "category":"", "weightPercent":0}],',
    '  "draftScores": [{"vendorID":"", "criterionID":"", "score":0, "confidence":0, "evidenceSnippet":""}],',
    '  "methodNotes": [""],',
    '  "citations": [{"cardId":"", "sourceLabel":"", "usedFor":"criterion"}]',
    "}",
    "Constraints: weights total exactly 100, confidence range 0-1, no placeholder names, and include at least one citation."
  ].join("\n");

  const firstPassRaw = await askGeminiJSON(fastModel, systemPrompt, prompt, 0.15);
  const firstPass = (typeof firstPassRaw === "object" && firstPassRaw !== null) ? firstPassRaw as Record<string, unknown> : {};
  const firstCitations = parseCitations(firstPass.citations, retrievedCards, "criterion");
  const firstPayload = {
    ...firstPass,
    citations: firstCitations
  };

  if (!hasLowVarianceScores(firstPayload)) {
    return firstPayload;
  }

  const retryPrompt = [
    prompt,
    "",
    "RETRY INSTRUCTION:",
    "- Your previous draft had low score variance across options.",
    "- Re-score with clearer evidence-based differentiation per criterion.",
    "- If near-tie is truly real, explain it in methodNotes and still avoid uniform score bands."
  ].join("\n");

  const secondPassRaw = await askGeminiJSON(reasoningModel, systemPrompt, retryPrompt, 0.12);
  const secondPass = (typeof secondPassRaw === "object" && secondPassRaw !== null) ? secondPassRaw as Record<string, unknown> : {};
  return {
    ...secondPass,
    citations: parseCitations(secondPass.citations, retrievedCards, "criterion")
  };
});

export const generateClarifyingQuestions = onCall(aiFunctionOptions, async (request) => {
  const systemPrompt = await readPromptFile("system.txt");
  const { projectId, situationText, userProfile } = request.data;
  const knowledgeCards = await loadKnowledgeCards();
  const retrievedCards = retrieveKnowledgeCards(knowledgeCards, {
    contextNarrative: String(situationText ?? ""),
    usageContext: String(userProfile?.primaryUsage ?? "other"),
    userProfile,
    phase: "clarifying_questions",
    topK: 6
  });
  const knowledgeBlock = knowledgePromptBlock(retrievedCards);
  const prompt = [
    "Generate clarifying questions that directly improve decision quality.",
    `Project: ${projectId ?? ""}`,
    `Situation: ${situationText ?? ""}`,
    `User profile: ${JSON.stringify(userProfile ?? {})}`,
    "",
    "RETRIEVED KNOWLEDGE CARDS (use these to avoid generic questions):",
    knowledgeBlock,
    "Requirements:",
    "- Produce 6-12 questions.",
    "- Closed-ended only: yes/no, fixed choice, numeric range, or short scale.",
    "- At least one question about hard constraints.",
    "- At least one question about risk tolerance.",
    "- At least one question about hidden stakeholders or second-order effects.",
    "- No generic filler prompts (e.g., 'tell me more').",
    "- One sentence per question.",
    "- Each question must include citation support from retrieved cards.",
    "Return JSON only in this shape:",
    '{ "questions": [{"question":"", "citations":[{"cardId":"", "sourceLabel":"", "usedFor":"question"}]}], "citations":[{"cardId":"", "sourceLabel":"", "usedFor":"question"}] }'
  ].join("\n");

  const payloadRaw = await askGeminiJSON(fastModel, systemPrompt, prompt, 0.2);
  const payload = (typeof payloadRaw === "object" && payloadRaw !== null) ? payloadRaw as Record<string, unknown> : {};
  const sharedCitations = parseCitations(payload.citations, retrievedCards, "question");
  const questionItems = Array.isArray(payload.questions) ? payload.questions : [];
  const questions = questionItems.map((item) => {
    if (typeof item === "string") {
      return {
        question: clampSingleSentence(item, 140),
        answer: "",
        citations: sharedCitations
      };
    }
    if (typeof item === "object" && item !== null) {
      const record = item as Record<string, unknown>;
      const question = clampSingleSentence(typeof record.question === "string" ? record.question : "", 140);
      if (!question) {
        return null;
      }
      return {
        question,
        answer: "",
        citations: parseCitations(record.citations, retrievedCards, "question")
      };
    }
    return null;
  }).filter((item): item is { question: string; answer: string; citations: EvidenceCitation[] } => item !== null);

  return {
    questions,
    citations: sharedCitations
  };
});

export const suggestDecisionOptions = onCall(aiFunctionOptions, async (request) => {
  const systemPrompt = await readPromptFile("system.txt");
  const { projectId, situationText, clarifyingQuestions, userProfile } = request.data;
  const contextBlob = JSON.stringify({
    situationText: situationText ?? "",
    clarifyingQuestions: clarifyingQuestions ?? []
  });
  const prompt = [
    `Project: ${projectId}`,
    `Situation: ${situationText ?? ""}`,
    `Clarifying answers: ${JSON.stringify(clarifyingQuestions ?? [])}`,
    `User profile: ${JSON.stringify(userProfile ?? {})}`,
    "Extract and normalize explicit primary decision options from the user context.",
    "Comparable-option rule:",
    "- Options must be same comparison type (candidate vs candidate, offer vs offer, etc.).",
    "- If user mixes type + strategy, keep only primary comparable options.",
    "Scope rule:",
    "- If 2 or more explicit options are present, return only those options.",
    "- Do not add pilot/negotiate/hybrid/wait unless explicitly listed as a primary option.",
    "Naming rule:",
    "- Preserve exact option names.",
    "- Never emit Vendor A/B, Option A/B, Candidate 1/2 placeholders when names exist.",
    "Return JSON only in this shape:",
    '{ "options": [{"id":"", "label":"", "type":"candidate|offer|school|vendor|generic_choice", "description":"", "aiSuggested": true}] }'
  ].join("\n");

  const payload = await askGeminiJSON(fastModel, systemPrompt, prompt, 0.25);
  return sanitizeOptions(payload.options, contextBlob);
});

export const generateBiasChallenges = onCall(aiFunctionOptions, async (request) => {
  const systemPrompt = await readPromptFile("system.txt");
  const { projectId, preferredOption, situationText, clarifyingQuestions, userProfile } = request.data;
  const prompt = [
    `Project: ${projectId}`,
    `Situation: ${situationText ?? ""}`,
    `Clarifying answers: ${JSON.stringify(clarifyingQuestions ?? [])}`,
    `Apparent preference: ${preferredOption ?? ""}`,
    `User profile: ${JSON.stringify(userProfile ?? {})}`,
    "Select exactly 3 debiasing exercises from [friend_test, ten_ten_ten, pre_mortem, worst_case, inversion, inaction_cost, values_check].",
    "Personalization rules:",
    "- Reference specific names/stakes from the decision.",
    "- If biggest challenge suggests overthinking, prefer commitment-forcing prompts (inversion, worst_case).",
    "- If biggest challenge suggests fear, prefer risk-normalizing prompts (pre_mortem, inaction_cost).",
    "- Force trade-off clarity, do not ask vague reflection questions.",
    "Formatting rules:",
    "- Each question must be one sentence.",
    "- Each question must be <=120 characters.",
    "Return JSON only in this shape:",
    '{ "challenges": [{"type":"friend_test", "question":"", "response": ""}] }'
  ].join("\n");

  const payload = await askGeminiJSON(fastModel, systemPrompt, prompt, 0.2);
  const challenges = Array.isArray(payload.challenges) ? payload.challenges as Array<Record<string, unknown>> : [];
  return challenges
    .map((item) => {
      const type = typeof item.type === "string" ? item.type : "friend_test";
      const questionRaw = typeof item.question === "string" ? item.question : "";
      return {
        type,
        question: clampSingleSentence(questionRaw),
        response: typeof item.response === "string" ? item.response : ""
      };
    })
    .filter((item) => item.question.length > 0)
    .slice(0, 3);
});

export const decisionChat = onCall(aiFunctionOptions, async (request) => {
  const systemPrompt = await readPromptFile("system.txt");
  const { projectId, phase, message, draft, userProfile } = request.data;
  const reassuranceMode = phase === "post_challenge_reassurance";
  const knowledgeCards = await loadKnowledgeCards();
  const usageHint = typeof draft?.usageContext === "string"
    ? draft.usageContext
    : (typeof userProfile?.primaryUsage === "string" ? userProfile.primaryUsage : "other");
  const retrievedCards = retrieveKnowledgeCards(knowledgeCards, {
    contextNarrative: `${String(message ?? "")}\n${JSON.stringify(draft ?? {})}`,
    usageContext: String(usageHint),
    userProfile,
    phase: String(phase ?? ""),
    topK: reassuranceMode || phase === "analysis" || phase === "results" ? 8 : 6
  });
  const knowledgeBlock = knowledgePromptBlock(retrievedCards);
  const prompt = [
    `Project: ${projectId}`,
    `Phase: ${phase}`,
    `User message: ${message}`,
    `Draft context: ${JSON.stringify(draft ?? {})}`,
    `User profile: ${JSON.stringify(userProfile ?? {})}`,
    "",
    "RETRIEVED KNOWLEDGE CARDS (use and cite these sources):",
    knowledgeBlock,
    "PHASE BEHAVIOR:",
    reassuranceMode
      ? "- Post-challenge reassurance: validate emotion, restate trade-off reality, and give stabilizing next action."
      : "- If critical context is missing, ask one high-leverage closed-ended question before advice.",
    "- Keep response concise and concrete.",
    "- No generic filler language.",
    "- Preserve explicit names; no placeholders.",
    "- Cite at least one knowledge card in recommendation/risk sections.",
    "- If evidence support is weak, explicitly lower confidence.",
    "- End with either a question OR an action, not both.",
    "Return JSON only:",
    '{ "content": "", "recommendedActions": [""], "citations": [{"cardId":"", "sourceLabel":"", "usedFor":"recommendation"}] }',
    "When phase is analysis/results/reassurance, content must follow exactly:",
    "Recommendation",
    "Why this option leads",
    "Risks to consider",
    "Confidence level",
    "Next step"
  ].join("\n");

  const payload = await askGeminiJSON(fastModel, systemPrompt, prompt, 0.2) as Record<string, unknown>;
  const rawContent = typeof payload.content === "string" ? payload.content : "";
  const recommendedActions = Array.isArray(payload.recommendedActions)
    ? payload.recommendedActions.filter((item): item is string => typeof item === "string").map(normalizeWhitespace).filter(Boolean).slice(0, 3)
    : [];
  const citations = parseCitations(payload.citations, retrievedCards, "recommendation");
  const shouldStructure = reassuranceMode || phase === "analysis" || phase === "results";

  return {
    content: shouldStructure
      ? enforceCitationAwareStructuredContent(rawContent, citations)
      : (rawContent.trim() || "I need more context to give a grounded answer."),
    recommendedActions,
    citations
  };
});

export const generateInsights = onCall(aiFunctionOptions, async (request) => {
  const systemPrompt = await readPromptFile("system.txt");
  const { projectId, draft, result, userProfile } = request.data;
  const knowledgeCards = await loadKnowledgeCards();
  const retrievedCards = retrieveKnowledgeCards(knowledgeCards, {
    contextNarrative: `${JSON.stringify(draft ?? {})}\n${JSON.stringify(result ?? {})}`,
    usageContext: String(draft?.usageContext ?? userProfile?.primaryUsage ?? "other"),
    userProfile,
    phase: "analysis",
    topK: 8
  });
  const knowledgeBlock = knowledgePromptBlock(retrievedCards);
  const prompt = [
    "Generate a structured post-decision insight report.",
    `Project: ${projectId}`,
    `Draft payload: ${JSON.stringify(draft)}`,
    `Result payload: ${JSON.stringify(result)}`,
    `User profile: ${JSON.stringify(userProfile ?? {})}`,
    "",
    "RETRIEVED KNOWLEDGE CARDS (use and cite these):",
    knowledgeBlock,
    "",
    "Analysis steps:",
    "1) Check whether score winner aligns with bias challenge responses; flag contradictions.",
    "2) If any criterion >20% weight has low-confidence evidence, flag winner instability.",
    "3) If margin between #1 and #2 is thin (<10%), explicitly call it near-tie.",
    "4) Identify blind spots not represented in the scorecard (optionality, reversibility, relationship effects).",
    "5) Tie recommendation logic to user values when available.",
    "",
    "Return JSON only:",
    "{",
    '  "summary":"",',
    '  "winnerReasoning":"",',
    '  "riskFlags":[""],',
    '  "overlookedStrategicPoints":[""],',
    '  "sensitivityFindings":[""],',
    '  "citations":[{"cardId":"", "sourceLabel":"", "usedFor":"risk"}]',
    "}",
    "Constraints:",
    "- winnerReasoning must preserve explicit names and avoid placeholders.",
    "- summary should be concise and decision-driving.",
    "- riskFlags and sensitivityFindings should highlight potential flips/uncertainty.",
    "- include at least one citation; if support is weak, explicitly state low confidence."
  ].join("\n");

  const rawPayload = await askGeminiJSON(reasoningModel, systemPrompt, prompt, 0.2);
  const payload = (typeof rawPayload === "object" && rawPayload !== null) ? rawPayload as Record<string, unknown> : {};
  const citations = parseCitations(payload.citations, retrievedCards, "risk");
  const riskFlags = Array.isArray(payload.riskFlags)
    ? payload.riskFlags.filter((item): item is string => typeof item === "string")
    : [];
  const summary = normalizeWhitespace(typeof payload.summary === "string" ? payload.summary : "");

  return {
    ...payload,
    summary: summary || "Evidence support is limited; treat current winner as provisional.",
    riskFlags: citations.length > 0 ? riskFlags : [...riskFlags, "Evidence support is limited; confidence is low until more validated inputs are added."],
    citations
  };
});

export const startDecisionConversation = onCall(aiFunctionOptions, async (request) => {
  const systemPrompt = await readPromptFile("system.txt");
  const taskPrompt = await readPromptFile("start_conversation.txt");
  const renderedPrompt = renderPrompt(taskPrompt, {
    projectId: JSON.stringify(request.data.projectId ?? ""),
    contextNarrative: JSON.stringify(request.data.contextNarrative ?? ""),
    usageContext: JSON.stringify(request.data.usageContext ?? ""),
    userProfile: JSON.stringify(request.data.userProfile ?? {})
  });
  const knowledgeCards = await loadKnowledgeCards();
  const retrievedCards = retrieveKnowledgeCards(knowledgeCards, {
    contextNarrative: String(request.data.contextNarrative ?? ""),
    usageContext: String(request.data.usageContext ?? "other"),
    userProfile: request.data.userProfile ?? {},
    phase: "conversation_start",
    topK: 6
  });
  const prompt = [
    renderedPrompt,
    "",
    "RETRIEVED KNOWLEDGE CARDS (use for concise, closed-ended, context-specific questions):",
    knowledgePromptBlock(retrievedCards)
  ].join("\n");
  return guardedConversationResponse(fastModel, systemPrompt, prompt);
});

export const continueDecisionConversation = onCall(aiFunctionOptions, async (request) => {
  const systemPrompt = await readPromptFile("system.txt");
  const taskPrompt = await readPromptFile("continue_conversation.txt");
  const transcript = Array.isArray(request.data.transcript) ? request.data.transcript as Array<Record<string, unknown>> : [];
  const frameworksUsed = transcript
    .map((entry) => normalizeWhitespace(String(entry.framework ?? "")))
    .filter(Boolean);
  const turnCount = transcript.filter((entry) => {
    const role = normalizeWhitespace(String(entry.role ?? "")).toLowerCase();
    const framework = normalizeWhitespace(String(entry.framework ?? ""));
    return role === "assistant" && framework.length > 0;
  }).length;
  if (turnCount >= 4) {
    return forcedTransitionResponse(frameworksUsed);
  }
  const renderedPrompt = renderPrompt(taskPrompt, {
    projectId: JSON.stringify(request.data.projectId ?? ""),
    transcript: JSON.stringify(transcript),
    turnCount: JSON.stringify(turnCount),
    latestUserResponse: JSON.stringify(request.data.latestUserResponse ?? ""),
    selectedOptionIndex: JSON.stringify(request.data.selectedOptionIndex ?? null),
    draft: JSON.stringify(request.data.draft ?? {}),
    userProfile: JSON.stringify(request.data.userProfile ?? {})
  });
  const knowledgeCards = await loadKnowledgeCards();
  const retrievedCards = retrieveKnowledgeCards(knowledgeCards, {
    contextNarrative: `${JSON.stringify(transcript)}\n${String(request.data.latestUserResponse ?? "")}`,
    usageContext: String(request.data.draft?.usageContext ?? request.data.userProfile?.primaryUsage ?? "other"),
    userProfile: request.data.userProfile ?? {},
    phase: "conversation_continue",
    topK: 6
  });
  const prompt = [
    renderedPrompt,
    "",
    "RETRIEVED KNOWLEDGE CARDS (use for concise, closed-ended, non-generic questions):",
    knowledgePromptBlock(retrievedCards)
  ].join("\n");
  return guardedConversationResponse(fastModel, systemPrompt, prompt);
});

export const finalizeConversationForMatrix = onCall(aiFunctionOptions, async (request) => {
  const systemPrompt = await readPromptFile("system.txt");
  const taskPrompt = await readPromptFile("finalize_matrix_setup.txt");
  const prompt = renderPrompt(taskPrompt, {
    projectId: JSON.stringify(request.data.projectId ?? ""),
    transcript: JSON.stringify(request.data.transcript ?? []),
    draft: JSON.stringify(request.data.draft ?? {}),
    userProfile: JSON.stringify(request.data.userProfile ?? {})
  });
  const response = await askGeminiJSON(reasoningModel, systemPrompt, prompt, 0.15) as Record<string, unknown>;
  const contextBlob = JSON.stringify({
    transcript: request.data.transcript ?? [],
    draft: request.data.draft ?? {}
  });

  const decisionBriefRaw = (typeof response.decisionBrief === "object" && response.decisionBrief !== null)
    ? response.decisionBrief as Record<string, unknown>
    : {};
  const detectedOptions = sanitizeOptions(decisionBriefRaw.detectedOptions, contextBlob);
  const suggestedOptions = sanitizeOptions(response.suggestedOptions, contextBlob);

  return {
    ...response,
    decisionBrief: {
      ...decisionBriefRaw,
      detectedOptions
    },
    suggestedOptions,
    suggestedCriteria: Array.isArray(response.suggestedCriteria) ? response.suggestedCriteria : []
  };
});

type GeminiGenerateContentResponse = {
  candidates?: Array<{
    content?: {
      parts?: Array<{
        text?: string;
      }>;
    };
  }>;
};

export const extractVendorFiles = onCall(async (request) => {
  const uploads: ExtractionUploadRef[] = Array.isArray(request.data.uploadRefs) ? request.data.uploadRefs as ExtractionUploadRef[] : [];
  const items = await Promise.all(
    uploads.map(async (item) => {
      const attachmentId = String(item?.attachmentId ?? "");
      const fileName = String(item?.fileName ?? "Attachment");
      const contentType = String(item?.contentType ?? "");
      const base64 = String(item?.base64 ?? "");
      const extension = fileName.split(".").pop()?.toLowerCase() ?? "";

      if (!base64) {
        return {
          attachmentId,
          extractedText: "",
          status: "needs_review",
          titleHint: fileName,
          validationMessage: "No document bytes were provided for backend extraction."
        };
      }

      try {
        const buffer = Buffer.from(base64, "base64");
        if (extension === "docx" || contentType.includes("wordprocessingml")) {
          const result = await mammoth.extractRawText({ buffer });
          return makeExtractionItem(attachmentId, fileName, result.value, "DOCX parsed on the backend.");
        }

        if (["xlsx", "xls", "numbers"].includes(extension) || contentType.includes("spreadsheet")) {
          const workbook = XLSX.read(buffer, { type: "buffer" });
          const text = workbook.SheetNames
            .slice(0, 4)
            .map((sheetName) => {
              const sheet = workbook.Sheets[sheetName];
              const rows = XLSX.utils.sheet_to_json<string[]>(sheet, {
                header: 1,
                blankrows: false
              }) as string[][];
              const normalizedRows = rows
                .slice(0, 60)
                .map((row) => row.map((cell) => String(cell ?? "").trim()).filter(Boolean).join(" | "))
                .filter(Boolean);
              return [`Sheet: ${sheetName}`, ...normalizedRows].join("\n");
            })
            .filter(Boolean)
            .join("\n\n");
          return makeExtractionItem(attachmentId, fileName, text, "Spreadsheet parsed on the backend.");
        }

        return {
          attachmentId,
          extractedText: "",
          status: "needs_review",
          titleHint: fileName,
          validationMessage: "This file type is not handled by the Office extraction endpoint."
        };
      } catch (error) {
        return {
          attachmentId,
          extractedText: "",
          status: "needs_review",
          titleHint: fileName,
          validationMessage: error instanceof Error ? error.message : "Backend extraction failed."
        };
      }
    })
  );

  return {
    projectId: request.data.projectId,
    items
  };
});

export const exportProjectPDF = onCall(async (request) => {
  // In production: generate PDF server-side and return a signed short-lived URL.
  return {
    projectId: request.data.projectId,
    url: "https://example.com/scorewise/export-placeholder.pdf"
  };
});

function makeExtractionItem(
  attachmentId: string,
  fileName: string,
  rawText: string,
  validationMessage: string
) {
  const cleaned = rawText
    .replace(/\r/g, "\n")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .join("\n")
    .slice(0, 12000);

  return {
    attachmentId,
    extractedText: cleaned ? `Source: ${fileName}\n${cleaned}` : "",
    status: cleaned ? "ready" : "needs_review",
    titleHint: fileName,
    validationMessage: cleaned ? validationMessage : "The document was parsed, but no readable text was found."
  };
}
