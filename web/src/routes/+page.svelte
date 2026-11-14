<script lang="ts">
	import AgentCard from '#lib/components/AgentCard.svelte';
	import SessionView from '#lib/components/SessionView.svelte';
	import ComputeTelemetry from '#lib/components/ComputeTelemetry.svelte';
	import { cadre } from '#lib/state.svelte.js';
</script>

<svelte:head>
	<title>Cadre ◈ Autonomous AI Teammates</title>
</svelte:head>

<div class="space-y-6">
	{#if cadre.activeTab === 'session'}
		<div id="panel-session" role="tabpanel" aria-labelledby="tab-session" class="space-y-4">
			<div class="flex flex-wrap items-center justify-between gap-3">
				<h2 class="text-lg font-bold text-zinc-900 dark:text-zinc-100 flex items-center gap-2">
					<span>Active Pairing Session</span>
					<span class="text-xs px-2 py-0.5 rounded-md font-mono bg-zinc-100 dark:bg-zinc-800 text-zinc-600 dark:text-zinc-400">
						{cadre.activeAgent.handle}
					</span>
				</h2>

				<div
					role="group"
					aria-label="Select active teammate"
					class="flex items-center gap-1.5 bg-zinc-100 dark:bg-zinc-800/80 p-1 rounded-xl border border-zinc-200/60 dark:border-zinc-700/60 text-xs"
				>
					{#each cadre.teammates as t (t.id)}
						<button
							type="button"
							aria-pressed={cadre.selectedAgentId === t.id}
							onclick={() => cadre.selectAgent(t.id)}
							class="px-2.5 py-1 rounded-lg transition-colors cursor-pointer flex items-center gap-1.5 {cadre.selectedAgentId === t.id
								? 'bg-white dark:bg-zinc-900 text-zinc-900 dark:text-zinc-100 font-bold shadow-2xs'
								: 'text-zinc-500 hover:text-zinc-900 dark:hover:text-zinc-200'}"
						>
							<span aria-hidden="true">{t.avatar}</span>
							<span>{t.name}</span>
						</button>
					{/each}
				</div>
			</div>

			<SessionView
				agent={cadre.activeAgent}
				messages={cadre.messages}
				sending={cadre.sending}
				connectionMode={cadre.connectionMode}
				chatEnabled={cadre.chatEnabled}
				onSendMessage={(text) => {
					void cadre.sendMessage(text);
				}}
			/>
		</div>
	{:else if cadre.activeTab === 'teammates'}
		<div id="panel-teammates" role="tabpanel" aria-labelledby="tab-teammates" class="space-y-4">
			<div>
				<h2 class="text-lg font-bold text-zinc-900 dark:text-zinc-100">Private Autonomous Teammates</h2>
				<p class="text-xs text-zinc-500 mt-0.5">
					Team members available in Buzz chat channels and interactive terminal sessions
				</p>
			</div>

			<div class="grid grid-cols-1 md:grid-cols-3 gap-5">
				{#each cadre.teammates as agent (agent.id)}
					<AgentCard
						{agent}
						onSelect={(a) => cadre.selectAgent(a.id)}
					/>
				{/each}
			</div>
		</div>
	{:else}
		<div id="panel-compute" role="tabpanel" aria-labelledby="tab-compute" class="space-y-4">
			<div class="flex flex-wrap items-center justify-between gap-3">
				<div>
					<div class="flex items-center gap-2">
						<h2 class="text-lg font-bold text-zinc-900 dark:text-zinc-100">Fleet Compute & Inference Layer</h2>
						<span
							class="text-[11px] font-mono px-2 py-0.5 rounded-md border {cadre.isReferenceNodes
								? 'bg-zinc-100 dark:bg-zinc-800 text-zinc-500 border-zinc-200 dark:border-zinc-700'
								: 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border-emerald-500/20'}"
						>
							{cadre.isReferenceNodes
								? cadre.connectionMode === 'standby'
									? 'Reference Topology · Host Standby'
									: 'Reference Topology'
								: 'Live Local Node'}
						</span>
					</div>
					<p class="text-xs text-zinc-500 mt-0.5">
						Local hardware orchestration across Ollama nodes and distributed MeshLLM clusters
					</p>
				</div>

				<button
					type="button"
					disabled={cadre.refreshing}
					onclick={() => {
						void cadre.refreshStatus(true);
					}}
					class="px-3 py-1.5 rounded-xl border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:bg-zinc-50 dark:hover:bg-zinc-800 disabled:opacity-50 text-xs font-mono text-zinc-600 dark:text-zinc-300 transition-colors cursor-pointer"
				>
					{cadre.refreshing ? 'Refreshing…' : '↻ Refresh Status'}
				</button>
			</div>

			<ComputeTelemetry nodes={cadre.nodes} isReference={cadre.isReferenceNodes} />
		</div>
	{/if}
</div>
