// Snowpack Configuration File
// See all supported options: https://www.snowpack.dev/#configuration

/** @type {import("snowpack").SnowpackUserConfig } */
module.exports = {
    mount: {
      "scripts": { url: '/' },
      "styles": { url: '/' }
    },
    plugins: [
      [
        '@snowpack/plugin-sass', { 
          style: "compressed",
          sourceMap: true, 
        }
      ]
    ],
    // installOptions: {},
    devOptions: {
      "port": 3000,
      "open": "none",
      "bundle": false,
    },
    buildOptions: {
      "clean": true,
      "out": "../wwwroot/client",
      "metaUrlPath": "/vendor"
    },
    optimize: {
      entrypoints: [
          "scripts/main.ts"
      ],
      bundle: true,
      minify: true,
      target: 'es2018',
    },
    exclude: [
      "**/node_modules/**/*",
      "../wwwroot/**/*"
    ]
  };
