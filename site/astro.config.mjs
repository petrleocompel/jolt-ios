// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// Served from GitHub Pages as a project site, so every internal link goes
// through `base`.
export default defineConfig({
	site: 'https://petrleocompel.github.io',
	base: '/jolt-ios',
	integrations: [
		starlight({
			title: 'Jolt Remote',
			description: 'An independent iOS companion app for Pavlok wearables.',
			logo: { src: './src/assets/bolt.svg' },
			customCss: ['./src/styles/theme.css'],
			social: [
				{ icon: 'github', label: 'GitHub', href: 'https://github.com/petrleocompel/jolt-ios' },
			],
			sidebar: [
				{ label: 'Home', link: '/' },
				{ label: 'Privacy policy', slug: 'privacy' },
				{ label: 'Support', slug: 'support' },
				{ label: 'Jolt Server', link: 'https://github.com/petrleocompel/jolt-server' },
			],
		}),
	],
});
