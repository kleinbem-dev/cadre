<script lang="ts">
	import type { ComputeNode } from '../types.js';
	import StatusDot from '@kleinbem/web-config/components/StatusDot';

	let {
		nodes = [],
		isReference = false
	}: {
		nodes: ComputeNode[];
		isReference?: boolean;
	} = $props();

	let totalVramUsedNum = $derived(nodes.reduce((acc, n) => acc + n.vramUsedGb, 0));
	let totalVramNum = $derived(nodes.reduce((acc, n) => acc + n.vramTotalGb, 0));
	let totalVramUsed = $derived(totalVramUsedNum.toFixed(1));
	let totalVram = $derived(totalVramNum.toFixed(0));

	let avgThroughput = $derived(
		(nodes.reduce((acc, n) => acc + n.tokensPerSec, 0) / Math.max(1, nodes.length)).toFixed(1)
	);

	let clusterBackendLabel = $derived.by(() => {
		const hasMesh = nodes.some((n) => n.backend === 'mesh');
		const hasOllama = nodes.some((n) => n.backend === 'ollama');
		if (hasMesh && hasOllama) return 'MeshLLM + Ollama';
		if (hasMesh) return 'MeshLLM';
		if (hasOllama) return 'Ollama';
		return 'Standby';
	});

	let activeModelLabel = $derived(nodes[0]?.activeModel || 'idle');
</script>

