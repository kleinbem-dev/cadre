import * as assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { afterEach, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';
import { runInNewContext } from 'node:vm';
import { INITIAL_NODES, INITIAL_TEAMMATES, SAMPLE_MESSAGES } from '#lib/data/mock.js';
import { CadreState, resolveTeammates } from '#lib/state.svelte.js';
import { APP_VERSION, type BackendStatusResponse } from '#lib/types.js';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

describe('app.html bootstrap & document shell', () => {
	const html = readFileSync(resolve(ROOT, 'src/app.html'), 'utf8');
	const pkg = JSON.parse(readFileSync(resolve(ROOT, 'package.json'), 'utf8')) as { version: string };

	it('keeps APP_VERSION synced with package.json', () => {
		assert.equal(APP_VERSION, pkg.version);
	});

	it('declares utf-8 charset, inline favicon, responsive viewport, and dark/light color-scheme', () => {
		assert.match(html, /<meta charset="utf-8"\s*\/>/);
		assert.match(html, /<link[\s\S]*?rel="icon"[\s\S]*?data:image\/svg\+xml/);
		assert.match(html, /name="viewport"/);
		assert.match(html, /name="color-scheme"\s+content="dark light"/);
		assert.match(html, /%sveltekit\.head%/);
		assert.match(html, /%sveltekit\.body%/);
	});

	it('rejects untrusted localStorage theme and font-size values via strict allowlists', () => {
		const scriptMatch = html.match(/<script>([\s\S]*?)<\/script>/);
		assert.ok(scriptMatch, 'missing inline bootstrap script');

		const classes = new Set<string>();
		const dataset: Record<string, string> = {};
		runInNewContext(scriptMatch[1], {
			localStorage: {
				getItem: (key: string) =>
					key === 'fleet-theme' ? 'injected theme' : 'evil whitespace'
			},
			window: {
				matchMedia: () => ({ matches: true })
			},
			document: {
				documentElement: {
					dataset,
					classList: {
						toggle: (cls: string, force: boolean) => {
							if (force) classes.add(cls);
							else classes.delete(cls);
						},
						add: (cls: string) => {
							if (/\s/.test(cls)) throw new Error('DOMException: invalid token');
							classes.add(cls);
						}
					}
				}
			}
		});

		assert.equal(dataset.theme, 'dark');
		assert.equal(dataset.fontSize, undefined);
		assert.ok(classes.has('dark'));
		assert.equal(classes.size, 1);
	});

	it('contains zero invalid py-0.2 Tailwind utility classes across src/', () => {
		for (const rel of readdirSync(resolve(ROOT, 'src'), { recursive: true })) {
			if (rel.endsWith('.svelte') || rel.endsWith('.ts') || rel.endsWith('.css')) {
				const content = readFileSync(resolve(ROOT, 'src', rel), 'utf8');
				assert.doesNotMatch(content, /\bpy-0\.2\b/, `invalid py-0.2 class in src/${rel}`);
			}
		}
	});
});

describe('seed teammates, compute nodes, and live state resolution', () => {
	const origFetch = globalThis.fetch;
	afterEach(() => {
		globalThis.fetch = origFetch;
	});

	it('defines unique teammate IDs, @-prefixed handles, and non-empty tool lists', () => {
		assert.ok(INITIAL_TEAMMATES.length >= 3);
		const ids = new Set<string>();
		for (const t of INITIAL_TEAMMATES) {
			assert.ok(!ids.has(t.id), `duplicate teammate id: ${t.id}`);
			ids.add(t.id);
			assert.match(t.handle, /^@[a-z0-9-]+$/);
			assert.ok(t.tools.length > 0);
			assert.ok(t.backend === 'mesh' || t.backend === 'ollama');
		}
	});

	it('defines valid compute node VRAM bounds and unique sample message IDs', () => {
		for (const n of INITIAL_NODES) {
			assert.ok(n.vramTotalGb > 0);
			assert.ok(n.vramUsedGb >= 0 && n.vramUsedGb <= n.vramTotalGb);
		}
		const ids = new Set(SAMPLE_MESSAGES.map((m) => m.id));
		assert.equal(ids.size, SAMPLE_MESSAGES.length);
	});

	it('maps live single-backend status and standby states onto teammates accurately', () => {
		const liveOllama: BackendStatusResponse = {
			activeBackend: 'ollama',
			configuredBackend: 'ollama',
			defaultModel: 'qwen2.5-coder:7b',
			chatEnabled: true,
			host: 'workstation',
			nodes: [
				{
					id: 'local-ollama',
					host: 'workstation',
					nodeType: 'laptop',
					backend: 'ollama',
					activeModel: 'qwen2.5-coder:7b',
					vramUsedGb: 5.0,
					vramTotalGb: 0,
					tokensPerSec: 0,
					latencyMs: 3,
					status: 'healthy'
				}
			]
		};

		const resolved = resolveTeammates(INITIAL_TEAMMATES, liveOllama, 'live', 'cadre-core', true);
		assert.equal(resolved[0].backend, 'ollama');
		assert.equal(resolved[0].model, 'qwen2.5-coder:7b');
		assert.equal(resolved[0].status, 'busy');
		assert.equal(resolved[1].status, 'idle');

		const standby = resolveTeammates(INITIAL_TEAMMATES, null, 'standby', 'cadre-core', false);
		assert.ok(standby.every((t) => t.status === 'offline'));
	});

	it('handles live /api/status + /api/chat, excludes preview history, and guards overlapping calls', async () => {
		const store = new CadreState();
		let postedMessages: Array<{ role: string; content: string }> = [];

		// Simulate a preview message before live status arrives
		store.connectionMode = 'preview';
		await store.sendMessage('preview question');

		// Simulate overlapping status refreshes where stale request resolves after newer one
		let resolveSlow!: (r: Response) => void;
		let callCount = 0;
		globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
			const url = String(input);
			if (url.startsWith('/api/status')) {
				callCount += 1;
				if (callCount === 1) {
					return new Promise<Response>((res) => {
						resolveSlow = res;
					});
				}
				return Promise.resolve(
					new Response(
						JSON.stringify({
							activeBackend: 'mesh',
							configuredBackend: 'mesh',
							defaultModel: 'Qwen3-Local',
							chatEnabled: true,
							host: 'nixos-nvme',
							nodes: [
								{
									id: 'local-mesh',
									host: 'nixos-nvme',
									nodeType: 'gpu-box',
									backend: 'mesh',
									activeModel: 'Qwen3-Local',
									vramUsedGb: 0,
									vramTotalGb: 0,
									tokensPerSec: 0,
									latencyMs: 2,
									status: 'healthy'
								}
							]
						}),
						{ status: 200, headers: { 'Content-Type': 'application/json' } }
					)
				);
			}
			const parsed = JSON.parse(String(init?.body ?? '{}')) as {
				messages: Array<{ role: string; content: string }>;
			};
			postedMessages = parsed.messages;
			return Promise.resolve(
				new Response(JSON.stringify({ reply: 'live reply from mesh' }), {
					status: 200,
					headers: { 'Content-Type': 'application/json' }
				})
			);
		}) as typeof fetch;

		const stalePromise = store.refreshStatus(false);
		const freshPromise = store.refreshStatus(true);
		await freshPromise;
		resolveSlow(new Response('not found', { status: 404 }));
		await stalePromise;

		assert.equal(store.connectionMode, 'live');
		assert.equal(store.isReferenceNodes, false);
		assert.equal(store.activeAgent.model, 'Qwen3-Local');

		const before = store.messages.length;
		const chatPromise = store.sendMessage('ping local node');
		assert.equal(store.sending, true);
		store.selectAgent('cadre-code');
		assert.equal(store.selectedAgentId, 'cadre-core');
		await chatPromise;

		assert.equal(store.messages.length, before + 2);
		assert.equal(store.messages.at(-1)?.content, 'live reply from mesh');
		assert.equal(store.messages.at(-1)?.isError, undefined);
		assert.deepEqual(
			postedMessages.filter((m) => m.role !== 'system'),
			[{ role: 'user', content: 'ping local node' }]
		);

		// Locked chat on non-loopback listener produces clear diagnostic error message
		store.status = { ...store.status!, chatEnabled: false };
		await store.sendMessage('blocked prompt');
		assert.equal(store.messages.at(-1)?.isError, true);
		assert.match(store.messages.at(-1)?.content ?? '', /enableChatProxy/);
	});
});
