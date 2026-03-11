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
const biasChallengeQuestionMaxLength = 100;

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

function unifiedContextBlob(unifiedContext: unknown): string {
  if (typeof unifiedContext !== "object" || unifiedContext === null) {
    return "";
  }
  const record = unifiedContext as Record<string, unknown>;
  const sections: string[] = [];

  const pushString = (value: unknown, label: string) => {
    if (typeof value === "string") {
      const normalized = normalizeWhitespace(value);
      if (normalized) {
        sections.push(`${label}: ${normalized}`);
      }
    }
  };
  const pushStringArray = (value: unknown, label: string) => {
    if (!Array.isArray(value)) {
      return;
    }
    const lines = value
      .filter((item): item is string => typeof item === "string")
      .map(normalizeWhitespace)
      .filter(Boolean);
    if (lines.length > 0) {
      sections.push(`${label}: ${lines.join(" | ")}`);
    }
  };

  pushString(record.decisionNarrative, "Narrative");
  pushStringArray(record.conversationTranscript, "Transcript");
  pushStringArray(record.attachmentEvidence, "AttachmentEvidence");
  pushStringArray(record.attachmentsSummary, "Attachments");
  pushStringArray(record.challengeResponsesSummary, "ChallengeResponses");

  if (Array.isArray(record.options)) {
    const options = (record.options as Array<Record<string, unknown>>)
      .map((item) => normalizeWhitespace(typeof item.label === "string" ? item.label : ""))
      .filter(Boolean);
    if (options.length > 0) {
      sections.push(`Options: ${options.join(" | ")}`);
    }
  }

  if (Array.isArray(record.criteria)) {
    const criteria = (record.criteria as Array<Record<string, unknown>>)
      .map((item) => normalizeWhitespace(typeof item.name === "string" ? item.name : ""))
      .filter(Boolean);
    if (criteria.length > 0) {
      sections.push(`Criteria: ${criteria.join(" | ")}`);
    }
  }

  if (Array.isArray(record.constraints)) {
    const constraints = (record.constraints as Array<Record<string, unknown>>)
      .map((item) => normalizeWhitespace(typeof item.rule === "string" ? item.rule : ""))
      .filter(Boolean);
    if (constraints.length > 0) {
      sections.push(`Constraints: ${constraints.join(" | ")}`);
    }
  }

  return sections.join("\n");
}

type BiasChallengeTypeID =
  | "friend_test"
  | "ten_ten_ten"
  | "pre_mortem"
  | "worst_case"
  | "inversion"
  | "inaction_cost"
  | "values_check";

type BiasChallengeItem = {
  type: BiasChallengeTypeID;
  question: string;
  response: string;
  quickPickOptions?: string[];
};

const allBiasChallengeTypes: BiasChallengeTypeID[] = [
  "friend_test",
  "ten_ten_ten",
  "pre_mortem",
  "worst_case",
  "inversion",
  "inaction_cost",
  "values_check"
];

const biasChallengeStopwords = new Set([
  "the", "and", "for", "with", "that", "this", "from", "what", "which",
  "would", "could", "should", "about", "into", "after", "before", "over",
  "under", "between", "option", "candidate", "choose", "choosing", "your",
  "their", "team", "hire", "more", "less"
]);

function normalizeBiasChallengeType(raw: string): BiasChallengeTypeID {
  const normalized = normalizeWhitespace(raw).toLowerCase().replace(/[-\s]+/g, "_");
  if ((allBiasChallengeTypes as string[]).includes(normalized)) {
    return normalized as BiasChallengeTypeID;
  }
  if (normalized === "friendtest") return "friend_test";
  if (normalized === "tententen") return "ten_ten_ten";
  if (normalized === "premortem") return "pre_mortem";
  if (normalized === "worstcase") return "worst_case";
  if (normalized === "inactioncost") return "inaction_cost";
  if (normalized === "valuescheck") return "values_check";
  return "friend_test";
}

function pickOrderedBiasChallengeTypes(userProfile: unknown): BiasChallengeTypeID[] {
  const record = (typeof userProfile === "object" && userProfile !== null)
    ? userProfile as Record<string, unknown>
    : {};
  const challenge = normalizeWhitespace(typeof record.biggestChallenge === "string" ? record.biggestChallenge : "").toLowerCase();
  switch (challenge) {
  case "overthinking":
    return ["inversion", "inaction_cost", "friend_test"];
  case "fear":
    return ["worst_case", "friend_test", "pre_mortem"];
  case "too_many_options":
    return ["values_check", "inversion", "inaction_cost"];
  default:
    return ["pre_mortem", "inversion", "values_check"];
  }
}

function extractProperNames(text: string): string[] {
  const matches = text.match(/\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,2}\b/g) ?? [];
  const blocked = new Set(["Project", "Situation", "Clarifying", "User", "Option", "Candidate"]);
  const names = matches
    .map((item) => normalizeWhitespace(item))
    .filter((item) => item.length > 1 && !blocked.has(item));
  return [...new Set(names)];
}

function extractPreferenceContrast(preferredOption: string, situationText: string, clarifyingQuestions: unknown): { preferred: string; alternative: string } {
  const preferred = normalizeWhitespace(preferredOption) || "this option";
  const inferredNames = extractProperNames(`${situationText}\n${JSON.stringify(clarifyingQuestions ?? [])}`);
  const preferredLower = preferred.toLowerCase();
  const alternatives = inferredNames.filter((item) => item.toLowerCase() !== preferredLower && !preferredLower.includes(item.toLowerCase()));
  return {
    preferred,
    alternative: alternatives[0] ?? "the alternative option"
  };
}

