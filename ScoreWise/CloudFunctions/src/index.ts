import * as admin from "firebase-admin";
import { onCall } from "firebase-functions/v2/https";
import OpenAI from "openai";

admin.initializeApp();

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

const DECISION_SYSTEM_PROMPT = [
  "You are ScoreWise AI, a decision-science copilot.",
  "Your job is to reduce bias and ambiguity using measurable criteria.",
  "Rules:",
  "1) Keep outputs evidence-aware and concrete.",
  "2) Ask for missing information if certainty is weak.",
  "3) Criteria must be non-overlapping and evaluable.",
  "4) Weights must sum to exactly 100.",
  "5) Include uncertainty and review flags."
].join("\n");

export const suggestRankingInputs = onCall(async (request) => {
  const { projectId, vendors, extractedText, usageContext, contextNarrative } = request.data;
  const prompt = [
    `Project: ${projectId}`,
    `Usage context: ${usageContext}`,
    `User brief/transcript: ${contextNarrative ?? ""}`,
    `Vendors: ${JSON.stringify(vendors)}`,
    `Extracted evidence chunks: ${JSON.stringify(extractedText)}`,
    "Output valid JSON only with:",
    "{",
    '  "criteria": [{"name":"", "detail":"", "category":"", "weightPercent":0}],',
    '  "draftScores": [{"vendorID":"", "criterionID":"", "score":0, "confidence":0, "evidenceSnippet":""}],',
    '  "methodNotes": [""]',
    "}",
    "Constraints: 3-20 criteria, score scale 1-10, confidence 0-1, weights total exactly 100."
  ].join("\n");

  const completion = await openai.chat.completions.create({
    model: "gpt-4.1-mini",
    temperature: 0.15,
    response_format: { type: "json_object" },
    messages: [
      { role: "system", content: DECISION_SYSTEM_PROMPT },
      { role: "user", content: prompt }
    ]
  });

  return JSON.parse(completion.choices[0]?.message?.content ?? "{}");
});

export const decisionChat = onCall(async (request) => {
  const { projectId, phase, message } = request.data;
  const prompt = [
    `Project: ${projectId}`,
    `Phase: ${phase}`,
    `User message: ${message}`,
    "Respond in JSON only:",
    '{ "content": "", "recommendedActions": [""] }',
    "Behavior:",
    "- Ask one clarifying question if information is missing.",
    "- Offer concise, trustworthy reasoning.",
    "- Give practical next actions."
  ].join("\n");

  const completion = await openai.chat.completions.create({
    model: "gpt-4.1-mini",
    temperature: 0.2,
    response_format: { type: "json_object" },
    messages: [
      { role: "system", content: DECISION_SYSTEM_PROMPT },
      { role: "user", content: prompt }
    ]
  });

  return JSON.parse(completion.choices[0]?.message?.content ?? "{}");
});

export const generateInsights = onCall(async (request) => {
  const { projectId, draft, result } = request.data;
  const prompt = [
    `Project: ${projectId}`,
    `Draft payload: ${JSON.stringify(draft)}`,
    `Result payload: ${JSON.stringify(result)}`,
    "Return JSON only:",
    "{",
    '  "summary":"",',
    '  "winnerReasoning":"",',
    '  "riskFlags":[""],',
    '  "overlookedStrategicPoints":[""],',
    '  "sensitivityFindings":[""]',
    "}",
    "Focus on strategic blind spots, confidence limits, and what could invalidate this winner."
  ].join("\n");

  const completion = await openai.chat.completions.create({
    model: "gpt-4.1",
    temperature: 0.2,
    response_format: { type: "json_object" },
    messages: [
      { role: "system", content: DECISION_SYSTEM_PROMPT },
      { role: "user", content: prompt }
    ]
  });

  return JSON.parse(completion.choices[0]?.message?.content ?? "{}");
});

export const extractVendorFiles = onCall(async (request) => {
  // In production: fetch signed URLs, parse PDF/DOCX and OCR images, then return normalized chunks.
  return {
    projectId: request.data.projectId,
    extractedText: request.data.uploadRefs?.map((ref: string) => `Extracted content from ${ref}`) ?? []
  };
});

export const exportProjectPDF = onCall(async (request) => {
  // In production: generate PDF server-side and return a signed short-lived URL.
  return {
    projectId: request.data.projectId,
    url: "https://example.com/scorewise/export-placeholder.pdf"
  };
});
