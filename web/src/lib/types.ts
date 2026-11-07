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
	role: 'user' | 'assistant' | 'tool' | 'thought';
	content: string;
	toolCalls?: ToolCall[];
	timestamp: string;
}

export interface ComputeNode {
	id: string;
	host: string;
	nodeType: 'laptop' | 'gpu-box' | 'cluster-peer';
	backend: 'ollama' | 'mesh';
	activeModel: string;
	vramUsedGb: number;
	vramTotalGb: number;
	tokensPerSec: number;
	latencyMs: number;
	status: 'healthy' | 'degraded' | 'down' | 'checking' | 'unknown';
}

export interface CadreSession {
	id: string;
	title: string;
	agentHandle: string;
	createdAt: string;
	messageCount: number;
}
