// Ramp request rate against vLLM's OpenAI-compatible API until the T4 hits the wall.
// Everything tunable comes from environment variables set by Terraform.
import http from 'k6/http';
import { check } from 'k6';

const BASE_URL = __ENV.BASE_URL;
const MODEL = __ENV.MODEL;
const MAX_TOKENS = parseInt(__ENV.MAX_TOKENS || '256');
const PROMPT_REPEAT = parseInt(__ENV.PROMPT_REPEAT || '20');
const STAGES = JSON.parse(__ENV.STAGES);

// ~50 tokens; repeated PROMPT_REPEAT times => prompt length (and KV cache per request).
const FILLER =
  'The quick brown fox jumps over the lazy dog while the observability team ' +
  'watches GPU memory, queue depth and token latency on a Grafana dashboard. ';

export const options = {
  scenarios: {
    ramp: {
      // Open model: k6 starts N new requests per second no matter how slow the
      // server gets — like real users. (A closed model with fixed VUs would
      // politely slow down with the server and hide the wall.)
      executor: 'ramping-arrival-rate',
      startRate: parseInt(__ENV.START_RATE || '1'),
      timeUnit: '1s',
      preAllocatedVUs: 50,
      // Once latency explodes, k6 runs out of VUs and records dropped_iterations.
      maxVUs: parseInt(__ENV.MAX_VUS || '400'),
      stages: STAGES,
    },
  },
  summaryTrendStats: ['p(50)', 'p(95)', 'p(99)', 'max'],
};

export default function () {
  // Unique prefix per request defeats vLLM's prefix cache, so every request
  // pays full prefill and full KV cache — otherwise identical prompts are free.
  const prompt =
    `Request ${__VU}-${__ITER}-${Math.random()}. Summarise the following:\n` +
    FILLER.repeat(PROMPT_REPEAT);

  const res = http.post(
    `${BASE_URL}/v1/chat/completions`,
    JSON.stringify({
      model: MODEL,
      messages: [{ role: 'user', content: prompt }],
      max_tokens: MAX_TOKENS,
      // vLLM extension: keep generating to max_tokens, so every request costs
      // the same and the load is predictable from run to run.
      ignore_eos: true,
    }),
    {
      headers: { 'Content-Type': 'application/json' },
      timeout: '300s',
      tags: { name: 'chat_completions' },
    },
  );

  check(res, { 'status is 200': (r) => r.status === 200 });
}
