import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { KitTestRequest } from '@redmine-kit/plugin/testing';
import { ApiError } from '@redmine-kit/plugin';
import { CardHeaderActionsContext } from '@redmine-kit/plugin/host';
import { describe, expect, it } from 'vitest';
import { AwsSesMailReceiving } from './AwsSesMailReceiving';
import { AwsSesMailSending } from './AwsSesMailSending';
import { AwsSesProjectMail } from './AwsSesProjectMail';
import { ISSUE, project, projectAdmin, receiving, receivingEmpty, sending, sendingEmpty, sendingErrors } from './fixtures';
import { renderKit } from './test/render';

// The email tabs on the plugin's JSON as its controllers answer it.
const SENDING = 'GET /admin/aws/mail_sending.json';
const RECEIVING = 'GET /admin/aws/mail_receiving.json';
const PROJECT = 'GET /projects/support/aws_ses_mail_setting.json';
const confirm = async (user: ReturnType<typeof userEvent.setup>, name: string) =>
  user.click(within(await screen.findByRole('dialog')).getByRole('button', { name }));

describe('AwsSesMailSending', () => {
  it('shows the account, the domain and the suppression list as the page does', async () => {
    renderKit(<AwsSesMailSending />, { responses: { [SENDING]: sending } });
    expect(await screen.findByText('50,000')).toBeInTheDocument();
    expect(screen.getByText('14 通/秒')).toBeInTheDocument();
    expect(within(screen.getByRole('table', { name: 'サプレッションリスト' })).getByText('bounce@example.net')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: '失敗したジョブ' })).toHaveAttribute('href', '/admin/aws/jobs?mail=1');
  });

  it('no domain: the warning; no state yet: 表示するデータがありません; no SQS: no link', async () => {
    renderKit(<AwsSesMailSending />, { responses: { [SENDING]: sendingEmpty } });
    expect(await screen.findByText(/SES で検証したドメインのアドレスにしてください/)).toBeInTheDocument();
    expect(screen.getAllByText('表示するデータがありません')).toHaveLength(2);
    expect(screen.queryByRole('link', { name: '失敗したジョブ' })).toBeNull();
  });

  it("each section's error of reading it in its place", async () => {
    renderKit(<AwsSesMailSending />, { responses: { [SENDING]: sendingErrors } });
    expect(await screen.findAllByText(/AccessDeniedException/)).toHaveLength(3);
  });

  it('removes an address after the confirmation, and sends the test email', async () => {
    const user = userEvent.setup();
    const requests: KitTestRequest[] = [];
    renderKit(<AwsSesMailSending />, {
      requests,
      responses: {
        [SENDING]: sending,
        'POST /admin/aws/mail_sending/unsuppress.json': { notice: 'bounce@example.net をサプレッションリストから削除しました。', errors: [] },
        'POST /admin/test_email.json': new ApiError(422, ['メールを送信中にエラーが発生しました (x)']),
      },
    });
    await screen.findByText('bounce@example.net');
    await user.click(screen.getByRole('button', { name: '削除' }));
    await confirm(user, '削除');
    expect(await screen.findByText('bounce@example.net をサプレッションリストから削除しました。')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'テストメールを送信' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('メールを送信中にエラーが発生しました (x)');
    expect(requests.filter((r) => r.method === 'post').map((r) => [r.path, r.body])).toEqual([
      ['/admin/aws/mail_sending/unsuppress.json', { address: 'bounce@example.net' }],
      ['/admin/test_email.json', {}],
    ]);
  });
});

describe('the refresh of both tabs', () => {
  it("is in the card's header with when the state was read, and names the tab", async () => {
    const user = userEvent.setup();
    const requests: KitTestRequest[] = [];
    const header = document.body.appendChild(document.createElement('div'));
    renderKit(
      <CardHeaderActionsContext value={header}>
        <AwsSesMailReceiving />
      </CardHeaderActionsContext>,
      { requests, responses: { [RECEIVING]: receiving, 'POST /admin/aws/mail_sending/refresh.json': { notice: null, errors: [] } } },
    );
    expect(await within(header).findByText('更新: 2026/11/24 09:30')).toBeInTheDocument();
    await user.click(within(header).getByRole('button', { name: '最新の情報に更新' }));
    expect(requests.find((r) => r.method === 'post')).toEqual({ method: 'post', path: '/admin/aws/mail_sending/refresh.json', body: { tab: 'mail_receiving' } });
    header.remove();
  });
});

