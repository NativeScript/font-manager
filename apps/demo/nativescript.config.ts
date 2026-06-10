import { NativeScriptConfig } from '@nativescript/core';

export default {
  id: 'org.nativescript.plugindemo',
  appResourcesPath: '../../tools/assets/App_Resources',
  android: {
    v8Flags: '--expose_gc',
    markingMode: 'none',
  },
  appPath: 'src',
  cli: {
    packageManager: 'npm',
  },
  ios: {
    SPMPackages: [
      {
        name: 'FontManager',
        libs: ['FontManager'],
        path: '../../packages/font-manager/src-native/ios/FontManager',
      },
    ],
  },
} as NativeScriptConfig;
