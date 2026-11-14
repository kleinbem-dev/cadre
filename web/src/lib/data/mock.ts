import type { AgentTeammate, ComputeNode, ChatMessage } from '../types.js';

export const INITIAL_TEAMMATES: AgentTeammate[] = [
	{
		id: 'cadre-core',
		handle: '@cadre',
		name: 'Cadre Lead',
		role: 'Pairing Assistant & Orchestrator',
		description:
			'General engineering teammate powered by Goose ACP. Plans architectures, runs commands, and drives pairing.',
		avatar: '◈',
		backend: 'mesh',
		model: 'Qwen3-8B-Q4_K_M',
		tools: ['bash', 'edit', 'read', 'git', 'browse'],
		status: 'idle'
	},
	{
		id: 'cadre-code',
		handle: '@cadre-code',
		name: 'Cadre Code',
		role: 'Refactoring & Bug Hunter',
		description:
			'Code-specialist teammate focused on AST manipulation, compiler error diagnostics, and test suites.',
		avatar: '⚡',
		backend: 'ollama',
		model: 'qwen2.5-coder:14b',
		tools: ['edit', 'read', 'test', 'ast-grep'],
		status: 'idle'
	},
	{
		id: 'cadre-fleet',
		handle: '@cadre-fleet',
		name: 'Cadre Fleet',
		role: 'NixOS & Fleet Systems Auditor',
		description:
			'Fleet infrastructure specialist. Manages JJ workspaces, evaluates Nix closures, and checks sops secrets.',
		avatar: '🛡️',
		backend: 'mesh',
		model: 'Qwen3-8B-Q4_K_M',
		tools: ['nix', 'just', 'jj', 'sops', 'ssh'],
		status: 'idle'
	}
];

export const INITIAL_NODES: ComputeNode[] = [
	{
		id: 'node-nvme',
		host: 'nixos-nvme',
		nodeType: 'gpu-box',
		backend: 'mesh',
		activeModel: 'Qwen3-8B-Q4_K_M',
		vramUsedGb: 6.2,
		vramTotalGb: 24.0,
		tokensPerSec: 68.4,
		latencyMs: 18,
		status: 'healthy'
	},
	{
		id: 'node-mini',
		host: 'mac-mini',
		nodeType: 'cluster-peer',
		backend: 'ollama',
		activeModel: 'qwen2.5-coder:14b',
		vramUsedGb: 9.1,
		vramTotalGb: 16.0,
		tokensPerSec: 42.1,
		latencyMs: 24,
		status: 'healthy'
	},
	{
		id: 'node-nasbook',
		host: 'nasbook',
		nodeType: 'laptop',
		backend: 'mesh',
		activeModel: 'Qwen3-8B-Q4_K_M (Split layer 24-32)',
		vramUsedGb: 3.4,
		vramTotalGb: 8.0,
		tokensPerSec: 31.5,
		latencyMs: 32,
		status: 'healthy'
	}
];

export const SAMPLE_MESSAGES: ChatMessage[] = [
	{
		id: 'msg-1',
		role: 'user',
		isPreview: true,
		content:
			'Can you verify the latest changes to web-config and confirm the exported components in the workspace?',
		timestamp: '16:48'
	},
	{
		id: 'msg-2',
		role: 'thought',
		isPreview: true,
		content:
			'Inspecting package.json exports in @kleinbem/web-config... Checking ./components/CommandPalette and ./components/StatusDot.',
		timestamp: '16:48'
	},
	{
		id: 'msg-3',
		role: 'assistant',
		isPreview: true,
		content:
			'I verified `@kleinbem/web-config`. The package now exports both `<StatusDot />` and `<CommandPalette />` with complete TypeScript definitions and Tailwind v4 `@source` registration.',
		toolCalls: [
			{
				tool: 'bash',
				input: 'just check web-config',
				output: 'node --check src/index.js src/vite.js -> OK',
				status: 'completed'
			}
		],
		timestamp: '16:49'
	}
];
