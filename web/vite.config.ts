import adapter from '@sveltejs/adapter-static';
import { sveltekit } from '@sveltejs/kit/vite';
import tailwindcss from '@tailwindcss/vite';
import { defineConfig } from 'vite';

export default defineConfig({
	plugins: [
		tailwindcss(),
		sveltekit({
			adapter: adapter({
				fallback: '200.html',
				pages: 'build',
				assets: 'build',
				strict: true
			}),
			compilerOptions: {
				experimental: {
					async: true
				},
				fragments: 'html'
			},
			dynamicCompileOptions({ filename }) {
				if (!filename.includes('node_modules')) {
					return { runes: true };
				}
			},
			experimental: {
				forkPreloads: true
			}
		})
	],
	server: {
		proxy: {
			'/v1': 'http://127.0.0.1:9337',
			'/api': 'http://127.0.0.1:9337'
		}
	}
});
