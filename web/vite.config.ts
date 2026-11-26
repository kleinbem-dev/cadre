import { defineWebConfig } from '@kleinbem/web-config/vite';

export default defineWebConfig({
	server: {
		proxy: {
			'/v1': 'http://127.0.0.1:9337',
			'/api': 'http://127.0.0.1:9337'
		}
	}
});
