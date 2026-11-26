<script lang="ts">
	import type { AgentTeammate, ChatMessage, ConnectionMode } from '../types.js';
	import StatusDot from '@kleinbem/web-config/components/StatusDot';

	let {
		agent,
		messages = [],
		sending = false,
		connectionMode = 'preview',
		chatEnabled = false,
		onSendMessage
	}: {
		agent: AgentTeammate;
		messages: ChatMessage[];
		sending?: boolean;
		connectionMode?: ConnectionMode;
		chatEnabled?: boolean;
		onSendMessage: (text: string) => void;
	} = $props();

	let inputText = $state('');

	let sessionStatusLabel = $derived.by(() => {
		if (sending) return 'Generating…';
		if (connectionMode === 'live' && chatEnabled) return 'Local Inference Ready';
		if (connectionMode === 'live') return 'Status Live · Chat Locked';
		if (connectionMode === 'standby') return 'Backend Standby';
		if (connectionMode === 'checking') return 'Connecting…';
		return 'Preview Mode';
	});

	let sessionDotStatus = $derived<'healthy' | 'checking' | 'unknown'>(
		sending || connectionMode === 'checking'
			? 'checking'
			: connectionMode === 'live' && chatEnabled
				? 'healthy'
				: 'unknown'
	);

	function handleSend() {
		const text = inputText.trim();
		if (!text || sending) return;
		inputText = '';
		onSendMessage(text);
	}

	function handleKeyDown(e: KeyboardEvent) {
		if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
			e.preventDefault();
			handleSend();
		}
	}

	function autoScroll(node: HTMLDivElement) {
		$effect(() => {
			void messages.length;
			void sending;
			node.scrollTop = node.scrollHeight;
		});
	}
</script>

