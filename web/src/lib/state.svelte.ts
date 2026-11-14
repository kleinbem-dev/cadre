import { INITIAL_NODES, INITIAL_TEAMMATES, SAMPLE_MESSAGES } from './data/mock.js';
import type {
	AgentTeammate,
	BackendStatusResponse,
	ChatMessage,
	ComputeNode,
	ConnectionMode,
	TabId
} from './types.js';

export function resolveTeammates(
	base: AgentTeammate[],
	status: BackendStatusResponse | null,
	mode: ConnectionMode,
	selectedAgentId: string,
	sending: boolean
): AgentTeammate[] {
	return base.map((t) => {
		const isSelectedBusy = sending && t.id === selectedAgentId;
		if (mode === 'standby') {
			return { ...t, status: 'offline' };
		}
		if (mode !== 'live' || !status) {
			return { ...t, status: isSelectedBusy ? 'busy' : t.status };
		}
		const matchingNode = status.nodes.find((n) => n.backend === t.backend);
		if (matchingNode && matchingNode.activeModel && matchingNode.activeModel !== 'idle') {
			return {
				...t,
				backend: matchingNode.backend,
				model: matchingNode.activeModel,
				status: isSelectedBusy ? 'busy' : 'idle'
			};
		}
		if (status.activeBackend === 'mesh' || status.activeBackend === 'ollama') {
			return {
				...t,
				backend: status.activeBackend,
				model: status.defaultModel || t.model,
				status: isSelectedBusy ? 'busy' : 'idle'
			};
		}
		return { ...t, status: isSelectedBusy ? 'busy' : 'idle' };
	});
}

