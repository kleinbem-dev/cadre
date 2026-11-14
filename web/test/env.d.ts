declare module 'node:test' {
	export function describe(name: string, fn: () => void | Promise<void>): Promise<void>;
	export function it(name: string, fn: () => void | Promise<void>): Promise<void>;
	export function beforeEach(fn: () => void | Promise<void>): void;
	export function afterEach(fn: () => void | Promise<void>): void;
}

declare module 'node:assert/strict' {
	export function equal<T>(actual: unknown, expected: T, message?: string): asserts actual is T;
	export function deepEqual<T>(actual: unknown, expected: T, message?: string): asserts actual is T;
	export function ok(value: unknown, message?: string): asserts value;
	export function match(string: string, regexp: RegExp, message?: string): void;
	export function doesNotMatch(string: string, regexp: RegExp, message?: string): void;
	export function throws(block: () => unknown, error?: RegExp | ErrorConstructor, message?: string): void;
	export function rejects(
		block: (() => Promise<unknown>) | Promise<unknown>,
		error?: RegExp | ErrorConstructor,
		message?: string
	): Promise<void>;
}

declare module 'node:fs' {
	export function existsSync(path: string): boolean;
	export function readFileSync(path: string, encoding: 'utf8'): string;
	export function readdirSync(path: string, options?: { recursive?: boolean }): string[];
}

declare module 'node:path' {
	export function dirname(path: string): string;
	export function resolve(...paths: string[]): string;
}

declare module 'node:url' {
	export function fileURLToPath(url: string | URL): string;
	export function pathToFileURL(path: string): URL;
}

declare module 'node:module' {
	export interface ResolveContext {
		conditions?: string[];
		parentURL?: string;
	}
	export interface ResolveResult {
		shortCircuit?: boolean;
		url: string;
	}
	export interface LoadResult {
		format: string;
		shortCircuit?: boolean;
		source: string;
	}
	export function stripTypeScriptTypes(
		code: string,
		options?: { mode?: 'strip' | 'transform' }
	): string;
	export function registerHooks(hooks: {
		resolve?: (
			specifier: string,
			context: ResolveContext,
			nextResolve: (specifier: string, context?: ResolveContext) => ResolveResult
		) => ResolveResult;
		load?: (
			url: string,
			context: Record<string, unknown>,
			nextLoad: (url: string, context?: Record<string, unknown>) => LoadResult
		) => LoadResult;
	}): void;
}

declare module 'node:vm' {
	export function runInNewContext(code: string, contextObject?: Record<string, unknown>): unknown;
}