<div class="flex flex-col h-[calc(100vh-12rem)] min-h-[500px] rounded-2xl border border-zinc-200/80 dark:border-zinc-800/80 bg-white dark:bg-zinc-900/40 shadow-xs overflow-hidden">
	<div class="px-5 py-3.5 border-b border-zinc-200/80 dark:border-zinc-800/80 flex items-center justify-between gap-3 bg-zinc-50/50 dark:bg-zinc-900/60">
		<div class="flex items-center gap-3 min-w-0">
			<div
				aria-hidden="true"
				class="h-8 w-8 shrink-0 rounded-lg bg-amber-500/10 border border-amber-500/30 flex items-center justify-center text-amber-500 font-bold select-none"
			>
				{agent.avatar}
			</div>
			<div class="min-w-0">
				<div class="flex items-center gap-2">
					<span class="font-bold text-sm text-zinc-900 dark:text-zinc-100">{agent.name}</span>
					<span class="text-xs font-mono text-zinc-400">{agent.handle}</span>
				</div>
				<p class="text-[11px] font-mono text-zinc-500 truncate">
					{agent.model} · {agent.backend === 'mesh' ? 'MeshLLM cluster' : 'Ollama'}
				</p>
			</div>
		</div>

		<div class="flex items-center gap-2 text-xs font-mono text-zinc-500 shrink-0">
			<StatusDot status={sessionDotStatus} size="sm" pulse={sending || (connectionMode === 'live' && chatEnabled)} />
			<span>{sessionStatusLabel}</span>
		</div>
	</div>

	<div
		role="log"
		aria-label="Conversation timeline"
		aria-live="polite"
		aria-busy={sending}
		{@attach autoScroll}
		class="flex-1 overflow-y-auto p-5 space-y-4"
	>
		{#each messages as msg (msg.id)}
			{#if msg.role === 'thought'}
				<details
					open
					class="p-3 rounded-xl bg-amber-500/5 border border-amber-500/20 text-xs text-amber-900 dark:text-amber-200 font-mono"
				>
					<summary class="cursor-pointer select-none flex items-center gap-2 font-semibold text-[11px] uppercase tracking-wider text-amber-600 dark:text-amber-400">
						<span aria-hidden="true">🧠</span>
						<span>Reasoning Step</span>
						<span class="text-zinc-400 font-normal">({msg.timestamp})</span>
					</summary>
					<p class="mt-1.5 whitespace-pre-wrap leading-relaxed opacity-90">{msg.content}</p>
				</details>
			{:else if msg.role === 'user'}
				<div class="flex justify-end">
					<div class="max-w-xl p-3.5 rounded-2xl bg-zinc-900 dark:bg-zinc-100 text-white dark:text-zinc-900 text-sm shadow-xs">
						<p class="whitespace-pre-wrap leading-relaxed">{msg.content}</p>
						<span class="block text-right text-[10px] text-zinc-400 dark:text-zinc-500 mt-1 font-mono">
							{msg.timestamp}
						</span>
					</div>
				</div>
			{:else}
				<div class="flex justify-start">
					<div
						class="max-w-2xl w-full p-4 rounded-2xl border text-sm {msg.isError
							? 'bg-rose-500/5 border-rose-500/30 text-rose-900 dark:text-rose-200'
							: 'bg-zinc-100/70 dark:bg-zinc-800/60 border-zinc-200/50 dark:border-zinc-700/50 text-zinc-900 dark:text-zinc-100'}"
					>
						<div class="flex items-center gap-2 mb-2 font-mono text-[11px] text-zinc-500">
							<span class="font-bold {msg.isError ? 'text-rose-600 dark:text-rose-400' : 'text-amber-600 dark:text-amber-400'}">
								{agent.handle}
							</span>
							<span>•</span>
							<span>{msg.timestamp}</span>
						</div>

						<p class="whitespace-pre-wrap leading-relaxed">{msg.content}</p>

						{#if msg.toolCalls && msg.toolCalls.length > 0}
							<div class="mt-3 pt-3 border-t border-zinc-200 dark:border-zinc-700/60 space-y-2">
								<span class="text-[10px] font-mono uppercase tracking-wider text-zinc-400">ACP Tool Execution</span>
								{#each msg.toolCalls as tc, idx (`${tc.tool}-${idx}`)}
									<div class="p-2.5 rounded-lg bg-zinc-900 dark:bg-zinc-950 text-zinc-200 font-mono text-xs overflow-x-auto">
										<div class="flex items-center justify-between text-zinc-400 text-[10px] mb-1">
											<span>tool: {tc.tool}</span>
											<span class={tc.status === 'failed' ? 'text-rose-400' : tc.status === 'running' ? 'text-amber-400' : 'text-emerald-400'}>
												{tc.status === 'failed' ? '✗' : tc.status === 'running' ? '…' : '✓'} {tc.status}
											</span>
										</div>
										{#if tc.input}
											<div class="text-amber-400">$ {tc.input}</div>
										{/if}
										{#if tc.output}
											<div class="text-zinc-300 mt-1 text-[11px] whitespace-pre-wrap">{tc.output}</div>
										{/if}
									</div>
								{/each}
							</div>
						{/if}
					</div>
				</div>
			{/if}
		{/each}

		{#if sending}
			<div class="flex justify-start">
				<div class="px-4 py-3 rounded-2xl bg-zinc-100/70 dark:bg-zinc-800/60 border border-zinc-200/50 dark:border-zinc-700/50 text-xs font-mono text-zinc-500 flex items-center gap-2">
					<StatusDot status="checking" size="sm" pulse />
					<span>{agent.handle} is generating on {agent.backend} ({agent.model})…</span>
				</div>
			</div>
		{/if}
	</div>

	<div class="p-4 border-t border-zinc-200/80 dark:border-zinc-800/80 bg-zinc-50/50 dark:bg-zinc-900/60">
		<div class="relative flex items-center rounded-xl border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 focus-within:ring-2 focus-within:ring-amber-500/20 focus-within:border-amber-500 transition-all">
			<textarea
				bind:value={inputText}
				onkeydown={handleKeyDown}
				aria-label="Message {agent.handle}"
				placeholder="Message {agent.handle}... (Enter to send, Shift+Enter for newline)"
				rows="1"
				class="w-full py-3 px-3.5 text-sm bg-transparent outline-none resize-none text-zinc-900 dark:text-zinc-100 placeholder:text-zinc-400"
			></textarea>
			<button
				type="button"
				onclick={handleSend}
				disabled={!inputText.trim() || sending}
				aria-label="Send message"
				title="Send message"
				class="m-1.5 p-2 rounded-lg bg-amber-500 hover:bg-amber-600 disabled:opacity-40 disabled:hover:bg-amber-500 text-white transition-colors cursor-pointer shrink-0"
			>
				<svg aria-hidden="true" class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
					<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8" />
				</svg>
			</button>
		</div>
		<div class="flex items-center justify-between text-[11px] text-zinc-400 font-mono mt-2 px-1">
			<span>Press ⌘K to switch agents or views</span>
			<span>Local Inference · 0 telemetry</span>
		</div>
	</div>
</div>
