module.exports = {
  plugins: {
    "@tailwindcss/postcss": {},
    "postcss-preset-env": {
      stage: 1,
      features: {
        "cascade-layers": false,
        "nesting-rules": true,
        "oklab-function": { preserve: true },
        "is-pseudo-class": false,
      },
      autoprefixer: {},
    },
  },
};