function extractSignalForOption(optionName: string, narrative: string, mode: "weakness" | "strength"): string | null {
  if (!optionName || !narrative) {
    return null;
  }
  const lowerName = optionName.toLowerCase();
  const lastName = lowerName.split(" ").filter(Boolean).pop() ?? lowerName;
  const weaknessSignals = ["weak", "limited", "lacks", "weaker", "slower", "less experience", "no experience", "junior", "gap"];
  const strengthSignals = ["strong", "excellent", "extensive", "built", "deployed", "led", "proven", "experienced", "fast"];
  const signals = mode === "weakness" ? weaknessSignals : strengthSignals;
  const sentences = narrative
    .split(/[\n\.!?]/g)
    .map((item) => normalizeWhitespace(item))
    .filter(Boolean);

  for (const sentence of sentences) {
    const lower = sentence.toLowerCase();
    if (!lower.includes(lowerName) && !lower.includes(lastName)) {
      continue;
    }
    if (signals.some((signal) => lower.includes(signal))) {
      return clampSingleSentence(sentence, 58);
    }
  }
  return null;
}

function challengeQuestionStem(question: string, tokenCount = 6): string {
  return normalizeWhitespace(question.toLowerCase())
    .replace(/[^a-z0-9\s]/g, " ")
    .split(" ")
    .filter(Boolean)
    .slice(0, tokenCount)
    .join(" ");
}

function buildSpecificityTokens(
  situationText: string,
  clarifyingQuestions: unknown,
  preferredOption: string
): Set<string> {
  const text = `${situationText}\n${JSON.stringify(clarifyingQuestions ?? [])}`;
  const allTokens = tokenizeForRetrieval(text).filter((token) => !biasChallengeStopwords.has(token));
  const nameTokens = new Set(tokenizeForRetrieval(preferredOption));
  const filtered = allTokens.filter((token) => !nameTokens.has(token));
  return new Set(filtered);
}

function questionSpecificityScore(question: string, specificityTokens: Set<string>): number {
  const tokens = tokenizeForRetrieval(question);
  let score = 0;
  for (const token of tokens) {
    if (specificityTokens.has(token)) {
      score += 2;
    }
  }
  if (/\d/.test(question)) {
    score += 2;
  }
  if (/(salary|visa|remote|constraint|risk|months|weeks|quarter|budget|skills?)/i.test(question)) {
    score += 1;
  }
  return score;
}

function buildFallbackBiasChallengePool(
  preferredOption: string,
  situationText: string,
  clarifyingQuestions: unknown,
  userProfile: unknown
): Record<BiasChallengeTypeID, string> {
  const profileRecord = (typeof userProfile === "object" && userProfile !== null)
    ? userProfile as Record<string, unknown>
    : {};
  const values = Array.isArray(profileRecord.valuesRanking)
    ? profileRecord.valuesRanking.filter((item): item is string => typeof item === "string")
    : [];
  const topValue = normalizeWhitespace(values[0] ?? "your top value");
  const narrative = `${situationText}\n${JSON.stringify(clarifyingQuestions ?? [])}`;
  const contrast = extractPreferenceContrast(preferredOption, situationText, clarifyingQuestions);
  const weakness = extractSignalForOption(contrast.preferred, narrative, "weakness");
  const strength = extractSignalForOption(contrast.alternative, narrative, "strength");

  return {
    friend_test: `Can you justify choosing ${contrast.preferred} over ${contrast.alternative} in one sentence?`,
    pre_mortem: weakness
      ? `${contrast.preferred}: ${weakness}. Can your team cover this in the first 6 months?`
      : `What is the likeliest reason ${contrast.preferred} fails after 6 months?`,
    inversion: strength
      ? `What do you lose by not choosing ${contrast.alternative}, given ${strength}?`
      : `Which option would you regret not choosing more, and why?`,
    worst_case: `If ${contrast.preferred} underperforms in 3 months, what is your backup plan?`,
    ten_ten_ten: `Will this choice still feel right in 1 year when early excitement fades?`,
    inaction_cost: "What happens to outcomes if you delay this decision by 2 more weeks?",
    values_check: `Does choosing ${contrast.preferred} protect ${topValue}, or only feel safer now?`
  };
}

