export const APP_VERSION = '0.1.0';

export type TabId = 'session' | 'teammates' | 'compute';

export type ConnectionMode = 'checking' | 'live' | 'standby' | 'preview';

export type AgentStatus = 'idle' | 'busy' | 'offline';

export interface AgentTeammate {
	id: string;
	handle: string;
	name: string;
	role: string;
	description: string;
	avatar: string;
	backend: 'ollama' | 'mesh';
	model: string;
	tools: string[];
	status: AgentStatus;
}

export interface ToolCall {
	tool: string;
	input?: string;
	output?: string;
	status?: 'running' | 'completed' | 'failed';
}

export interface ChatMessage {
	id: string;
	role: 'user' | 'assistant' | 'thought';
	content: string;
	isError?: boolean;
	isPreview?: boolean;
	toolCalls?: ToolCall[];
	timestamp: string;
}

export interface ComputeNode {
	id: string;
	host: string;
	nodeType: 'laptop' | 'gpu-box' | 'cluster-peer';
	backend: 'ollama' | 'mesh';
	activeModel: string;
	models?: string[];
	vramUsedGb: number;
	vramTotalGb: number;
	tokensPerSec: number;
	latencyMs: number;
	status: 'healthy' | 'degraded' | 'down' | 'checking' | 'unknown';
}

export interface BackendStatusResponse {
	activeBackend: 'mesh' | 'ollama' | 'standby';
	configuredBackend: 'auto' | 'mesh' | 'ollama';
	defaultModel: string;
	chatEnabled: boolean;
	host: string;
	nodes: ComputeNode[];
}
