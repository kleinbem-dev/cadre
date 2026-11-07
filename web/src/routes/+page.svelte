<script lang="ts">
	import { onMount } from 'svelte';
	import Header from '#lib/components/Header.svelte';
	import AgentCard from '#lib/components/AgentCard.svelte';
	import SessionView from '#lib/components/SessionView.svelte';
	import ComputeTelemetry from '#lib/components/ComputeTelemetry.svelte';
	import { INITIAL_TEAMMATES, INITIAL_NODES, SAMPLE_MESSAGES } from '#lib/data/mock.js';
	import type { AgentTeammate, ChatMessage } from '#lib/types.js';

	let activeTab = $state<'session' | 'teammates' | 'compute'>('session');
	let teammates = $state<AgentTeammate[]>(INITIAL_TEAMMATES);
	let selectedAgentId = $state<string>('cadre-core');
	let messages = $state<ChatMessage[]>(SAMPLE_MESSAGES);
	let paletteOpen = $state(false);

	let activeAgent = $derived(
		teammates.find((t) => t.id === selectedAgentId) ?? teammates[0]
	);

	function handleSendMessage(text: string) {
		const userMsg: ChatMessage = {
			id: `msg-${Date.now()}`,
			role: 'user',
			content: text,
			timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
		};

		messages = [...messages, userMsg];

		// Simulated local response from active teammate
		setTimeout(() => {
			const assistantMsg: ChatMessage = {
				id: `msg-${Date.now() + 1}`,
				role: 'assistant',
				content: `[${activeAgent.handle} via Goose ACP on ${activeAgent.backend}]: Executed request against local node. Telemetry clean, no egress required.`,
				timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
			};
			messages = [...messages, assistantMsg];
		}, 600);
	}

	onMount(() => {
		const navHandler = (e: Event) => {
			const custom = e as CustomEvent<'session' | 'teammates' | 'compute'>;
			if (custom.detail) activeTab = custom.detail;
		};

		const agentHandler = (e: Event) => {
			const custom = e as CustomEvent<string>;
			if (custom.detail) {
				selectedAgentId = custom.detail;
				activeTab = 'session';
			}
		};

		window.addEventListener('cadre:navigate', navHandler);
		window.addEventListener('cadre:select-agent', agentHandler);

		return () => {
			window.removeEventListener('cadre:navigate', navHandler);
			window.removeEventListener('cadre:select-agent', agentHandler);
		};
	});
</script>

<svelte:head>
	<title>Cadre ◈ Autonomous AI Teammates</title>
</svelte:head>

<div class="space-y-6">
	<Header
		{activeTab}
		onTabChange={(tab) => (activeTab = tab)}
		onOpenPalette={() => {
			// Trigger command palette via standard shortcut simulation or dispatch
			window.dispatchEvent(new KeyboardEvent('keydown', { key: 'k', metaKey: true }));
		}}
	/>

	{#if activeTab === 'session'}
		<div class="space-y-4">
			<div class="flex items-center justify-between">
				<div class="flex items-center gap-2">
					<h2 class="text-lg font-bold text-zinc-900 dark:text-zinc-100 flex items-center gap-2">
						<span>Active Pairing Session</span>
						<span class="text-xs px-2 py-0.5 rounded-md font-mono bg-zinc-100 dark:bg-zinc-800 text-zinc-600 dark:text-zinc-400">
							{activeAgent.handle}
						</span>
					</h2>
				</div>

				<!-- Teammate quick switcher dropdown / pills -->
				<div class="flex items-center gap-1.5 bg-zinc-100 dark:bg-zinc-800/80 p-1 rounded-xl border border-zinc-200/60 dark:border-zinc-700/60 text-xs">
					{#each teammates as t (t.id)}
						<button
							type="button"
							onclick={() => (selectedAgentId = t.id)}
							class="px-2.5 py-1 rounded-lg transition-colors cursor-pointer flex items-center gap-1.5 {selectedAgentId === t.id
								? 'bg-white dark:bg-zinc-900 text-zinc-900 dark:text-zinc-100 font-bold shadow-2xs'
								: 'text-zinc-500 hover:text-zinc-900 dark:hover:text-zinc-200'}"
						>
							<span>{t.avatar}</span>
							<span>{t.name}</span>
						</button>
					{/each}
				</div>
			</div>

			<SessionView
				agent={activeAgent}
				{messages}
				onSendMessage={handleSendMessage}
			/>
		</div>
	{:else if activeTab === 'teammates'}
		<div class="space-y-4">
			<div class="flex items-center justify-between">
				<div>
					<h2 class="text-lg font-bold text-zinc-900 dark:text-zinc-100">Private Autonomous Teammates</h2>
					<p class="text-xs text-zinc-500 mt-0.5">
						Team members available in Buzz chat channels and interactive terminal sessions
					</p>
				</div>
			</div>

			<div class="grid grid-cols-1 md:grid-cols-3 gap-5">
				{#each teammates as agent (agent.id)}
					<AgentCard
						{agent}
						onSelect={(a) => {
							selectedAgentId = a.id;
							activeTab = 'session';
						}}
					/>
				{/each}
			</div>
		</div>
	{:else if activeTab === 'compute'}
		<div class="space-y-4">
			<div>
				<h2 class="text-lg font-bold text-zinc-900 dark:text-zinc-100">Fleet Compute & Inference Layer</h2>
				<p class="text-xs text-zinc-500 mt-0.5">
					Local hardware orchestration across Ollama nodes and distributed MeshLLM clusters
				</p>
			</div>

			<ComputeTelemetry nodes={INITIAL_NODES} />
		</div>
	{/if}
</div>
