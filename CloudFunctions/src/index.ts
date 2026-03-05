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

const aiFunctionOptions = {
  secrets: [geminiApiKey]
};

export const suggestRankingInputs = onCall(aiFunctionOptions, async (request) => {
  const systemPrompt = await readPromptFile("system.txt");
  const { projectId, vendors, extractedText, usageContext, contextNarrative, userProfile } = request.data;
  const optionSummary = Array.isArray(vendors)
    ? vendors.map((vendor: Record<string, unknown>) => `${String(vendor.id ?? "")}:${String(vendor.name ?? "")}`).join(" | ")
    : "";
  const prompt = [
    "You are constructing a weighted decision matrix for this specific case.",
    `Project: ${projectId ?? ""}`,
    `Situation: ${contextNarrative ?? ""}`,
    `Usage context: ${usageContext ?? "unknown"}`,
    `Options: ${optionSummary}`,
    `User profile: ${JSON.stringify(userProfile ?? {})}`,
    `Evidence: ${JSON.stringify(extractedText ?? [])}`,
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
    "- Keep evidenceSnippet concrete and tied to provided context.",
    "",
    "Return valid JSON only with this exact shape:",
    "{",
    '  "criteria": [{"name":"", "detail":"", "category":"", "weightPercent":0}],',
    '  "draftScores": [{"vendorID":"", "criterionID":"", "score":0, "confidence":0, "evidenceSnippet":""}],',
    '  "methodNotes": [""]',
    "}",
    "Constraints: weights total exactly 100, confidence range 0-1, no placeholder names."
  ].join("\n");

  return askGeminiJSON(fastModel, systemPrompt, prompt, 0.15);
});

export const generateClarifyingQuestions = onCall(aiFunctionOptions, async (request) => {
  const systemPrompt = await readPromptFile("system.txt");
  const { projectId, situationText, userProfile } = request.data;
  const prompt = [
    "Generate clarifying questions that directly improve decision quality.",
    `Project: ${projectId ?? ""}`,
    `Situation: ${situationText ?? ""}`,
    `User profile: ${JSON.stringify(userProfile ?? {})}`,
    "Requirements:",
    "- Produce 6-12 questions.",
    "- Closed-ended only: yes/no, fixed choice, numeric range, or short scale.",
    "- At least one question about hard constraints.",
    "- At least one question about risk tolerance.",
    "- At least one question about hidden stakeholders or second-order effects.",
    "- No generic filler prompts (e.g., 'tell me more').",
    "- One sentence per question.",
    "Return JSON only in this shape:",
    '{ "questions": [""] }'
  ].join("\n");

  const payload = await askGeminiJSON(fastModel, systemPrompt, prompt, 0.2);
  return payload.questions ?? [];
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
  const prompt = [
    `Project: ${projectId}`,
    `Phase: ${phase}`,
    `User message: ${message}`,
    `Draft context: ${JSON.stringify(draft ?? {})}`,
    `User profile: ${JSON.stringify(userProfile ?? {})}`,
    "PHASE BEHAVIOR:",
    reassuranceMode
      ? "- Post-challenge reassurance: validate emotion, restate trade-off reality, and give stabilizing next action."
      : "- If critical context is missing, ask one high-leverage closed-ended question before advice.",
    "- Keep response concise and concrete.",
    "- No generic filler language.",
    "- Preserve explicit names; no placeholders.",
    "- End with either a question OR an action, not both.",
    "Return JSON only:",
    '{ "content": "", "recommendedActions": [""] }',
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
  const shouldStructure = reassuranceMode || phase === "analysis" || phase === "results";

  return {
    content: shouldStructure ? enforceStructuredContent(rawContent) : (rawContent.trim() || "I need more context to give a grounded answer."),
    recommendedActions
  };
});

export const generateInsights = onCall(aiFunctionOptions, async (request) => {
  const systemPrompt = await readPromptFile("system.txt");
  const { projectId, draft, result, userProfile } = request.data;
  const prompt = [
    "Generate a structured post-decision insight report.",
    `Project: ${projectId}`,
    `Draft payload: ${JSON.stringify(draft)}`,
    `Result payload: ${JSON.stringify(result)}`,
    `User profile: ${JSON.stringify(userProfile ?? {})}`,
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
    '  "sensitivityFindings":[""]',
    "}",
    "Constraints:",
    "- winnerReasoning must preserve explicit names and avoid placeholders.",
    "- summary should be concise and decision-driving.",
    "- riskFlags and sensitivityFindings should highlight potential flips/uncertainty."
  ].join("\n");

  return askGeminiJSON(reasoningModel, systemPrompt, prompt, 0.2);
});

export const startDecisionConversation = onCall(aiFunctionOptions, async (request) => {
  const systemPrompt = await readPromptFile("system.txt");
  const taskPrompt = await readPromptFile("start_conversation.txt");
  const prompt = renderPrompt(taskPrompt, {
    projectId: JSON.stringify(request.data.projectId ?? ""),
    contextNarrative: JSON.stringify(request.data.contextNarrative ?? ""),
    usageContext: JSON.stringify(request.data.usageContext ?? ""),
    userProfile: JSON.stringify(request.data.userProfile ?? {})
  });
  return askGeminiJSON(fastModel, systemPrompt, prompt, 0.2);
});

export const continueDecisionConversation = onCall(aiFunctionOptions, async (request) => {
  const systemPrompt = await readPromptFile("system.txt");
  const taskPrompt = await readPromptFile("continue_conversation.txt");
  const prompt = renderPrompt(taskPrompt, {
    projectId: JSON.stringify(request.data.projectId ?? ""),
    transcript: JSON.stringify(request.data.transcript ?? []),
    latestUserResponse: JSON.stringify(request.data.latestUserResponse ?? ""),
    selectedOptionIndex: JSON.stringify(request.data.selectedOptionIndex ?? null),
    draft: JSON.stringify(request.data.draft ?? {}),
    userProfile: JSON.stringify(request.data.userProfile ?? {})
  });
  return askGeminiJSON(fastModel, systemPrompt, prompt, 0.2);
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