describe('AwsSesMailReceiving', () => {
  it('shows the addresses, the warnings, the projects and the received email', async () => {
    renderKit(<AwsSesMailReceiving />, { responses: { [RECEIVING]: receiving } });
    expect(await screen.findByText('noreply@example.com')).toBeInTheDocument();
    expect(screen.getByText(/ロールアドレスをプロジェクトのアドレスとして使用しています/)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: `#${ISSUE}` })).toHaveAttribute('href', `/issues/${ISSUE}`);
    expect(screen.getByRole('img', { name: 'はい' })).toBeInTheDocument();
  });

  it('no domain and no bucket: the warnings; no email: 表示するデータがありません', async () => {
    renderKit(<AwsSesMailReceiving />, { responses: { [RECEIVING]: receivingEmpty } });
    expect(await screen.findByText(/REDMINE_SES_MAIL_BUCKET が未設定/)).toBeInTheDocument();
    expect(screen.getByText(/SES で検証したドメインのアドレスにしてください/)).toBeInTheDocument();
    expect(screen.getByText('表示するデータがありません')).toBeInTheDocument();
  });

  it('re-imports the checked email, asks for the dropped ones, saves the settings and shows the errors', async () => {
    const user = userEvent.setup();
    const requests: KitTestRequest[] = [];
    renderKit(<AwsSesMailReceiving />, {
      requests,
      responses: {
        [RECEIVING]: receiving,
        'POST /admin/aws/mail_receiving/reimport.json': { notice: '1 通を再取得します。', errors: [] },
        'POST /admin/aws/mail_receiving.json': new ApiError(422, ['アドレスには英小文字、数字、「.」「_」「-」のみ使用できます。']),
      },
    });
    await screen.findByText('ログインできません');
    await user.click(within(screen.getByRole('table', { name: '受信履歴' })).getAllByRole('checkbox')[1]);
    await user.click(screen.getByRole('button', { name: '再取得' }));
    await confirm(user, '再取得');
    expect(await screen.findByText('1 通を再取得します。')).toBeInTheDocument();
    await user.click(screen.getByRole('radio', { name: '未取得' }));
    expect(requests.some((r) => r.path === '/admin/aws/mail_receiving.json' && r.query?.dropped === '1')).toBe(true);
    const address = await screen.findByRole('textbox', { name: 'デフォルトアドレス' });
    await user.clear(address);
    await user.type(address, 'Bad Name');
    await user.click(screen.getByRole('button', { name: /^保存/ }));
    expect(await screen.findByRole('alert')).toHaveTextContent('アドレスには英小文字');
    const posts = requests.filter((r) => r.method === 'post');
    expect(posts[0]).toEqual({ method: 'post', path: '/admin/aws/mail_receiving/reimport.json', body: { ids: [7] } });
    expect(posts[1].body).toEqual({ settings: { ...receiving.settings, global_local_part: 'Bad Name' } });
  });
});

describe('AwsSesProjectMail', () => {
  const context = { project: { identifier: 'support', name: 'サポート' } };

  it("a manager changes the issues' values; the forwarded email's are disabled; 保存 sends what may be changed", async () => {
    const user = userEvent.setup();
    const requests: KitTestRequest[] = [];
    renderKit(<AwsSesProjectMail />, { context, requests, responses: { [PROJECT]: project, 'PATCH /projects/support/aws_ses_mail_setting.json': project } });
    expect(await screen.findByText('support@example.com')).toBeInTheDocument();
    expect(screen.getByRole('textbox', { name: '転送元' })).toBeDisabled();
    await user.click(screen.getByRole('combobox', { name: 'トラッカー' }));
    await user.click(await screen.findByRole('option', { name: '機能' }));
    await user.click(screen.getByRole('button', { name: /^保存/ }));
    const patch = (await waitForPatch(requests))!;
    expect(Object.keys(patch.body as object)).toEqual(['aws_ses_project_mail_setting']);
    const sent = (patch.body as { aws_ses_project_mail_setting: Record<string, string> }).aws_ses_project_mail_setting;
    expect(sent.tracker_id).toBe('2');
    expect(sent).not.toHaveProperty('forwarders');
  });

  it("a system administrator changes the forwarded email's values; without an address, メール受信 is off", async () => {
    renderKit(<AwsSesProjectMail />, { context, responses: { [PROJECT]: { ...projectAdmin, address: null } } });
    expect(await screen.findByRole('textbox', { name: '転送元' })).toBeEnabled();
    expect(screen.getAllByRole('checkbox', { name: 'メール受信' })[0]).toBeDisabled();
  });
});

async function waitForPatch(requests: KitTestRequest[]) {
  for (let i = 0; i < 50; i++) {
    const patch = requests.find((r) => r.method === 'patch');
    if (patch) return patch;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  return undefined;
}
