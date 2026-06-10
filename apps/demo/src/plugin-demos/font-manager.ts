import { Observable, EventData, Page } from '@nativescript/core';
import { DemoSharedFontManager } from '@demo/shared';
import {} from '@nativescript/font-manager';

export function navigatingTo(args: EventData) {
  const page = <Page>args.object;
  page.bindingContext = new DemoModel();
}

export class DemoModel extends DemoSharedFontManager {}
