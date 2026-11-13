import { defineWebConfig } from '@kleinbem/web-config/vite';

export default defineWebConfig({
	adapterOptions: {
		fallback: '200.html',
		pages: 'build',
		assets: 'build'
	},
	server: {
		proxy: {
			'/v1': 'http://127.0.0.1:9337',
			'/api': 'http://127.0.0.1:9337'
		}
	}
});
