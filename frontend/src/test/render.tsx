import type { ReactNode } from 'react';
import { render } from '@testing-library/react';
import { KitTestHost, type KitTestHostProps } from '@redmine-kit/plugin/testing';
import { ConfirmProvider } from '@redmine-kit/ui'; // check-ui-ok: a test; the app mounts the confirmations' provider (confirmAction) around a plugin's components
import { kitCatalog } from '@redmine-kit/plugin/locales';

// A component of the module in a test, with the app's part (KitTestHost): the strings as Redmine loads them (Redmine
// 7.0.3's and redmine_kit_ui's, then the plugin's config/locales), the same as its Storybook's; the permissions given.

export const JA = kitCatalog('ja');
export const EN = kitCatalog('en');

export function renderKit(ui: ReactNode, { lang = 'ja', ...props }: Omit<KitTestHostProps, 'children'> & { lang?: 'ja' | 'en' } = {}) {
  const t = lang === 'ja' ? JA : EN;
  return render(
    <KitTestHost strings={lang} t={t} {...props}>
      <ConfirmProvider />
      {ui}
    </KitTestHost>,
  );
}
