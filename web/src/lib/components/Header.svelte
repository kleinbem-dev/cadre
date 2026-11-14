<script lang="ts">
	import ThemeToggle from '@kleinbem/web-config/theme/toggle';
	import FontSizeToggle from '@kleinbem/web-config/font-size/toggle';
	import StatusDot from '@kleinbem/web-config/components/StatusDot';
	import { APP_VERSION, type ConnectionMode, type TabId } from '../types.js';

	let {
		activeTab = 'session',
		connectionMode = 'preview',
		statusLabel = '',
		onTabChange,
		onOpenPalette
	}: {
		activeTab: TabId;
		connectionMode?: ConnectionMode;
		statusLabel?: string;
		onTabChange: (tab: TabId) => void;
		onOpenPalette: () => void;
	} = $props();

	const TABS: { id: TabId; label: string }[] = [
		{ id: 'session', label: 'Session' },
		{ id: 'teammates', label: 'Teammates' },
		{ id: 'compute', label: 'Compute' }
	];

	let computeDotStatus = $derived<'healthy' | 'checking' | 'unknown'>(
		connectionMode === 'live'
			? 'healthy'
			: connectionMode === 'checking'
				? 'checking'
				: 'unknown'
	);

	function handleTabKeydown(e: KeyboardEvent, index: number) {
		let nextIndex = -1;
		if (e.key === 'ArrowRight') nextIndex = (index + 1) % TABS.length;
		else if (e.key === 'ArrowLeft') nextIndex = (index - 1 + TABS.length) % TABS.length;
		else if (e.key === 'Home') nextIndex = 0;
		else if (e.key === 'End') nextIndex = TABS.length - 1;
		if (nextIndex < 0) return;

		e.preventDefault();
		const target = TABS[nextIndex];
		onTabChange(target.id);
		document.getElementById(`tab-${target.id}`)?.focus();
	}
</script>

<header class="sticky top-0 z-40 w-full border-b border-zinc-200/80 dark:border-zinc-800/80 bg-white/80 dark:bg-zinc-950/80 backdrop-blur-md">
	<div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between gap-3">
		<div class="flex items-center gap-3 min-w-0">
			<div
				aria-hidden="true"
				class="h-9 w-9 shrink-0 rounded-xl bg-amber-500/10 border border-amber-500/30 flex items-center justify-center text-amber-500 font-bold text-lg select-none shadow-xs"
			>
				◈
			</div>
			<div class="min-w-0">
				<div class="flex items-center gap-2">
					<h1 class="font-bold text-base tracking-tight text-zinc-900 dark:text-zinc-50">
						Cadre
					</h1>
					<span class="text-[10px] uppercase tracking-wider px-1.5 py-0.5 font-mono font-medium rounded bg-amber-500/10 text-amber-600 dark:text-amber-400 border border-amber-500/20">
						v{APP_VERSION}
					</span>
				</div>
				<p class="text-[11px] text-zinc-500 font-mono hidden md:block truncate">
					{statusLabel || 'private AI teammates on your own compute'}
				</p>
			</div>
		</div>

		<div
			role="tablist"
			aria-label="Cadre workspace views"
			class="flex items-center gap-1 bg-zinc-100/80 dark:bg-zinc-900/80 p-1 rounded-xl border border-zinc-200/60 dark:border-zinc-800/60 text-xs font-medium"
		>
			{#each TABS as tab, idx (tab.id)}
				<button
					id="tab-{tab.id}"
					type="button"
					role="tab"
					aria-selected={activeTab === tab.id}
					aria-controls="panel-{tab.id}"
					tabindex={activeTab === tab.id ? 0 : -1}
					onclick={() => onTabChange(tab.id)}
					onkeydown={(e) => handleTabKeydown(e, idx)}
					class="flex items-center gap-1.5 px-2.5 sm:px-3 py-1.5 rounded-lg transition-colors cursor-pointer {activeTab === tab.id
						? 'bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 shadow-2xs font-semibold'
						: 'text-zinc-600 dark:text-zinc-400 hover:text-zinc-900 dark:hover:text-zinc-200'}"
				>
					{#if tab.id === 'session'}
						<span aria-hidden="true">💬</span>
					{:else if tab.id === 'teammates'}
						<span aria-hidden="true">👥</span>
					{:else}
						<StatusDot status={computeDotStatus} size="sm" pulse={connectionMode === 'live'} />
					{/if}
					<span>{tab.label}</span>
				</button>
			{/each}
		</div>

		<div class="flex items-center gap-2 shrink-0">
			<button
				type="button"
				onclick={onOpenPalette}
				aria-label="Open Command Palette"
				aria-keyshortcuts="Meta+K Control+K"
				title="Open Command Palette (⌘K)"
				class="flex items-center gap-2 px-2.5 py-1.5 rounded-xl border border-zinc-200 dark:border-zinc-800 bg-zinc-50 dark:bg-zinc-900 hover:bg-zinc-100 dark:hover:bg-zinc-800/80 text-zinc-500 dark:text-zinc-400 text-xs transition-colors cursor-pointer"
			>
				<svg aria-hidden="true" class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
					<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
				</svg>
				<span class="hidden md:inline font-mono text-[11px]">⌘K</span>
			</button>

			<FontSizeToggle />
			<ThemeToggle />
		</div>
	</div>
</header>