<div class="space-y-6">
	<div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
		<div class="p-4 rounded-2xl border border-zinc-200/80 dark:border-zinc-800/80 bg-white dark:bg-zinc-900/60 shadow-xs">
			<span class="text-xs text-zinc-500 font-mono">Cluster Backend</span>
			<div class="flex items-center gap-2 mt-1">
				<span class="text-xl font-bold text-zinc-900 dark:text-zinc-50">{clusterBackendLabel}</span>
			</div>
			<span class="text-[11px] text-zinc-400 font-mono mt-1 block">
				{isReference ? 'Reference Fleet Topology' : 'Local Zero-Egress Compute'}
			</span>
		</div>

		<div class="p-4 rounded-2xl border border-zinc-200/80 dark:border-zinc-800/80 bg-white dark:bg-zinc-900/60 shadow-xs">
			<span class="text-xs text-zinc-500 font-mono">Cluster VRAM Allocated</span>
			<div class="flex items-baseline gap-1 mt-1">
				<span class="text-2xl font-bold text-zinc-900 dark:text-zinc-50">{totalVramUsed}</span>
				<span class="text-xs text-zinc-400 font-mono">
					{totalVramNum > 0 ? `/ ${totalVram} GB` : 'GB reported'}
				</span>
			</div>
			<div class="w-full bg-zinc-100 dark:bg-zinc-800 h-1.5 rounded-full mt-2 overflow-hidden">
				<div
					class="bg-amber-500 h-full rounded-full transition-all"
					style="width: {totalVramNum > 0 ? Math.min(100, (totalVramUsedNum / totalVramNum) * 100) : 0}%"
				></div>
			</div>
		</div>

		<div class="p-4 rounded-2xl border border-zinc-200/80 dark:border-zinc-800/80 bg-white dark:bg-zinc-900/60 shadow-xs">
			<span class="text-xs text-zinc-500 font-mono">Mean Generation Speed</span>
			<div class="flex items-baseline gap-1 mt-1">
				<span class="text-2xl font-bold text-emerald-600 dark:text-emerald-400">{avgThroughput}</span>
				<span class="text-xs text-zinc-400 font-mono">tok / sec</span>
			</div>
			<span class="text-[11px] text-zinc-400 font-mono mt-1 block">Local CUDA + Metal compute</span>
		</div>

		<div class="p-4 rounded-2xl border border-zinc-200/80 dark:border-zinc-800/80 bg-white dark:bg-zinc-900/60 shadow-xs">
			<span class="text-xs text-zinc-500 font-mono">Active Model</span>
			<div class="flex items-center gap-1.5 mt-1">
				<span class="text-sm font-bold font-mono text-zinc-900 dark:text-zinc-50 truncate">
					{activeModelLabel}
				</span>
			</div>
			<span class="text-[11px] text-zinc-400 font-mono mt-1 block">
				{nodes.length} {nodes.length === 1 ? 'node' : 'nodes'} visible
			</span>
		</div>
	</div>

	<div>
		<h3 class="text-sm font-bold uppercase tracking-wider text-zinc-400 font-mono mb-3">
			Fleet Compute Nodes ({nodes.length})
		</h3>

		<div class="grid grid-cols-1 md:grid-cols-3 gap-4">
			{#each nodes as node (node.id)}
				<div class="p-5 rounded-2xl border border-zinc-200/80 dark:border-zinc-800/80 bg-white dark:bg-zinc-900/60 shadow-xs flex flex-col justify-between">
					<div>
						<div class="flex items-start justify-between gap-2 mb-3">
							<div class="flex items-center gap-2.5">
								<span aria-hidden="true" class="text-2xl select-none">
									{node.nodeType === 'gpu-box' ? '🖥️' : node.nodeType === 'laptop' ? '💻' : '⚡'}
								</span>
								<div>
									<h4 class="font-bold text-sm text-zinc-900 dark:text-zinc-100">{node.host}</h4>
									<span class="text-[10px] uppercase font-mono px-1.5 py-0.5 rounded bg-zinc-100 dark:bg-zinc-800 text-zinc-500">
										{node.nodeType}
									</span>
								</div>
							</div>

							<div class="flex items-center gap-1.5">
								<StatusDot status={node.status} size="sm" pulse={node.status === 'healthy'} />
								<span class="text-[11px] font-mono text-zinc-400">{node.latencyMs} ms</span>
							</div>
						</div>

						<div class="space-y-2 mt-4 text-xs font-mono">
							<div class="flex items-center justify-between text-zinc-500">
								<span>Backend</span>
								<span class="text-zinc-800 dark:text-zinc-200 uppercase">{node.backend}</span>
							</div>

							<div class="flex items-center justify-between text-zinc-500 gap-2">
								<span class="shrink-0">Model</span>
								<span class="text-zinc-800 dark:text-zinc-200 truncate">{node.activeModel}</span>
							</div>

							<div class="flex items-center justify-between text-zinc-500">
								<span>Throughput</span>
								<span class="text-emerald-600 dark:text-emerald-400 font-bold">
									{node.tokensPerSec > 0 ? `${node.tokensPerSec} tok/s` : 'on-demand'}
								</span>
							</div>

							<div class="pt-2">
								<div class="flex items-center justify-between text-[11px] text-zinc-400 mb-1">
									<span>VRAM Usage</span>
									<span>
										{node.vramTotalGb > 0
											? `${node.vramUsedGb} / ${node.vramTotalGb} GB`
											: node.vramUsedGb > 0
												? `${node.vramUsedGb} GB allocated`
												: 'host-managed'}
									</span>
								</div>
								<div class="w-full bg-zinc-100 dark:bg-zinc-800 h-1.5 rounded-full overflow-hidden">
									<div
										class="bg-amber-500 h-full rounded-full"
										style="width: {node.vramTotalGb > 0 ? Math.min(100, Math.round((node.vramUsedGb / node.vramTotalGb) * 100)) : 0}%"
									></div>
								</div>
							</div>
						</div>
					</div>

					<div class="mt-4 pt-3 border-t border-zinc-100 dark:border-zinc-800/60 flex items-center justify-between text-[11px] text-zinc-400 font-mono">
						<span>Peer ID: {node.id}</span>
						<span class={node.status === 'healthy' ? 'text-emerald-500' : node.status === 'down' ? 'text-red-500' : 'text-amber-500'}>
							{node.status === 'healthy' ? 'Online' : node.status}
						</span>
					</div>
				</div>
			{/each}
		</div>
	</div>
</div>
