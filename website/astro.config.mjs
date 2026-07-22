import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import tailwind from '@astrojs/tailwind';

export default defineConfig({
  site: 'https://rosewood-editor.dev',
  integrations: [
    starlight({
      title: 'Rosewood',
      logo: {
        dark: './src/assets/logo-dark.svg',
        light: './src/assets/logo-light.svg',
        alt: 'Rosewood Editor',
      },
      social: {
        github: 'https://github.com/abdul-hamid-achik/rosewood',
      },
      sidebar: [
        {
          label: 'Guides',
          items: [
            { label: 'Getting Started', slug: 'guides/getting-started' },
            { label: 'Features & Usage', slug: 'guides/features' },
            { label: 'Configuration', slug: 'guides/configuration' },
            { label: 'Dependencies', slug: 'guides/dependencies' },
            { label: 'Troubleshooting', slug: 'guides/troubleshooting' },
          ],
        },
        {
          label: 'Reference',
          items: [
            { label: 'Keyboard Shortcuts', slug: 'reference/shortcuts' },
            { label: 'FAQ', slug: 'reference/faq' },
          ],
        },
      ],
      customCss: ['./src/styles/custom.css'],
      expressiveCode: {
        themes: ['nord'],
      },
    }),
    tailwind({
      applyBaseStyles: false,
    }),
  ],
});