function nowTime(): string {
	return new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

export class CadreState {
	activeTab = $state<TabId>('session');
	commandPaletteOpen = $state(false);
	selectedAgentId = $state('cadre-core');
	messages = $state<ChatMessage[]>(SAMPLE_MESSAGES);
	sending = $state(false);
	refreshing = $state(false);
	connectionMode = $state<ConnectionMode>('checking');
	status = $state<BackendStatusResponse | null>(null);

	#msgSeq = 100;
	#refreshSeq = 0;
	#refreshAbort: AbortController | null = null;

	teammates = $derived<AgentTeammate[]>(
		resolveTeammates(
			INITIAL_TEAMMATES,
			this.status,
			this.connectionMode,
			this.selectedAgentId,
			this.sending
		)
	);

	activeAgent = $derived<AgentTeammate>(
		this.teammates.find((t) => t.id === this.selectedAgentId) ?? this.teammates[0]
	);

	isReferenceNodes = $derived(
		this.connectionMode !== 'live' || !this.status || this.status.nodes.length === 0
	);

	nodes = $derived<ComputeNode[]>(
		!this.isReferenceNodes && this.status ? this.status.nodes : INITIAL_NODES
	);

	chatEnabled = $derived(this.connectionMode === 'live' && Boolean(this.status?.chatEnabled));

	statusLabel = $derived.by(() => {
		if (this.connectionMode === 'live' && this.status) {
			return `${this.status.activeBackend} · ${this.status.defaultModel}`;
		}
		if (this.connectionMode === 'standby') {
			return 'Standby (backend stopped)';
		}
		if (this.connectionMode === 'preview') {
			return 'Static preview';
		}
		return 'Checking local node…';
	});

	setTab(tab: TabId): void {
		this.activeTab = tab;
	}

	selectAgent(agentId: string): void {
		if (this.sending) return;
		if (INITIAL_TEAMMATES.some((t) => t.id === agentId)) {
			this.selectedAgentId = agentId;
			this.activeTab = 'session';
		}
	}

	async refreshStatus(force = false): Promise<void> {
		const seq = ++this.#refreshSeq;
		this.#refreshAbort?.abort();
		const controller = new AbortController();
		this.#refreshAbort = controller;
		this.refreshing = true;
		try {
			const url = force ? '/api/status?refresh=1' : '/api/status';
			const resp = await fetch(url, {
				headers: { Accept: 'application/json' },
				signal: controller.signal
			});
			if (seq !== this.#refreshSeq) return;
			if (!resp.ok) {
				this.connectionMode = 'preview';
				this.status = null;
				return;
			}
			const data = (await resp.json()) as BackendStatusResponse;
			if (seq !== this.#refreshSeq) return;
			if (!data || typeof data.activeBackend !== 'string' || !Array.isArray(data.nodes)) {
				this.connectionMode = 'preview';
				this.status = null;
				return;
			}
			this.status = data;
			this.connectionMode = data.activeBackend === 'standby' ? 'standby' : 'live';
		} catch {
			if (seq !== this.#refreshSeq) return;
			this.connectionMode = 'preview';
			this.status = null;
		} finally {
			if (seq === this.#refreshSeq) {
				this.refreshing = false;
				this.#refreshAbort = null;
			}
		}
	}

	async sendMessage(rawText: string): Promise<void> {
		const text = rawText.trim();
		if (!text || this.sending) return;

		const agent = this.activeAgent;
		const isLiveChat = this.connectionMode === 'live' && Boolean(this.status?.chatEnabled);
		const userMsg: ChatMessage = {
			id: `msg-${++this.#msgSeq}`,
			role: 'user',
			content: text,
			...(isLiveChat ? {} : { isPreview: true }),
			timestamp: nowTime()
		};
		this.messages = [...this.messages, userMsg];

		if (this.connectionMode === 'standby') {
			this.messages = [
				...this.messages,
				{
					id: `msg-${++this.#msgSeq}`,
					role: 'assistant',
					isError: true,
					content:
						"Local inference is in standby (no active MeshLLM or Ollama model detected). Start your node with 'cadre serve' and refresh.",
					timestamp: nowTime()
				}
			];
			return;
		}

		if (this.connectionMode === 'live' && this.status && !this.status.chatEnabled) {
			this.messages = [
				...this.messages,
				{
					id: `msg-${++this.#msgSeq}`,
					role: 'assistant',
					isError: true,
					content:
						"Chat proxy is disabled on non-loopback listeners. Run 'cadre web' locally on 127.0.0.1 or enable services.cadre.web.enableChatProxy.",
					timestamp: nowTime()
				}
			];
			return;
		}

		if (this.connectionMode !== 'live') {
			this.messages = [
				...this.messages,
				{
					id: `msg-${++this.#msgSeq}`,
					role: 'assistant',
					isPreview: true,
					content: `[Preview mode — run 'cadre web' to connect ${agent.handle} to local MeshLLM or Ollama inference.]`,
					timestamp: nowTime()
				}
			];
			return;
		}

		this.sending = true;
		try {
			const history = this.messages
				.filter(
					(m) =>
						!m.isPreview &&
						(m.role === 'user' || (m.role === 'assistant' && !m.isError))
				)
				.slice(-16)
				.map((m) => ({ role: m.role as 'user' | 'assistant', content: m.content }));

			const resp = await fetch('/api/chat', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
				body: JSON.stringify({
					backend: agent.backend,
					model: agent.model,
					messages: [
						{
							role: 'system',
							content: `You are ${agent.name} (${agent.handle}), ${agent.role}. ${agent.description}`
						},
						...history
					]
				})
			});

			const payload = (await resp.json().catch(() => ({}))) as {
				reply?: string;
				error?: string;
			};
			if (!resp.ok) {
				this.messages = [
					...this.messages,
					{
						id: `msg-${++this.#msgSeq}`,
						role: 'assistant',
						isError: true,
						content: payload.error || `Local inference request failed (HTTP ${resp.status}).`,
						timestamp: nowTime()
					}
				];
				return;
			}

			this.messages = [
				...this.messages,
				{
					id: `msg-${++this.#msgSeq}`,
					role: 'assistant',
					content: payload.reply || '(empty response)',
					timestamp: nowTime()
				}
			];
		} catch (err) {
			this.messages = [
				...this.messages,
				{
					id: `msg-${++this.#msgSeq}`,
					role: 'assistant',
					isError: true,
					content: `Failed to reach local Cadre server: ${err instanceof Error ? err.message : String(err)}`,
					timestamp: nowTime()
				}
			];
		} finally {
			this.sending = false;
		}
	}
}

export const cadre = new CadreState();
