/** @type {import('tailwindcss').Config} */
export default {
  content: ['./src/**/*.{astro,html,js,jsx,md,mdx,svelte,ts,tsx,vue}'],
  theme: {
    extend: {
      colors: {
        nord: {
          bg: '#2E3440',
          fg: '#ECEFF4',
          panel: '#3B4252',
          accent: '#88C0D0',
          frost1: '#8FBCBB',
          frost2: '#88C0D0',
          frost3: '#81A1C1',
          frost4: '#5E81AC',
          aurora1: '#BF616A',
          aurora2: '#D08770',
          aurora3: '#EBCB8B',
          aurora4: '#A3BE8C',
          aurora5: '#B48EAD',
          snow1: '#D8DEE9',
          snow2: '#E5E9F0',
          snow3: '#ECEFF4',
        },
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', '-apple-system', 'sans-serif'],
        mono: ['JetBrains Mono', 'Fira Code', 'monospace'],
      },
      animation: {
        'fade-in': 'fadeIn 0.8s ease-out forwards',
        'slide-up': 'slideUp 0.6s ease-out forwards',
        'float': 'float 6s ease-in-out infinite',
        'glow': 'glow 2s ease-in-out infinite alternate',
      },
      keyframes: {
        fadeIn: {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        slideUp: {
          '0%': { opacity: '0', transform: 'translateY(30px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
        float: {
          '0%, 100%': { transform: 'translateY(0)' },
          '50%': { transform: 'translateY(-10px)' },
        },
        glow: {
          '0%': { boxShadow: '0 0 20px rgba(136, 192, 208, 0.3)' },
          '100%': { boxShadow: '0 0 40px rgba(136, 192, 208, 0.6)' },
        },
      },
    },
  },
  plugins: [],
};