function buildQuickPickOptions(
  type: BiasChallengeTypeID,
  preferredOption: string,
  situationText: string,
  clarifyingQuestions: unknown,
  userProfile: unknown
): string[] {
  const profileRecord = (typeof userProfile === "object" && userProfile !== null)
    ? userProfile as Record<string, unknown>
    : {};
  const values = Array.isArray(profileRecord.valuesRanking)
    ? profileRecord.valuesRanking.filter((item): item is string => typeof item === "string")
    : [];
  const topValue = normalizeWhitespace(values[0] ?? "your top value");
  const contrast = extractPreferenceContrast(preferredOption, situationText, clarifyingQuestions);
  switch (type) {
  case "friend_test":
    return [
      `I can justify ${contrast.preferred} clearly`,
      `${contrast.alternative} has a stronger case`,
      "I still need stronger evidence",
      "Both cases look equally strong"
    ];
  case "pre_mortem":
    return [
      "Main risk is capability gap",
      "Main risk is execution speed",
      "Main risk is stakeholder fit",
      "Risk is manageable with safeguards"
    ];
  case "inversion":
    return [
      `I would regret skipping ${contrast.alternative}`,
      `I would regret skipping ${contrast.preferred}`,
      "Regret risk looks balanced",
      "Regret depends on timeline"
    ];
  case "worst_case":
    return [
      "I have a clear backup plan",
      "Backup plan is weak",
      "Worst-case is acceptable",
      "Worst-case is unacceptable"
    ];
  case "ten_ten_ten":
    return [
      "Still right in one year",
      "Feels right only now",
      "Unsure after initial phase",
      "Need long-term validation"
    ];
  case "inaction_cost":
    return [
      "Delay cost is high",
      "Delay cost is moderate",
      "Delay cost is low",
      "Need data on delay impact"
    ];
  case "values_check":
    return [
      `Aligned with ${topValue}`,
      "Partially aligned with values",
      "Feels safe but misaligned",
      "Value alignment is unclear"
    ];
  default:
    return [
      "Need one more data point",
      "Current direction is still valid",
      "Risk feels higher than expected",
      "Tie remains unresolved"
    ];
  }
}

function normalizeBiasChallengeQuestion(question: string): string {
  return clampSingleSentence(question, biasChallengeQuestionMaxLength);
}

function sanitizeBiasChallengeItems(
  rawChallenges: unknown,
  preferredOption: string,
  situationText: string,
  clarifyingQuestions: unknown,
  userProfile: unknown
): BiasChallengeItem[] {
  const fallbackPool = buildFallbackBiasChallengePool(preferredOption, situationText, clarifyingQuestions, userProfile);
  const preferredOrder = pickOrderedBiasChallengeTypes(userProfile);
  const preferredSet = new Set(preferredOrder);
  const fillOrder = [...preferredOrder, ...allBiasChallengeTypes.filter((type) => !preferredSet.has(type))];
  const specificityTokens = buildSpecificityTokens(situationText, clarifyingQuestions, preferredOption);
  const parsed = Array.isArray(rawChallenges) ? rawChallenges as Array<Record<string, unknown>> : [];

  const accepted: BiasChallengeItem[] = [];
  const usedTypes = new Set<BiasChallengeTypeID>();
  const usedStems = new Set<string>();
  let imagineUsed = 0;

  for (const item of parsed) {
    const type = normalizeBiasChallengeType(typeof item.type === "string" ? item.type : "friend_test");
    if (usedTypes.has(type)) {
      continue;
    }
    const question = normalizeBiasChallengeQuestion(typeof item.question === "string" ? item.question : "");
    if (!question) {
      continue;
    }
    const stem = challengeQuestionStem(question);
    if (!stem || usedStems.has(stem)) {
      continue;
    }
    const startsWithImagine = /^imagine\b/i.test(question);
    if (startsWithImagine && imagineUsed >= 1) {
      continue;
    }
    const specificity = questionSpecificityScore(question, specificityTokens);
    if (specificity < 1) {
      continue;
    }
    usedTypes.add(type);
    usedStems.add(stem);
    if (startsWithImagine) {
      imagineUsed += 1;
    }
    accepted.push({
      type,
      question,
      response: typeof item.response === "string" ? item.response : "",
      quickPickOptions: buildQuickPickOptions(type, preferredOption, situationText, clarifyingQuestions, userProfile)
        .map((item) => clampWords(item, 15))
        .filter(Boolean)
        .slice(0, 5)
    });
    if (accepted.length >= 3) {
      break;
    }
  }

  for (const type of fillOrder) {
    if (accepted.length >= 3) {
      break;
    }
    if (usedTypes.has(type)) {
      continue;
    }
    const question = normalizeBiasChallengeQuestion(fallbackPool[type]);
    if (!question) {
      continue;
    }
    const stem = challengeQuestionStem(question);
    if (!stem || usedStems.has(stem)) {
      continue;
    }
    const startsWithImagine = /^imagine\b/i.test(question);
    if (startsWithImagine && imagineUsed >= 1) {
      continue;
    }
    usedTypes.add(type);
    usedStems.add(stem);
    if (startsWithImagine) {
      imagineUsed += 1;
    }
    accepted.push({
      type,
      question,
      response: "",
      quickPickOptions: buildQuickPickOptions(type, preferredOption, situationText, clarifyingQuestions, userProfile)
        .map((item) => clampWords(item, 15))
        .filter(Boolean)
        .slice(0, 5)
    });
  }

  return accepted.slice(0, 3);
}

