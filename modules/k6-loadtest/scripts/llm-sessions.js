// Multi-turn chat sessions — the workload that makes routing strategy matter.
//
// Each simulated user has a long, unique conversation history (system prompt +
// earlier turns). Every request from that user repeats the history and adds a
// new question, like a real chat app. If the router sends a user back to the
// backend that served them before, vLLM's prefix cache already holds the
// history and only the new question needs prefill -> low TTFT. If not, the
// whole history is recomputed on a cold backend.
import http from 'k6/http';
import { check } from 'k6';

const BASE_URL = __ENV.BASE_URL;
const MODEL = __ENV.MODEL;
const SESSION_HEADER = __ENV.SESSION_HEADER || 'x-user-id';
const USERS = parseInt(__ENV.USERS || '40');
const HISTORY_REPEAT = parseInt(__ENV.HISTORY_REPEAT || '30'); // ~27 tokens each (measured)
const MAX_TOKENS = parseInt(__ENV.MAX_TOKENS || '64');
const STAGES = JSON.parse(__ENV.STAGES);

const HISTORY_CHUNK =
  'Earlier in this conversation we discussed GPU memory, KV cache sizing, ' +
  'batching, request queues and why time to first token matters to users. ';

export const options = {
  scenarios: {
    sessions: {
      executor: 'ramping-arrival-rate',
      startRate: parseInt(__ENV.START_RATE || '1'),
      timeUnit: '1s',
      preAllocatedVUs: 50,
      maxVUs: parseInt(__ENV.MAX_VUS || '300'),
      stages: STAGES,
    },
  },
  summaryTrendStats: ['p(50)', 'p(95)', 'p(99)', 'max'],
};

// History is unique per user AND starts with the user id, so two users never
// share a prefix — only a user's own turns do.
function history(user) {
  return `You are the assistant for user-${user}. ` + HISTORY_CHUNK.repeat(HISTORY_REPEAT);
}

export default function () {
  const user = Math.floor(Math.random() * USERS);

  const res = http.post(
    `${BASE_URL}/v1/chat/completions`,
    JSON.stringify({
      model: MODEL,
      messages: [
        { role: 'system', content: history(user) },
        { role: 'user', content: `Follow-up question ${__ITER}-${Math.random()}: summarise in one line.` },
      ],
      max_tokens: MAX_TOKENS,
      ignore_eos: true,
    }),
    {
      headers: { 'Content-Type': 'application/json', [SESSION_HEADER]: `user-${user}` },
      timeout: '300s',
      tags: { name: 'chat_session' },
    },
  );

  check(res, { 'status is 200': (r) => r.status === 200 });
}
