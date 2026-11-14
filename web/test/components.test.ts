import * as assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { render } from 'svelte/server';
import AgentCard from '#lib/components/AgentCard.svelte';
import ComputeTelemetry from '#lib/components/ComputeTelemetry.svelte';
import Header from '#lib/components/Header.svelte';
import SessionView from '#lib/components/SessionView.svelte';
import { INITIAL_NODES, INITIAL_TEAMMATES, SAMPLE_MESSAGES } from '#lib/data/mock.js';
import type { AgentTeammate, ChatMessage, ComputeNode } from '#lib/types.js';

describe('Header component & WAI-ARIA tabs', () => {
	it('renders WAI-ARIA tablist, roving tabindex, and command palette trigger', () => {
		const { body } = render(Header, {
			props: {
				activeTab: 'teammates',
				connectionMode: 'live',
				statusLabel: 'mesh · Qwen3-8B-Q4_K_M',
				onTabChange: () => {},
				onOpenPalette: () => {}
			}
		});
		assert.match(body, /role="tablist"/);
		assert.match(body, /id="tab-teammates"[^>]*role="tab"[^>]*aria-selected="true"[^>]*aria-controls="panel-teammates"[^>]*tabindex="0"/);
		assert.match(body, /id="tab-session"[^>]*role="tab"[^>]*aria-selected="false"[^>]*tabindex="-1"/);
		assert.match(body, /mesh · Qwen3-8B-Q4_K_M/);
		assert.match(body, /Open Command Palette/);
	});
});

describe('AgentCard component', () => {
	it('renders MeshLLM and Ollama badges, tools, and status states', () => {
		const meshHtml = render(AgentCard, {
			props: { agent: INITIAL_TEAMMATES[0], onSelect: () => {} }
		}).body;
		assert.match(meshHtml, /@cadre/);
		assert.match(meshHtml, /MeshLLM cluster/);
		assert.match(meshHtml, /Start Pairing Session/);

		const busyOllama: AgentTeammate = {
			...INITIAL_TEAMMATES[1],
			status: 'busy'
		};
		const ollamaHtml = render(AgentCard, {
			props: { agent: busyOllama }
		}).body;
		assert.match(ollamaHtml, /Ollama local/);
		assert.match(ollamaHtml, /busy/);
		assert.doesNotMatch(ollamaHtml, /Start Pairing Session/);
	});
});

describe('ComputeTelemetry component', () => {
	it('aggregates VRAM, handles live host-managed VRAM (total=0), and guards empty arrays', () => {
		const populated = render(ComputeTelemetry, {
			props: { nodes: INITIAL_NODES, isReference: true }
		}).body;
		assert.match(populated, /nixos-nvme/);
		assert.match(populated, /\/ 48 GB/);
		assert.match(populated, /Reference Fleet Topology/);

		const liveNodes: ComputeNode[] = [
			{
				id: 'local-mesh',
				host: 'workstation',
				nodeType: 'gpu-box',
				backend: 'mesh',
				activeModel: 'Qwen3-Local',
				vramUsedGb: 0,
				vramTotalGb: 0,
				tokensPerSec: 0,
				latencyMs: 2,
				status: 'healthy'
			}
		];
		const liveHtml = render(ComputeTelemetry, {
			props: { nodes: liveNodes, isReference: false }
		}).body;
		assert.match(liveHtml, /Local Zero-Egress Compute/);
		assert.match(liveHtml, /host-managed/);
		assert.match(liveHtml, /Qwen3-Local/);
		assert.doesNotMatch(liveHtml, /NaN/);

		const empty = render(ComputeTelemetry, {
			props: { nodes: [] }
		}).body;
		assert.match(empty, /Standby/);
		assert.doesNotMatch(empty, /NaN/);
	});
});

describe('SessionView component', () => {
	it('renders collapsible <details> reasoning, accessible log, error & busy states', () => {
		const extraMessages: ChatMessage[] = [
			...SAMPLE_MESSAGES,
			{
				id: 'msg-err',
				role: 'assistant',
				isError: true,
				content: 'Local backend unreachable.',
				timestamp: '16:50',
				toolCalls: [
					{
						tool: 'nix',
						input: 'nix build .#broken',
						output: 'error: attribute broken missing',
						status: 'failed'
					}
				]
			}
		];
		const { body } = render(SessionView, {
			props: {
				agent: INITIAL_TEAMMATES[0],
				messages: extraMessages,
				sending: true,
				connectionMode: 'live',
				chatEnabled: true,
				onSendMessage: () => {}
			}
		});
		assert.match(body, /role="log"/);
		assert.match(body, /aria-live="polite"/);
		assert.match(body, /<details[\s>]/);
		assert.match(body, /<summary[\s>][\s\S]*?Reasoning Step/);
		assert.match(body, /ACP Tool Execution/);
		assert.match(body, /Local backend unreachable\./);
		assert.match(body, /is generating on mesh/);
		assert.match(body, /aria-label="Message @cadre"/);
	});
});
