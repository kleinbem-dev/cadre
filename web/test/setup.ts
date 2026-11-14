import { existsSync, readFileSync } from 'node:fs';
import { registerHooks, stripTypeScriptTypes } from 'node:module';
import { dirname, resolve as resolvePath } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { compile, compileModule } from 'svelte/compiler';

const ROOT = resolvePath(dirname(fileURLToPath(import.meta.url)), '..');
const ROOT_PKG_URL = pathToFileURL(resolvePath(ROOT, 'package.json')).href;

function tryFileWithTs(candidatePath: string): string | null {
	if (existsSync(candidatePath) && !candidatePath.endsWith('/')) {
		return pathToFileURL(candidatePath).href;
	}
	const stripped = candidatePath.replace(/\.js$/, '');
	for (const base of stripped !== candidatePath ? [stripped, candidatePath] : [candidatePath]) {
		for (const ext of ['.ts', '.js', '/index.ts', '/index.js']) {
			if (existsSync(base + ext)) {
				return pathToFileURL(base + ext).href;
			}
		}
	}
	return null;
}

registerHooks({
	resolve(specifier, context, nextResolve) {
		if (specifier === '#lib') {
			return { shortCircuit: true, url: pathToFileURL(resolvePath(ROOT, 'src/lib/index.ts')).href };
		}
		if (specifier.startsWith('#lib/')) {
			const hit = tryFileWithTs(resolvePath(ROOT, 'src/lib', specifier.slice('#lib/'.length)));
			if (hit) return { shortCircuit: true, url: hit };
		}
		if (
			(specifier.startsWith('./') || specifier.startsWith('../')) &&
			context.parentURL?.startsWith('file:')
		) {
			const parentDir = dirname(fileURLToPath(context.parentURL));
			const hit = tryFileWithTs(resolvePath(parentDir, specifier));
			if (hit) return { shortCircuit: true, url: hit };
		}
		const withSvelte = {
			...context,
			conditions: [...(context.conditions ?? []), 'svelte']
		};
		try {
			return nextResolve(specifier, withSvelte);
		} catch (err) {
			if (!specifier.startsWith('.') && !specifier.startsWith('/') && context.parentURL !== ROOT_PKG_URL) {
				return nextResolve(specifier, { ...withSvelte, parentURL: ROOT_PKG_URL });
			}
			throw err;
		}
	},
	load(url, context, nextLoad) {
		if (url.endsWith('.svelte.js') || url.endsWith('.svelte.ts')) {
			const filename = fileURLToPath(url);
			const raw = readFileSync(filename, 'utf8');
			const source = url.endsWith('.ts') ? stripTypeScriptTypes(raw) : raw;
			const compiled = compileModule(source, {
				filename,
				generate: 'server'
			});
			return {
				format: 'module',
				shortCircuit: true,
				source: compiled.js.code
			};
		}
		if (url.endsWith('.svelte')) {
			const filename = fileURLToPath(url);
			const source = readFileSync(filename, 'utf8');
			const compiled = compile(source, {
				filename,
				generate: 'server',
				runes: filename.includes('node_modules') ? undefined : true
			});
			return {
				format: 'module',
				shortCircuit: true,
				source: compiled.js.code
			};
		}
		return nextLoad(url, context);
	}
});
