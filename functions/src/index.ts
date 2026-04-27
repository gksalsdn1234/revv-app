import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as admin from "firebase-admin";
import * as textToSpeech from "@google-cloud/text-to-speech";

admin.initializeApp();

const anthropicKey = defineSecret("ANTHROPIC_API_KEY");
const openweatherKey = defineSecret("OPENWEATHER_API_KEY");
const ttsClient = new textToSpeech.TextToSpeechClient();
const defaultGoogleVoice = "ko-KR-Chirp3-HD-Leda";

function ttsVoiceScore(name: string): number {
  let score = 0;
  if (name.includes("Chirp3-HD")) score += 100;
  if (name.includes("Leda")) score += 18;
  if (name.includes("Autonoe")) score += 14;
  if (name.includes("Aoede")) score += 12;
  if (name.includes("Kore")) score += 10;
  if (name.includes("Wavenet")) score += 6;
  if (name.includes("Standard")) score -= 8;
  return score;
}

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

// ─── listGoogleTtsVoices ─────────────────────────────────────────────────────
// 반환: { voices: [{ name, locale, label, tier, gender }] }

export const listGoogleTtsVoices = onCall(
  {cors: true},
  async () => {
    try {
      const [response] = await ttsClient.listVoices({languageCode: "ko-KR"});
      const voices = (response.voices ?? [])
        .filter((voice) => (voice.languageCodes ?? []).includes("ko-KR"))
        .map((voice) => {
          const name = voice.name ?? "";
          const locale = (voice.languageCodes ?? [])[0] ?? "ko-KR";
          const tier = name.includes("Chirp3-HD") ?
            "premium" :
            name.includes("Wavenet") ?
              "wavenet" :
              "standard";
          return {
            name,
            locale,
            label: `${name} · ${locale}`,
            tier,
            gender: voice.ssmlGender ?? "SSML_VOICE_GENDER_UNSPECIFIED",
          };
        })
        .filter((voice) => voice.name.startsWith("ko-KR-"))
        .sort((a, b) => {
          const scoreDelta = ttsVoiceScore(b.name) - ttsVoiceScore(a.name);
          if (scoreDelta != 0) return scoreDelta;
          return a.name.localeCompare(b.name);
        });
      return {voices};
    } catch (error) {
      throw new HttpsError("internal", `Google TTS 음성 목록 오류: ${String(error)}`);
    }
  }
);

// ─── synthesizeTts ───────────────────────────────────────────────────────────
// 파라미터: { text, voiceName? }
// 반환: { audioContent, voiceName, provider, format }

export const synthesizeTts = onCall(
  {cors: true, timeoutSeconds: 60},
  async (request) => {
    const {text, voiceName} = request.data as {
      text?: string;
      voiceName?: string;
    };

    const normalizedText = (text ?? "").trim();
    if (normalizedText.length === 0) {
      throw new HttpsError("invalid-argument", "text가 필요합니다.");
    }
    if (normalizedText.length > 260) {
      throw new HttpsError("invalid-argument", "text는 260자 이하여야 합니다.");
    }

    const selectedVoice = typeof voiceName === "string" &&
        voiceName.startsWith("ko-KR-") ?
      voiceName :
      defaultGoogleVoice;

    try {
      const [response] = await ttsClient.synthesizeSpeech({
        input: {text: normalizedText},
        voice: {
          languageCode: "ko-KR",
          name: selectedVoice,
        },
        audioConfig: {
          audioEncoding: "MP3",
        },
      });

      const audio = response.audioContent;
      if (!audio) {
        throw new HttpsError("internal", "Google TTS 오디오 응답이 비어 있습니다.");
      }

      const bytes = typeof audio === "string" ?
        Buffer.from(audio, "base64") :
        Buffer.from(audio);

      return {
        audioContent: bytes.toString("base64"),
        voiceName: selectedVoice,
        provider: "google",
        format: "mp3",
      };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("internal", `Google TTS 합성 오류: ${String(error)}`);
    }
  }
);
