<script lang="ts">
	import '../app.css';
	import { onMount } from 'svelte';
	import { theme } from '@kleinbem/web-config/theme/state';
	import CommandPalette from '@kleinbem/web-config/components/CommandPalette';
	import type { CommandItem } from '@kleinbem/web-config/components/CommandPalette';
	import Header from '#lib/components/Header.svelte';
	import { cadre } from '#lib/state.svelte.js';

	let { children } = $props();

	$effect(() => {
		const active = theme.current;
		document.documentElement.dataset.theme = active;
		document.documentElement.classList.toggle('dark', active === 'dark');
		document.documentElement.classList.toggle('light', active === 'light');
	});

	onMount(() => {
		void cadre.refreshStatus();
	});

	const commandItems: CommandItem[] = [
		{
			id: 'agent-lead',
			title: 'Switch to @cadre (Lead Pairing)',
			category: 'Teammates',
			icon: '◈',
			badge: 'MeshLLM',
			onSelect: () => cadre.selectAgent('cadre-core')
		},
		{
			id: 'agent-code',
			title: 'Switch to @cadre-code (Refactoring)',
			category: 'Teammates',
			icon: '⚡',
			badge: 'Ollama',
			onSelect: () => cadre.selectAgent('cadre-code')
		},
		{
			id: 'agent-fleet',
			title: 'Switch to @cadre-fleet (Nix & Ops)',
			category: 'Teammates',
			icon: '🛡️',
			badge: 'MeshLLM',
			onSelect: () => cadre.selectAgent('cadre-fleet')
		},
		{
			id: 'tab-session',
			title: 'View Pairing Session',
			category: 'Navigation',
			icon: '💬',
			onSelect: () => cadre.setTab('session')
		},
		{
			id: 'tab-teammates',
			title: 'View Teammates Overview',
			category: 'Navigation',
			icon: '👥',
			onSelect: () => cadre.setTab('teammates')
		},
		{
			id: 'tab-compute',
			title: 'View Fleet Compute & VRAM',
			category: 'Navigation',
			icon: '📊',
			onSelect: () => cadre.setTab('compute')
		},
		{
			id: 'action-refresh',
			title: 'Refresh Local Inference Status',
			category: 'Actions',
			icon: '↻',
			onSelect: () => {
				void cadre.refreshStatus(true);
			}
		},
		{
			id: 'link-foyer',
			title: 'Open Foyer Homelab Portal',
			category: 'Fleet',
			icon: '🏠',
			url: 'https://home.kleinbem.dev',
			external: true
		},
		{
			id: 'link-status',
			title: 'Open Gatus Fleet Status',
			category: 'Fleet',
			icon: '📈',
			url: 'https://status.kleinbem.dev',
			external: true
		},
		{
			id: 'link-github',
			title: 'Cadre Source Code (GitHub)',
			category: 'Help',
			icon: '🐙',
			url: 'https://github.com/kleinbem-dev/cadre',
			external: true
		}
	];
</script>

<a
	href="#main-content"
	class="sr-only focus:not-sr-only focus:fixed focus:top-3 focus:left-3 focus:z-50 focus:rounded-lg focus:bg-amber-500 focus:px-3 focus:py-2 focus:text-xs focus:font-semibold focus:text-zinc-950 focus:shadow-lg"
>
	Skip to main content
</a>

<div class="min-h-screen flex flex-col bg-zinc-50 dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 antialiased selection:bg-amber-500/20 selection:text-amber-500">
	<Header
		activeTab={cadre.activeTab}
		connectionMode={cadre.connectionMode}
		statusLabel={cadre.statusLabel}
		onTabChange={(tab) => cadre.setTab(tab)}
		onOpenPalette={() => (cadre.commandPaletteOpen = true)}
	/>

	<main id="main-content" tabindex="-1" class="flex-1 w-full max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6 outline-none">
		{@render children()}
	</main>

	<footer class="py-6 border-t border-zinc-200/60 dark:border-zinc-800/60 text-center text-xs text-zinc-400 font-mono">
		<div class="flex items-center justify-center gap-3">
			<span class="font-bold text-zinc-500 dark:text-zinc-300">cadre ◈</span>
			<span>•</span>
			<span>private AI teammates on your own compute</span>
			<span>•</span>
			<a
				href="https://github.com/kleinbem-dev/cadre"
				target="_blank"
				rel="noopener noreferrer"
				class="hover:underline text-zinc-500 dark:text-zinc-400 hover:text-zinc-800 dark:hover:text-zinc-200"
			>
				source
			</a>
		</div>
	</footer>

	<CommandPalette items={commandItems} bind:open={cadre.commandPaletteOpen} />
</div>