function shouldRepairBiasChallenges(
  rawChallenges: unknown,
  sanitized: BiasChallengeItem[],
  preferredOption: string,
  situationText: string,
  clarifyingQuestions: unknown
): boolean {
  if (sanitized.length < 3) {
    return true;
  }
  const specificityTokens = buildSpecificityTokens(situationText, clarifyingQuestions, preferredOption);
  const specificCount = sanitized.filter((item) => questionSpecificityScore(item.question, specificityTokens) >= 1).length;
  if (specificCount < 2) {
    return true;
  }
  const parsed = Array.isArray(rawChallenges) ? rawChallenges as Array<Record<string, unknown>> : [];
  if (parsed.length < 3) {
    return true;
  }
  return false;
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

function enforceReassuranceContent(content: string, citations: EvidenceCitation[]): string {
  const compact = normalizeWhitespace(content);
  const hasSections = compact.includes("Reassurance now") &&
    compact.includes("Why this still holds") &&
    compact.includes("What could invalidate it") &&
    compact.includes("Concrete next action in 48 hours");
  if (hasSections) {
    return content.trim();
  }
  if (citations.length > 0) {
    return [
      "Reassurance now",
      compact || "Your reasoning is solid enough to move forward with one controlled validation.",
      "",
      "Why this still holds",
      "The current top option still aligns with your weighted criteria and constraints.",
      "",
      "What could invalidate it",
      "A single high-impact assumption could flip the decision if new evidence contradicts it.",
      "",
      "Concrete next action in 48 hours",
      "Run one targeted validation step and decide on a fixed deadline."
    ].join("\n");
  }
  return [
    "Reassurance now",
    "Current reassurance is provisional because evidence support is limited.",
    "",
    "Why this still holds",
    "The direction is plausible, but it needs stronger validation from your sources.",
    "",
    "What could invalidate it",
    "Unverified assumptions may change the winner.",
    "",
    "Concrete next action in 48 hours",
    "Add one concrete evidence source and regenerate reassurance."
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
const genericConversationQuestionPatterns = [
  /tell me more/i,
  /share more/i,
  /more context/i,
  /^what do you think/i,
  /^how do you feel/i
];

function isGenericQuestionText(question: string): boolean {
  const normalized = normalizeWhitespace(question).toLowerCase();
  if (!normalized) {
    return true;
  }
  if (genericConversationQuestionPatterns.some((pattern) => pattern.test(normalized))) {
    return true;
  }
  return normalized.startsWith("what else") ||
    normalized.startsWith("anything else") ||
    normalized.includes("any additional details");
}

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
  if (genericConversationQuestionPatterns.some((pattern) => pattern.test(payload.message.content))) {
    return true;
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
  const { projectId, vendors, extractedText, usageContext, contextNarrative, userProfile, unifiedContext } = request.data;
  const unifiedBlob = unifiedContextBlob(unifiedContext);
  const knowledgeCards = await loadKnowledgeCards();
  const retrievedCards = retrieveKnowledgeCards(knowledgeCards, {
    contextNarrative: `${String(contextNarrative ?? "")}\n${unifiedBlob}`,
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
    `Unified context: ${unifiedBlob}`,
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
  const { projectId, situationText, userProfile, unifiedContext } = request.data;
  const unifiedBlob = unifiedContextBlob(unifiedContext);
  const knowledgeCards = await loadKnowledgeCards();
  const retrievedCards = retrieveKnowledgeCards(knowledgeCards, {
    contextNarrative: `${String(situationText ?? "")}\n${unifiedBlob}`,
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
    `Unified context: ${unifiedBlob}`,
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
  const toQuestions = (rawPayload: unknown) => {
    const payload = (typeof rawPayload === "object" && rawPayload !== null) ? rawPayload as Record<string, unknown> : {};
    const shared = parseCitations(payload.citations, retrievedCards, "question");
    const questionItems = Array.isArray(payload.questions) ? payload.questions : [];
    const items = questionItems.map((item) => {
      if (typeof item === "string") {
        return {
          question: clampSingleSentence(item, 140),
          answer: "",
          citations: shared
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
    return { questions: items, citations: shared };
  };

  let parsed = toQuestions(payloadRaw);
  const needsRepair = parsed.questions.length < 6 || parsed.questions.some((item) => isGenericQuestionText(item.question));
  if (needsRepair) {
    const repairPrompt = [
      prompt,
      "",
      "REPAIR INSTRUCTION:",
      "- Replace generic questions with situation-specific, closed-ended questions.",
      "- Every question must reference at least one concrete fact from the situation or unified context.",
      "- Keep one sentence per question.",
      "Previous output JSON:",
      JSON.stringify(payloadRaw)
    ].join("\n");
    const repairedPayload = await askGeminiJSON(reasoningModel, systemPrompt, repairPrompt, 0.12);
    const repaired = toQuestions(repairedPayload);
    if (repaired.questions.length >= parsed.questions.length) {
      parsed = repaired;
    }
  }

  return {
    questions: parsed.questions,
    citations: parsed.citations
  };
});

export const suggestDecisionOptions = onCall(aiFunctionOptions, async (request) => {
  const systemPrompt = await readPromptFile("system.txt");
  const { projectId, situationText, clarifyingQuestions, userProfile, unifiedContext } = request.data;
  const unifiedBlob = unifiedContextBlob(unifiedContext);
  const contextBlob = JSON.stringify({
    situationText: situationText ?? "",
    clarifyingQuestions: clarifyingQuestions ?? [],
    unifiedContext: unifiedBlob
  });
  const prompt = [
    `Project: ${projectId}`,
    `Situation: ${situationText ?? ""}`,
    `Unified context: ${unifiedBlob}`,
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
  const {
    projectId,
    preferredOption,
    situationText,
    clarifyingQuestions,
    userProfile,
    unifiedContext,
    challengeResponsesSummary
  } = request.data;
  const preferred = String(preferredOption ?? "");
  const situation = String(situationText ?? "");
  const unifiedBlob = unifiedContextBlob(unifiedContext);
  const clarifying = clarifyingQuestions ?? [];
  const prompt = [
    `Project: ${projectId}`,
    `Situation: ${situation}`,
    `Unified context: ${unifiedBlob}`,
    `Clarifying answers: ${JSON.stringify(clarifying)}`,
    `Previous challenge responses: ${JSON.stringify(challengeResponsesSummary ?? [])}`,
    `Apparent preference: ${preferred}`,
    `User profile: ${JSON.stringify(userProfile ?? {})}`,
    "",
    "Generate exactly 3 bias challenge questions. Each must:",
    "1. Use a DIFFERENT exercise type (never repeat the same type)",
    "2. Reference SPECIFIC facts from the situation (strengths, weaknesses, numbers, constraints — not just names)",
    "3. Force a concrete trade-off or risk assessment, not vague reflection",
    "4. Be ONE sentence, max 100 characters",
    "5. NOT start with 'Imagine' for more than one question",
    "",
    "GOOD examples (specific, forces trade-off):",
    '- "Sara has weak data skills — can your team absorb that gap in the first 6 months?"',
    '- "If Omar leaves after 1 year for a bigger company, was the hire still worth it?"',
    '- "Which candidate would you regret NOT hiring more — and why?"',
    "",
    "BAD examples (vague, templated):",
    '- "Imagine this hire fails; what specific actions led to that outcome for Sara"',
    '- "How will choosing Sara feel in 10 minutes, 10 months, 10 years?"',
    "",
    "Exercise types to choose from: friend_test, ten_ten_ten, pre_mortem, worst_case, inversion, inaction_cost, values_check",
    "",
    "Personalization rules:",
    "- If user challenge is overthinking → use inversion + inaction_cost + one other",
    "- If user challenge is fear → use worst_case + friend_test + one other",
    "- If user challenge is too_many_options → use values_check + inversion + one other",
    "Return JSON only in this shape:",
    '{ "challenges": [{"type":"friend_test", "question":"...", "response": ""}] }'
  ].join("\n");

  const firstPayload = await askGeminiJSON(fastModel, systemPrompt, prompt, 0.2);
  const firstRawChallenges = (typeof firstPayload === "object" && firstPayload !== null)
    ? (firstPayload as Record<string, unknown>).challenges
    : [];
  const firstSanitized = sanitizeBiasChallengeItems(
    firstRawChallenges,
    preferred,
    `${situation}\n${unifiedBlob}`,
    clarifying,
    userProfile
  );
  if (!shouldRepairBiasChallenges(firstRawChallenges, firstSanitized, preferred, `${situation}\n${unifiedBlob}`, clarifying)) {
    return firstSanitized;
  }

  const repairPrompt = [
    prompt,
    "",
    "REPAIR INSTRUCTION:",
    "- Your previous output was repetitive or not specific enough.",
    "- Return 3 challenges with unique types, unique sentence stems, and specific facts.",
    "- Ensure at least two questions reference constraints, strengths, weaknesses, numbers, or timeline.",
    "- Keep every question one sentence and max 100 characters.",
    "Previous output JSON:",
    JSON.stringify(firstPayload)
  ].join("\n");
  const repairedPayload = await askGeminiJSON(reasoningModel, systemPrompt, repairPrompt, 0.12);
  const repairedRawChallenges = (typeof repairedPayload === "object" && repairedPayload !== null)
    ? (repairedPayload as Record<string, unknown>).challenges
    : [];
  return sanitizeBiasChallengeItems(
    repairedRawChallenges,
    preferred,
    `${situation}\n${unifiedBlob}`,
    clarifying,
    userProfile
  );
});

export const decisionChat = onCall(aiFunctionOptions, async (request) => {
  const systemPrompt = await readPromptFile("system.txt");
  const { projectId, phase, message, draft, userProfile, unifiedContext, attachmentsSummary, challengeResponsesSummary } = request.data;
  const reassuranceMode = phase === "post_challenge_reassurance";
  const unifiedBlob = unifiedContextBlob(unifiedContext);
  const knowledgeCards = await loadKnowledgeCards();
  const usageHint = typeof draft?.usageContext === "string"
    ? draft.usageContext
    : (typeof userProfile?.primaryUsage === "string" ? userProfile.primaryUsage : "other");
  const retrievedCards = retrieveKnowledgeCards(knowledgeCards, {
    contextNarrative: `${String(message ?? "")}\n${JSON.stringify(draft ?? {})}\n${unifiedBlob}`,
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
    `Unified context: ${unifiedBlob}`,
    `Attachments summary: ${JSON.stringify(attachmentsSummary ?? [])}`,
    `Challenge responses summary: ${JSON.stringify(challengeResponsesSummary ?? [])}`,
    `User profile: ${JSON.stringify(userProfile ?? {})}`,
    "",
    "RETRIEVED KNOWLEDGE CARDS (use and cite these sources):",
    knowledgeBlock,
    "PHASE BEHAVIOR:",
    reassuranceMode
      ? "- Post-challenge reassurance: validate emotion, restate trade-off reality, and give stabilizing next action with concrete 48-hour action."
      : "- If critical context is missing, ask one high-leverage closed-ended question before advice.",
    "- Keep response concise and concrete.",
    "- No generic filler language.",
    "- Preserve explicit names; no placeholders.",
    "- Cite at least one knowledge card in recommendation/risk sections.",
    "- If evidence support is weak, explicitly lower confidence.",
    "- End with either a question OR an action, not both.",
    "Return JSON only:",
    '{ "content": "", "recommendedActions": [""], "citations": [{"cardId":"", "sourceLabel":"", "usedFor":"recommendation"}] }',
    reassuranceMode
      ? "For post_challenge_reassurance phase, content must follow exactly: Reassurance now / Why this still holds / What could invalidate it / Concrete next action in 48 hours."
      : "For analysis/results/follow_up_delta phases, content must follow exactly: Recommendation / Why this option leads / Risks to consider / Confidence level / Next step."
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
      ? (reassuranceMode
          ? enforceReassuranceContent(rawContent, citations)
          : enforceCitationAwareStructuredContent(rawContent, citations))
      : (rawContent.trim() || "I need more context to give a grounded answer."),
    recommendedActions,
    citations
  };
});

type NormalizedInsightPayload = {
  summary: string;
  winnerReasoning: string;
  riskFlags: string[];
  overlookedStrategicPoints: string[];
  sensitivityFindings: string[];
  drivers: string[];
  confidenceLabel: string;
  nextStep: string;
};

const genericInsightPhrases = [
  "weak or sparse evidence",
  "validate the top uncertainty",
  "small weight changes can flip",
  "currently leading",
  "confidence is limited by weak or sparse evidence"
];

function parseInsightLineList(raw: unknown): string[] {
  if (!Array.isArray(raw)) {
    return [];
  }
  return raw
    .filter((item): item is string => typeof item === "string")
    .map(normalizeWhitespace)
    .filter(Boolean);
}

function extractInsightNames(draft: unknown, result: unknown): { criteriaNames: string[]; optionNames: string[] } {
  const draftRecord = (typeof draft === "object" && draft !== null) ? draft as Record<string, unknown> : {};
  const resultRecord = (typeof result === "object" && result !== null) ? result as Record<string, unknown> : {};
  const criteriaNames = Array.isArray(draftRecord.criteria)
    ? (draftRecord.criteria as Array<Record<string, unknown>>)
      .map((item) => normalizeWhitespace(typeof item.name === "string" ? item.name : ""))
      .filter(Boolean)
    : [];
  const optionNamesFromResult = Array.isArray(resultRecord.rankedVendors)
    ? (resultRecord.rankedVendors as Array<Record<string, unknown>>)
      .map((item) => normalizeWhitespace(typeof item.vendorName === "string" ? item.vendorName : ""))
      .filter(Boolean)
    : [];
  const optionNamesFromDraft = Array.isArray(draftRecord.vendors)
    ? (draftRecord.vendors as Array<Record<string, unknown>>)
      .map((item) => normalizeWhitespace(typeof item.name === "string" ? item.name : ""))
      .filter(Boolean)
    : [];
  const optionNames = [...new Set([...optionNamesFromResult, ...optionNamesFromDraft])];
  return { criteriaNames, optionNames };
}

function containsGenericInsightPhrase(text: string): boolean {
  const lower = normalizeWhitespace(text).toLowerCase();
  return genericInsightPhrases.some((phrase) => lower.includes(phrase));
}

function mentionsAny(text: string, terms: string[]): boolean {
  const lower = normalizeWhitespace(text).toLowerCase();
  return terms
    .map((item) => normalizeWhitespace(item).toLowerCase())
    .filter((item) => item.length >= 3)
    .some((item) => lower.includes(item));
}

function inferInsightConfidenceLabel(payload: NormalizedInsightPayload): string {
  if (payload.confidenceLabel) {
    return payload.confidenceLabel;
  }
  const blob = [
    payload.summary,
    payload.winnerReasoning,
    ...payload.riskFlags,
    ...payload.sensitivityFindings
  ].join(" ").toLowerCase();
  if (blob.includes("low confidence") || blob.includes("near tie") || blob.includes("winner can flip")) {
    return "Low";
  }
  if (blob.includes("high confidence") || blob.includes("stable lead")) {
    return "High";
  }
  return "Medium";
}

function normalizeInsightPayload(raw: unknown): NormalizedInsightPayload {
  const record = (typeof raw === "object" && raw !== null) ? raw as Record<string, unknown> : {};
  const summary = normalizeWhitespace(typeof record.summary === "string" ? record.summary : "");
  const winnerReasoning = normalizeWhitespace(typeof record.winnerReasoning === "string" ? record.winnerReasoning : "");
  const riskFlags = parseInsightLineList(record.riskFlags);
  const overlookedStrategicPoints = parseInsightLineList(record.overlookedStrategicPoints);
  const sensitivityFindings = parseInsightLineList(record.sensitivityFindings);
  const drivers = parseInsightLineList(record.drivers);
  const confidenceLabel = normalizeWhitespace(typeof record.confidenceLabel === "string" ? record.confidenceLabel : "");
  const nextStep = normalizeWhitespace(typeof record.nextStep === "string" ? record.nextStep : (overlookedStrategicPoints[0] ?? ""));

  return {
    summary,
    winnerReasoning,
    riskFlags,
    overlookedStrategicPoints,
    sensitivityFindings,
    drivers,
    confidenceLabel,
    nextStep
  };
}

function validateInsightPayload(
  payload: NormalizedInsightPayload,
  criteriaNames: string[],
  optionNames: string[]
): { needsRepair: boolean; reasons: string[] } {
  const reasons: string[] = [];
  const narrativeBlob = [
    payload.summary,
    payload.winnerReasoning,
    ...payload.riskFlags,
    ...payload.sensitivityFindings
  ].join(" ");

  if (!payload.winnerReasoning) {
    reasons.push("winnerReasoning is empty.");
  }
  if (containsGenericInsightPhrase(narrativeBlob)) {
    reasons.push("response contains banned generic phrasing.");
  }
  if (payload.riskFlags.length === 0) {
    reasons.push("riskFlags is empty.");
  }
  if (criteriaNames.length > 0 && !mentionsAny(narrativeBlob, criteriaNames)) {
    reasons.push("analysis does not reference any criterion names.");
  }
  if (optionNames.length > 0 && !mentionsAny(`${payload.winnerReasoning} ${payload.riskFlags.join(" ")}`, optionNames)) {
    reasons.push("analysis does not reference explicit option names.");
  }
  if (!payload.nextStep || !/(run|schedule|request|verify|pilot|negotiate|test|check|review|compare|interview)/i.test(payload.nextStep)) {
    reasons.push("next step is not concrete enough.");
  }

  return {
    needsRepair: reasons.length > 0,
    reasons
  };
}

function defaultNextStepForContext(usageContext: string): string {
  const lower = usageContext.toLowerCase();
  if (lower.includes("recruit") || lower.includes("candidate") || lower.includes("hire")) {
    return "Run a structured trial task and one reference check before finalizing.";
  }
  if (lower.includes("career") || lower.includes("offer") || lower.includes("job")) {
    return "Schedule a compensation and scope validation call this week before deciding.";
  }
  if (lower.includes("business") || lower.includes("vendor") || lower.includes("work")) {
    return "Run a short pilot on the highest-risk criterion before committing.";
  }
  return "Run one targeted validation step this week, then finalize the decision.";
}

function ensureInsightMinimum(
  payload: NormalizedInsightPayload,
  criteriaNames: string[],
  optionNames: string[],
  usageContext: string
): NormalizedInsightPayload {
  const winner = optionNames[0] ?? "the current top option";
  const criterion = criteriaNames[0] ?? "the highest-weighted criterion";
  const fallbackRisk = `If ${criterion.toLowerCase()} assumptions change, the winner can flip.`;
  const drivers = payload.drivers.length > 0
    ? payload.drivers
    : criteriaNames.slice(0, 3).map((name) => `${name} is materially influencing the current ranking.`);

  const winnerReasoning = payload.winnerReasoning
    ? payload.winnerReasoning
    : `${winner} is favored because it performs better on ${criterion}.`;

  const riskFlags = payload.riskFlags.length > 0
    ? payload.riskFlags.map((item) => containsGenericInsightPhrase(item) ? fallbackRisk : item)
    : [fallbackRisk];

  const sensitivityFindings = payload.sensitivityFindings.length > 0
    ? payload.sensitivityFindings
    : [`Sensitivity check: if ${criterion.toLowerCase()} is reweighted, the winner may change.`];

  const nextStep = payload.nextStep || payload.overlookedStrategicPoints[0] || defaultNextStepForContext(usageContext);

  const summary = payload.summary || `Current outcome favors ${winner}, but depends heavily on ${criterion}.`;

  return {
    summary,
    winnerReasoning,
    riskFlags: riskFlags.slice(0, 4),
    overlookedStrategicPoints: (payload.overlookedStrategicPoints.length > 0 ? payload.overlookedStrategicPoints : [nextStep]).slice(0, 3),
    sensitivityFindings: sensitivityFindings.slice(0, 4),
    drivers: drivers.slice(0, 4),
    confidenceLabel: inferInsightConfidenceLabel(payload),
    nextStep
  };
}

export const generateInsights = onCall(aiFunctionOptions, async (request) => {
  const systemPrompt = await readPromptFile("system.txt");
  const { projectId, draft, result, userProfile, unifiedContext, attachmentsSummary, challengeResponsesSummary } = request.data;
  const unifiedBlob = unifiedContextBlob(unifiedContext);
  const usageContext = String((draft as Record<string, unknown> | undefined)?.usageContext ?? userProfile?.primaryUsage ?? "other");
  const knowledgeCards = await loadKnowledgeCards();
  const retrievedCards = retrieveKnowledgeCards(knowledgeCards, {
    contextNarrative: `${JSON.stringify(draft ?? {})}\n${JSON.stringify(result ?? {})}\n${unifiedBlob}`,
    usageContext,
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
    `Unified context: ${unifiedBlob}`,
    `Attachments summary: ${JSON.stringify(attachmentsSummary ?? [])}`,
    `Challenge responses summary: ${JSON.stringify(challengeResponsesSummary ?? [])}`,
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
    "CRITICAL RULES:",
    "- winnerReasoning must explain WHY the option leads on named criteria; never use generic winner text.",
    "- riskFlags must reference specific criteria names and potential score/weight flip conditions.",
    "- overlookedStrategicPoints and nextStep must be concrete actions specific to decision type.",
    "- sensitivityFindings must name a criterion that could flip the winner.",
    "- NEVER use these phrases: 'weak or sparse evidence', 'validate the top uncertainty', 'small weight changes can flip', 'currently leading'.",
    "- Preserve explicit option names exactly as provided.",
    "",
    "Return JSON only:",
    "{",
    '  "summary":"",',
    '  "winnerReasoning":"",',
    '  "riskFlags":[""],',
    '  "overlookedStrategicPoints":[""],',
    '  "sensitivityFindings":[""],',
    '  "drivers":[""],',
    '  "confidenceLabel":"Low|Medium|High",',
    '  "nextStep":"",',
    '  "citations":[{"cardId":"", "sourceLabel":"", "usedFor":"risk"}]',
    "}",
    "Constraints:",
    "- winnerReasoning must preserve explicit names and avoid placeholders.",
    "- summary should be concise and decision-driving.",
    "- riskFlags and sensitivityFindings should highlight potential flips/uncertainty.",
    "- include at least one citation; if support is weak, explicitly state low confidence."
  ].join("\n");

  const { criteriaNames, optionNames } = extractInsightNames(draft, result);
  const firstRawPayload = await askGeminiJSON(reasoningModel, systemPrompt, prompt, 0.2);
  const firstNormalized = normalizeInsightPayload(firstRawPayload);
  const firstValidation = validateInsightPayload(firstNormalized, criteriaNames, optionNames);

  let finalPayload = firstNormalized;
  let finalRawPayload: unknown = firstRawPayload;
  if (firstValidation.needsRepair) {
    const repairPrompt = [
      prompt,
      "",
      "REPAIR INSTRUCTION:",
      "- Rewrite to remove generic phrasing and tie claims to concrete criteria and options.",
      "- Ensure nextStep is concrete and actionable for this decision type.",
      "- Ensure riskFlags and sensitivityFindings include named criterion flip logic.",
      `Repair reasons: ${firstValidation.reasons.join(" | ")}`,
      "Previous output JSON:",
      JSON.stringify(firstRawPayload)
    ].join("\n");
    const repairedRawPayload = await askGeminiJSON(reasoningModel, systemPrompt, repairPrompt, 0.12);
    finalRawPayload = repairedRawPayload;
    finalPayload = normalizeInsightPayload(repairedRawPayload);
  }

  const citations = parseCitations(
    (typeof finalRawPayload === "object" && finalRawPayload !== null)
      ? (finalRawPayload as Record<string, unknown>).citations
      : undefined,
    retrievedCards,
    "risk"
  );
  const ensured = ensureInsightMinimum(finalPayload, criteriaNames, optionNames, usageContext);

  return {
    summary: ensured.summary || "Evidence support is limited; treat current winner as provisional.",
    winnerReasoning: ensured.winnerReasoning,
    riskFlags: citations.length > 0
      ? ensured.riskFlags
      : [...ensured.riskFlags, "Evidence support is limited; confidence is low until more validated inputs are added."],
    overlookedStrategicPoints: ensured.overlookedStrategicPoints,
    sensitivityFindings: ensured.sensitivityFindings,
    drivers: ensured.drivers,
    confidenceLabel: ensured.confidenceLabel,
    nextStep: ensured.nextStep,
    citations
  };
});

export const startDecisionConversation = onCall(aiFunctionOptions, async (request) => {
  const systemPrompt = await readPromptFile("system.txt");
  const taskPrompt = await readPromptFile("start_conversation.txt");
  const unifiedBlob = unifiedContextBlob(request.data.unifiedContext);
  const renderedPrompt = renderPrompt(taskPrompt, {
    projectId: JSON.stringify(request.data.projectId ?? ""),
    contextNarrative: JSON.stringify(request.data.contextNarrative ?? ""),
    usageContext: JSON.stringify(request.data.usageContext ?? ""),
    userProfile: JSON.stringify(request.data.userProfile ?? {}),
    unifiedContext: JSON.stringify(request.data.unifiedContext ?? {})
  });
  const knowledgeCards = await loadKnowledgeCards();
  const retrievedCards = retrieveKnowledgeCards(knowledgeCards, {
    contextNarrative: `${String(request.data.contextNarrative ?? "")}\n${unifiedBlob}`,
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
  const unifiedBlob = unifiedContextBlob(request.data.unifiedContext);
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
    userProfile: JSON.stringify(request.data.userProfile ?? {}),
    unifiedContext: JSON.stringify(request.data.unifiedContext ?? {})
  });
  const knowledgeCards = await loadKnowledgeCards();
  const retrievedCards = retrieveKnowledgeCards(knowledgeCards, {
    contextNarrative: `${JSON.stringify(transcript)}\n${String(request.data.latestUserResponse ?? "")}\n${unifiedBlob}`,
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
  const unifiedBlob = unifiedContextBlob(request.data.unifiedContext);
  const prompt = renderPrompt(taskPrompt, {
    projectId: JSON.stringify(request.data.projectId ?? ""),
    transcript: JSON.stringify(request.data.transcript ?? []),
    draft: JSON.stringify(request.data.draft ?? {}),
    userProfile: JSON.stringify(request.data.userProfile ?? {}),
    unifiedContext: JSON.stringify(request.data.unifiedContext ?? {})
  });
  const response = await askGeminiJSON(reasoningModel, systemPrompt, prompt, 0.15) as Record<string, unknown>;
  const contextBlob = JSON.stringify({
    transcript: request.data.transcript ?? [],
    draft: request.data.draft ?? {},
    unifiedContext: unifiedBlob
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
