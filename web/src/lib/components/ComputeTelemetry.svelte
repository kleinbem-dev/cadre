<script lang="ts">
	import type { ComputeNode } from '../types.js';
	import StatusDot from '@kleinbem/web-config/components/StatusDot';

	let {
		nodes = []
	}: {
		nodes: ComputeNode[];
	} = $props();

	let totalVramUsed = $derived(
		nodes.reduce((acc, n) => acc + n.vramUsedGb, 0).toFixed(1)
	);

	let totalVram = $derived(
		nodes.reduce((acc, n) => acc + n.vramTotalGb, 0).toFixed(0)
	);

	let avgThroughput = $derived(
		(nodes.reduce((acc, n) => acc + n.tokensPerSec, 0) / Math.max(1, nodes.length)).toFixed(1)
	);
</script>

<div class="space-y-6">
	<!-- High Level Telemetry KPI Row -->
	<div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
		<div class="p-4 rounded-2xl border border-zinc-200/80 dark:border-zinc-800/80 bg-white dark:bg-zinc-900/60 shadow-xs">
			<span class="text-xs text-zinc-500 font-mono">Cluster Backend</span>
			<div class="flex items-center gap-2 mt-1">
				<span class="text-xl font-bold text-zinc-900 dark:text-zinc-50">MeshLLM + Ollama</span>
			</div>
			<span class="text-[11px] text-zinc-400 font-mono mt-1 block">P2P Distributed Fleet</span>
		</div>

		<div class="p-4 rounded-2xl border border-zinc-200/80 dark:border-zinc-800/80 bg-white dark:bg-zinc-900/60 shadow-xs">
			<span class="text-xs text-zinc-500 font-mono">Cluster VRAM Allocated</span>
			<div class="flex items-baseline gap-1 mt-1">
				<span class="text-2xl font-bold text-zinc-900 dark:text-zinc-50">{totalVramUsed}</span>
				<span class="text-xs text-zinc-400 font-mono">/ {totalVram} GB</span>
			</div>
			<div class="w-full bg-zinc-100 dark:bg-zinc-800 h-1.5 rounded-full mt-2 overflow-hidden">
				<div
					class="bg-amber-500 h-full rounded-full transition-all"
					style="width: {(parseFloat(totalVramUsed) / Math.max(1, parseFloat(totalVram))) * 100}%"
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
				<span class="text-sm font-bold font-mono text-zinc-900 dark:text-zinc-50 truncate">Qwen3-8B-Q4_K_M</span>
			</div>
			<span class="text-[11px] text-zinc-400 font-mono mt-1 block">Mesh sharded layers</span>
		</div>
	</div>

	<!-- Compute Nodes Detailed Grid -->
	<div>
		<h2 class="text-sm font-bold uppercase tracking-wider text-zinc-400 font-mono mb-3">
			Fleet Compute Nodes ({nodes.length})
		</h2>

		<div class="grid grid-cols-1 md:grid-cols-3 gap-4">
			{#each nodes as node (node.id)}
				<div class="p-5 rounded-2xl border border-zinc-200/80 dark:border-zinc-800/80 bg-white dark:bg-zinc-900/60 shadow-xs flex flex-col justify-between">
					<div>
						<div class="flex items-start justify-between gap-2 mb-3">
							<div class="flex items-center gap-2.5">
								<span class="text-2xl select-none">
									{node.nodeType === 'gpu-box' ? '🖥️' : node.nodeType === 'laptop' ? '💻' : '⚡'}
								</span>
								<div>
									<h3 class="font-bold text-sm text-zinc-900 dark:text-zinc-100">{node.host}</h3>
									<span class="text-[10px] uppercase font-mono px-1.5 py-0.2 rounded bg-zinc-100 dark:bg-zinc-800 text-zinc-500">
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

							<div class="flex items-center justify-between text-zinc-500">
								<span>Model</span>
								<span class="text-zinc-800 dark:text-zinc-200 truncate max-w-[150px]">{node.activeModel}</span>
							</div>

							<div class="flex items-center justify-between text-zinc-500">
								<span>Throughput</span>
								<span class="text-emerald-600 dark:text-emerald-400 font-bold">{node.tokensPerSec} tok/s</span>
							</div>

							<div class="pt-2">
								<div class="flex items-center justify-between text-[11px] text-zinc-400 mb-1">
									<span>VRAM Usage</span>
									<span>{node.vramUsedGb} / {node.vramTotalGb} GB</span>
								</div>
								<div class="w-full bg-zinc-100 dark:bg-zinc-800 h-1.5 rounded-full overflow-hidden">
									<div
										class="bg-amber-500 h-full rounded-full"
										style="width: {(node.vramUsedGb / node.vramTotalGb) * 100}%"
									></div>
								</div>
							</div>
						</div>
					</div>

					<div class="mt-4 pt-3 border-t border-zinc-100 dark:border-zinc-800/60 flex items-center justify-between text-[11px] text-zinc-400 font-mono">
						<span>Peer ID: {node.id}</span>
						<span class="text-emerald-500">Online</span>
					</div>
				</div>
			{/each}
		</div>
	</div>
</div>
