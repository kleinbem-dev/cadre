<script lang="ts">
	import ThemeToggle from '@kleinbem/web-config/theme/toggle';
	import FontSizeToggle from '@kleinbem/web-config/font-size/toggle';
	import StatusDot from '@kleinbem/web-config/components/StatusDot';

	let {
		activeTab = 'session',
		onTabChange,
		onOpenPalette
	}: {
		activeTab: 'session' | 'teammates' | 'compute';
		onTabChange: (tab: 'session' | 'teammates' | 'compute') => void;
		onOpenPalette: () => void;
	} = $props();
</script>

<header class="sticky top-0 z-40 w-full border-b border-zinc-200/80 dark:border-zinc-800/80 bg-white/80 dark:bg-zinc-950/80 backdrop-blur-md">
	<div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between gap-4">
		<!-- Brand & Logo -->
		<div class="flex items-center gap-3">
			<div class="h-9 w-9 rounded-xl bg-amber-500/10 border border-amber-500/30 flex items-center justify-center text-amber-500 font-bold text-lg select-none shadow-xs">
				◈
			</div>
			<div>
				<div class="flex items-center gap-2">
					<h1 class="font-bold text-base tracking-tight text-zinc-900 dark:text-zinc-50 flex items-center gap-1.5">
						Cadre
					</h1>
					<span class="text-[10px] uppercase tracking-wider px-1.5 py-0.2 font-mono font-medium rounded bg-amber-500/10 text-amber-600 dark:text-amber-400 border border-amber-500/20">
						v0.1.0
					</span>
				</div>
				<p class="text-[11px] text-zinc-500 font-mono hidden sm:block">
					private AI teammates on your own compute
				</p>
			</div>
		</div>

		<!-- Center Navigation Tabs -->
		<nav class="flex items-center gap-1 bg-zinc-100/80 dark:bg-zinc-900/80 p-1 rounded-xl border border-zinc-200/60 dark:border-zinc-800/60 text-xs font-medium">
			<button
				type="button"
				onclick={() => onTabChange('session')}
				class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg transition-colors cursor-pointer {activeTab === 'session'
					? 'bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 shadow-2xs font-semibold'
					: 'text-zinc-600 dark:text-zinc-400 hover:text-zinc-900 dark:hover:text-zinc-200'}"
			>
				<span>💬</span>
				<span>Session</span>
			</button>

			<button
				type="button"
				onclick={() => onTabChange('teammates')}
				class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg transition-colors cursor-pointer {activeTab === 'teammates'
					? 'bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 shadow-2xs font-semibold'
					: 'text-zinc-600 dark:text-zinc-400 hover:text-zinc-900 dark:hover:text-zinc-200'}"
			>
				<span>👥</span>
				<span>Teammates</span>
			</button>

			<button
				type="button"
				onclick={() => onTabChange('compute')}
				class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg transition-colors cursor-pointer {activeTab === 'compute'
					? 'bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 shadow-2xs font-semibold'
					: 'text-zinc-600 dark:text-zinc-400 hover:text-zinc-900 dark:hover:text-zinc-200'}"
			>
				<StatusDot status="healthy" size="sm" pulse />
				<span>Compute</span>
			</button>
		</nav>

		<!-- Actions -->
		<div class="flex items-center gap-2">
			<!-- Search / Command Palette button -->
			<button
				type="button"
				onclick={onOpenPalette}
				class="flex items-center gap-2 px-2.5 py-1.5 rounded-xl border border-zinc-200 dark:border-zinc-800 bg-zinc-50 dark:bg-zinc-900 hover:bg-zinc-100 dark:hover:bg-zinc-800/80 text-zinc-500 dark:text-zinc-400 text-xs transition-colors cursor-pointer"
				title="Open Command Palette (⌘K)"
			>
				<svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
					<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
				</svg>
				<span class="hidden md:inline font-mono text-[11px]">⌘K</span>
			</button>

			<FontSizeToggle />
			<ThemeToggle />
		</div>
	</div>
</header>
