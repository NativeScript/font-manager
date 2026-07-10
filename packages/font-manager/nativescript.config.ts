import { NativeScriptConfig } from '@nativescript/core';

export default {
  ios: {
    SPMPackages: [
      {
        name: 'FontManager',
        libs: ['FontManager'],
        version: '1.0.12',
        repositoryURL: 'https://github.com/NativeScript/font-manager.git',
      },
    ],
  },
  visionos: {
    discardUncaughtJsExceptions: false,
    SPMPackages: [
      {
        name: 'FontManager',
        libs: ['FontManager'],
        version: '1.0.12',
        repositoryURL: 'https://github.com/NativeScript/font-manager.git',
      },
    ],
  },
} as NativeScriptConfig;
