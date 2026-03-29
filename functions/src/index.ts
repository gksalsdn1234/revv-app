import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as admin from "firebase-admin";

admin.initializeApp();

const anthropicKey = defineSecret("ANTHROPIC_API_KEY");
const openweatherKey = defineSecret("OPENWEATHER_API_KEY");

// ─── callClaude ──────────────────────────────────────────────────────────────
// 단일 함수로 revv_ai_service.dart + route_brief_service.dart 의 모든 Claude 호출 처리
// 파라미터: { model, system, messages, maxTokens }
// 반환: { text: string }

export const callClaude = onCall(
  {secrets: [anthropicKey], cors: true},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    }

    const {model, system, messages, maxTokens} = request.data as {
      model?: string;
      system?: string;
      messages: Array<{role: string; content: string}>;
      maxTokens?: number;
    };

    if (!messages || !Array.isArray(messages) || messages.length === 0) {
      throw new HttpsError("invalid-argument", "messages 배열이 필요합니다.");
    }

    const body: Record<string, unknown> = {
      model: model ?? "claude-sonnet-4-6",
      max_tokens: maxTokens ?? 200,
      messages,
    };
    if (system) body.system = system;

    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": anthropicKey.value(),
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new HttpsError("internal", `Claude API 오류: ${res.status} ${errText}`);
    }

    const data = (await res.json()) as {
      content: Array<{type: string; text: string}>;
    };
    const text = data.content?.[0]?.text ?? "";
    return {text: text.trim()};
  }
);

// ─── getWeather ───────────────────────────────────────────────────────────────
// 파라미터: { lat, lng }
// 반환: OpenWeatherMap current weather JSON (그대로 전달)

export const getWeather = onCall(
  {secrets: [openweatherKey], cors: true},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    }

    const {lat, lng} = request.data as {lat: number; lng: number};
    if (typeof lat !== "number" || typeof lng !== "number") {
      throw new HttpsError("invalid-argument", "lat, lng 숫자가 필요합니다.");
    }

    const url = `https://api.openweathermap.org/data/2.5/weather?lat=${lat}&lon=${lng}&appid=${openweatherKey.value()}&units=metric&lang=kr`;
    const res = await fetch(url, {signal: AbortSignal.timeout(10000)});

    if (!res.ok) {
      throw new HttpsError("internal", `날씨 API 오류: ${res.status}`);
    }

    return await res.json();
  }
);
