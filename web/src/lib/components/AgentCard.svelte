<script lang="ts">
	import type { AgentTeammate } from '../types.js';
	import StatusDot from '@kleinbem/web-config/components/StatusDot';

	let {
		agent,
		onSelect
	}: {
		agent: AgentTeammate;
		onSelect?: (agent: AgentTeammate) => void;
	} = $props();

	let isMesh = $derived(agent.backend === 'mesh');
</script>

<div
	class="group relative flex flex-col justify-between p-5 rounded-2xl border border-zinc-200/80 dark:border-zinc-800/80 bg-white dark:bg-zinc-900/60 hover:bg-zinc-50/50 dark:hover:bg-zinc-900 shadow-xs hover:shadow-md transition-all duration-150 hover:-translate-y-0.5"
>
	<div>
		<div class="flex items-start justify-between gap-3 mb-3">
			<div class="flex items-center gap-3">
				<div class="h-10 w-10 rounded-xl bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center text-xl select-none shrink-0 group-hover:scale-105 transition-transform">
					{agent.avatar}
				</div>
				<div>
					<div class="flex items-center gap-2">
						<h3 class="font-bold text-sm text-zinc-900 dark:text-zinc-100">{agent.name}</h3>
						<span class="text-xs font-mono text-amber-600 dark:text-amber-400">{agent.handle}</span>
					</div>
					<p class="text-xs text-zinc-500 mt-0.5">{agent.role}</p>
				</div>
			</div>

			<div class="flex items-center gap-1.5 shrink-0">
				<StatusDot status={agent.status === 'busy' ? 'checking' : agent.status === 'offline' ? 'down' : 'healthy'} size="sm" pulse={agent.status === 'busy'} />
				<span class="text-[10px] font-mono text-zinc-400 uppercase tracking-wider">{agent.status}</span>
			</div>
		</div>

		<p class="text-xs text-zinc-600 dark:text-zinc-300 leading-relaxed mb-4">
			{agent.description}
		</p>
	</div>

	<div class="pt-3 border-t border-zinc-100 dark:border-zinc-800/60 flex flex-col gap-2.5 text-xs">
		<!-- Backend & Model info -->
		<div class="flex items-center justify-between text-[11px] font-mono">
			<span class="text-zinc-400">Model</span>
			<span class="px-1.5 py-0.5 rounded bg-zinc-100 dark:bg-zinc-800 text-zinc-700 dark:text-zinc-300">
				{agent.model}
			</span>
		</div>

		<div class="flex items-center justify-between text-[11px] font-mono">
			<span class="text-zinc-400">Engine</span>
			<span class="px-1.5 py-0.5 rounded {isMesh ? 'bg-indigo-500/10 text-indigo-600 dark:text-indigo-400 border border-indigo-500/20' : 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border border-emerald-500/20'}">
				{isMesh ? 'MeshLLM cluster' : 'Ollama local'}
			</span>
		</div>

		<!-- Tools -->
		<div class="flex flex-wrap gap-1 mt-1">
			{#each agent.tools as tool}
				<span class="px-1.5 py-0.5 text-[10px] font-mono rounded bg-zinc-100 dark:bg-zinc-800 text-zinc-500 dark:text-zinc-400 border border-zinc-200/50 dark:border-zinc-700/50">
					{tool}
				</span>
			{/each}
		</div>

		{#if onSelect}
			<button
				type="button"
				onclick={() => onSelect(agent)}
				class="mt-2 w-full py-1.5 px-3 rounded-xl bg-zinc-900 dark:bg-zinc-100 hover:bg-zinc-800 dark:hover:bg-white text-white dark:text-zinc-900 font-medium text-xs transition-colors cursor-pointer text-center"
			>
				Start Pairing Session
			</button>
		{/if}
	</div>
</div>
