import { OpenRouterError } from '../utils/errors.js';
import { log } from '../utils/logger.js';

export interface LLMMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

export interface LLMRequestOptions {
  apiKey: string;
  model: string;
  messages: LLMMessage[];
  temperature?: number;
  maxTokens?: number;
  jsonMode?: boolean;
}

interface OpenRouterResponse {
  choices: Array<{
    message: {
      content: string;
    };
  }>;
  usage?: {
    prompt_tokens: number;
    completion_tokens: number;
    total_tokens: number;
  };
}

const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions';

export async function llmRequest(options: LLMRequestOptions): Promise<string> {
  const { apiKey, model, messages, temperature = 0.3, maxTokens = 16384, jsonMode = false } = options;

  log.debug(`LLM request to ${model} (${messages.length} messages, json=${jsonMode})`);

  const body: Record<string, unknown> = {
    model,
    messages,
    temperature,
    max_tokens: maxTokens,
  };

  if (jsonMode) {
    body.response_format = { type: 'json_object' };
  }

  const res = await fetch(OPENROUTER_URL, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://github.com/soel-lang/soel',
      'X-Title': 'SOEL Compiler',
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new OpenRouterError(
      `OpenRouter API error: ${res.status} ${res.statusText}`,
      res.status,
      text
    );
  }

  const data = (await res.json()) as OpenRouterResponse;

  if (!data.choices?.[0]?.message?.content) {
    throw new OpenRouterError('Empty response from OpenRouter');
  }

  const content = data.choices[0].message.content;

  if (data.usage) {
    log.debug(
      `Tokens: ${data.usage.prompt_tokens} in, ${data.usage.completion_tokens} out`
    );
  }

  return content;
}

/**
 * Extract JSON from an LLM response that may contain markdown fences or extra text.
 */
export function extractJSON(text: string): string {
  // Try to find JSON in code fences first
  const fenceMatch = text.match(/```(?:json)?\s*\n?([\s\S]*?)\n?```/);
  if (fenceMatch) {
    return fenceMatch[1].trim();
  }

  // Try to find raw JSON object/array
  const jsonMatch = text.match(/(\{[\s\S]*\}|\[[\s\S]*\])/);
  if (jsonMatch) {
    return jsonMatch[1].trim();
  }

  return text.trim();
}
