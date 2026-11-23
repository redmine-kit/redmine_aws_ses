import type { SesProjectJson, SesReceivingJson, SesSendingJson } from './api';

// an issue a received email made (its reference, as the server writes it: 「#」 and the id)
export const ISSUE = 12345;

// The stories' and tests' data: the plugin's JSON as its controllers answer it (the server's strings in Japanese).

export const sending: SesSendingJson = {
  updated: '2026/11/24 09:30',
  domain: 'example.com',
  account: {
    rows: [
      { name: 'アカウントステータス', value: '正常' },
      { name: '送信', value: '有効' },
      { name: '本稼働アクセス', value: 'はい' },
      { name: '日次送信クォータ', value: '50,000' },
      { name: '直近 24 時間の送信数', value: '1,234' },
      { name: '最大送信レート', value: '14 通/秒' },
    ],
  },
  identity: { rows: [{ name: 'ドメイン', value: 'example.com' }, { name: '検証済み', value: 'はい' }, { name: 'DKIM', value: '成功' }] },
  suppressed: { rows: [{ address: 'bounce@example.net', user: '鈴木 一郎', reason: 'バウンス', last_update: '2026/11/20 10:15' }] },
  failed_jobs: true,
};

// before the first refresh, the sender address not of a domain
export const sendingEmpty: SesSendingJson = { updated: null, domain: null, account: { rows: null }, identity: { rows: null }, suppressed: { rows: [] }, failed_jobs: false };

// SES refused the reads
const error = 'SES の API を呼べませんでした (Aws::SESV2::Errors::AccessDeniedException)。詳しくはログを参照してください。';
export const sendingErrors: SesSendingJson = { ...sending, account: { error }, identity: { error }, suppressed: { error } };

export const receiving: SesReceivingJson = {
  updated: '2026/11/24 09:30',
  domain: 'example.com',
  addresses: [
    { name: 'ドメイン', value: 'example.com' },
    { name: 'デフォルトアドレス', value: 'noreply@example.com' },
    { name: 'MX', value: 'inbound-smtp.ap-northeast-1.amazonaws.com' },
  ],
  warnings: ['ロールアドレスをプロジェクトのアドレスとして使用しています: support@example.com。届くメールをチケットにしてよいか確認してください。'],
  projects: [
    { project: { identifier: 'support', name: 'サポート' }, address: 'support@example.com', receive: true },
    { project: { identifier: 'portal', name: 'ポータル' }, address: 'portal@example.com', receive: false },
  ],
  bucket: true,
  received: [
    { id: 7, status: 'imported', received_at: '2026/11/24 08:58', from: 'alice@example.net', subject: 'ログインできません', project: { identifier: 'support', name: 'サポート' }, verdicts: '合格', result: `#${ISSUE}`, issue_id: ISSUE },
    { id: 6, status: 'dropped', received_at: '2026/11/23 18:40', from: 'spam@example.org', subject: 'Win a prize', project: null, verdicts: 'スパム', result: 'スパム', issue_id: null },
  ],
  settings: { global_local_part: 'noreply', global_mail: 'drop', default_project: '', import_without_dmarc_pass: '0', import_spam: '0', per_project_addresses: '1', project_senders: '0' },
  global_mail: [
    { value: 'drop', label: '取得しない' },
    { value: 'default_project', label: 'デフォルトのプロジェクトで取得' },
  ],
  default_projects: [
    { value: 'support', label: 'サポート' },
    { value: 'portal', label: 'ポータル' },
  ],
};

export const receivingEmpty: SesReceivingJson = { ...receiving, domain: null, addresses: null, warnings: [], projects: null, bucket: false, received: [] };

export const project: SesProjectJson = {
  address: 'support@example.com',
  values: { receive: 'true', tracker_id: '1', category_id: '', priority_id: '', assigned_to_id: '', is_private: 'false', unknown_user: 'ignore', forwarders: '', import_forwarded: 'false', forwarded_author: 'external' },
  editable: ['receive', 'tracker_id', 'category_id', 'priority_id', 'assigned_to_id', 'is_private', 'unknown_user'],
  trackers: [{ value: '1', label: 'バグ' }, { value: '2', label: '機能' }],
  categories: [],
  priorities: [{ value: '2', label: '通常' }],
  assignees: [{ value: '3', label: '鈴木 一郎' }],
  unknown_user: [{ value: 'ignore', label: '取得しない' }, { value: 'accept', label: '匿名ユーザーとして取得' }],
  forwarded_author: [{ value: 'external', label: 'プロジェクト外の送信者' }, { value: 'registered', label: '登録済みのユーザー' }, { value: 'forwarder', label: '元の差出人にしない' }],
};

// a system administrator: the forwarded email's values too
export const projectAdmin: SesProjectJson = { ...project, editable: [...project.editable, 'forwarders', 'import_forwarded', 'forwarded_author'] };
