import { DemoSharedBase } from '../utils';
import { FontFace, FontFaceSet, FontDisplay } from '@nativescript/font-manager';

interface TestResult {
  name: string;
  passed: boolean;
  error?: string;
}

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

async function run(name: string, fn: () => void | Promise<void>): Promise<TestResult> {
  try {
    await fn();
    return { name, passed: true };
  } catch (e) {
    return { name, passed: false, error: e?.message ?? String(e) };
  }
}

export class DemoSharedFontManager extends DemoSharedBase {
  results: TestResult[] = [];

  async testIt() {
    const results: TestResult[] = [];

    results.push(
      await run('FontFace: creates with correct family', () => {
        const face = new FontFace('sans-serif');
        assert(face.family === 'sans-serif', `expected 'sans-serif', got '${face.family}'`);
      }),
    );

    results.push(
      await run('FontFace: initial status is unloaded', () => {
        const face = new FontFace('serif');
        assert(face.status === 'unloaded', `expected 'unloaded', got '${face.status}'`);
      }),
    );

    results.push(
      await run('FontFace: load resolves and status becomes loaded', async () => {
        const face = new FontFace('sans-serif');
        await face.load();
        assert(face.status === 'loaded', `expected 'loaded', got '${face.status}'`);
      }),
    );

    results.push(
      await run('FontFace: load is idempotent', async () => {
        const face = new FontFace('monospace');
        await face.load();
        await face.load();
        assert(face.status === 'loaded', `expected 'loaded', got '${face.status}'`);
      }),
    );

    results.push(
      await run('FontFace: descriptor defaults', () => {
        const face = new FontFace('serif');
        assert(face.display === 'auto', `display: expected 'auto', got '${face.display}'`);
        assert(face.weight === 'normal', `weight: expected 'normal', got '${face.weight}'`);
        assert(face.style === 'normal', `style: expected 'normal', got '${face.style}'`);
        assert(face.stretch === 'normal', `stretch: expected 'normal', got '${face.stretch}'`);
      }),
    );

    results.push(
      await run('FontFace: descriptor setters round-trip', () => {
        const face = new FontFace('serif');
        face.display = 'swap';
        face.weight = '700';
        face.style = 'italic';
        assert(face.display === 'swap', `display: got '${face.display}'`);
        assert(face.weight === 'bold', `weight: got '${face.weight}'`);
        assert(face.style === 'italic', `style: got '${face.style}'`);
      }),
    );

    results.push(
      await run('FontFace: constructor descriptors applied', () => {
        const face = new FontFace('serif', undefined, { weight: '700', style: 'italic', display: 'swap' });
        assert(face.weight === 'bold', `weight: got '${face.weight}'`);
        assert(face.style === 'italic', `style: got '${face.style}'`);
        assert(face.display === 'swap', `display: got '${face.display}'`);
      }),
    );

    results.push(
      await run('FontFace: updateDescriptor parses weight and style', () => {
        const face = new FontFace('Roboto');
        face.updateDescriptor('@font-face { font-weight: 300; font-style: italic; }');
        assert(face.style === 'italic', `style: got '${face.style}'`);
      }),
    );

    results.push(
      await run('FontFaceSet: add increases size', () => {
        const set = new (FontFaceSet as any)();
        const face = new FontFace('serif');
        const before = set.size;
        set.add(face);
        assert(set.size === before + 1, `expected ${before + 1}, got ${set.size}`);
        set.delete(face);
      }),
    );

    results.push(
      await run('FontFaceSet: delete decreases size', () => {
        const set = new (FontFaceSet as any)();
        const face = new FontFace('serif');
        set.add(face);
        const before = set.size;
        set.delete(face);
        assert(set.size === before - 1, `expected ${before - 1}, got ${set.size}`);
      }),
    );

    results.push(
      await run('FontFaceSet: check returns true for added family', () => {
        const set = new (FontFaceSet as any)();
        const face = new FontFace('serif');
        set.add(face);
        assert(set.check('16px serif'), 'check should return true');
        set.delete(face);
      }),
    );

    results.push(
      await run('FontFaceSet: check returns false for unknown family', () => {
        const set = new (FontFaceSet as any)();
        assert(!set.check('16px "NonExistentFont12345"'), 'check should return false');
      }),
    );

    results.push(
      await run('FontFaceSet: load resolves matching faces', async () => {
        const set = new (FontFaceSet as any)();
        const face = new FontFace('monospace');
        set.add(face);
        const loaded = await set.load('16px monospace');
        assert(loaded.length > 0, 'expected at least one loaded face');
        set.delete(face);
      }),
    );

    results.push(
      await run('FontFaceSet: clear empties the set', () => {
        const set = new (FontFaceSet as any)();
        set.add(new FontFace('serif'));
        set.add(new FontFace('monospace'));
        set.clear();
        assert(set.size === 0, `expected 0, got ${set.size}`);
      }),
    );

    results.push(
      await run('FontFaceSet: forEach iterates all faces', () => {
        const set = new (FontFaceSet as any)();
        set.add(new FontFace('serif'));
        set.add(new FontFace('monospace'));
        let count = 0;
        set.forEach(() => count++);
        assert(count === 2, `expected 2 iterations, got ${count}`);
        set.clear();
      }),
    );

    results.push(
      await run('FontFaceSet: instance is a singleton', () => {
        assert(FontFaceSet.instance === FontFaceSet.instance, 'instance should be the same reference');
      }),
    );

    results.push(
      await run('FontFaceSet: ready resolves when idle', async () => {
        let resolved = false;
        await new Promise<void>((resolve) => {
          FontFaceSet.instance.ready.then(() => {
            resolved = true;
            resolve();
          });
        });
        assert(resolved, 'ready should have resolved');
      }),
    );

    const passed = results.filter((r) => r.passed).length;
    const failed = results.filter((r) => !r.passed).length;

    results.forEach((r) => {
      const icon = r.passed ? '✓' : '✗';
      const msg = r.passed ? r.name : `${r.name} — ${r.error}`;
      console.log(`[font-manager] ${icon} ${msg}`);
    });

    console.log(`\n[font-manager] ${passed}/${results.length} passed${failed > 0 ? `, ${failed} failed` : ''}`);

    this.results = results;
    this.notifyPropertyChange('results', results);
  }
}
