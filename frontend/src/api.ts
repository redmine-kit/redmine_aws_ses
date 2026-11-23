// The plugin's JSON (AwsSesMailSendingController, AwsSesMailReceivingController, AwsSesProjectMailSettingsController,
// and Redmine Kit UI's admin/test_email.json): the paths the tabs read and write, and the shapes of their answers.

export const sesPaths = {
  /** GET: the Email sending tab */
  sending: '/admin/aws/mail_sending.json',
  /** POST { tab }: reads the state of SES and DNS again */
  refresh: '/admin/aws/mail_sending/refresh.json',
  /** POST { address }: removes an address from the suppression list */
  unsuppress: '/admin/aws/mail_sending/unsuppress.json',
  /** GET (?dropped=1: dropped email only): the Email receiving tab; POST { settings }: saves its settings */
  receiving: '/admin/aws/mail_receiving.json',
  /** POST { ids }: imports the email again */
  reimport: '/admin/aws/mail_receiving/reimport.json',
  /** POST: Redmine's test email to the administrator (Administration › Settings › Email notifications) */
  testEmail: '/admin/test_email.json',
  /** the failed mail jobs of Redmine Kit AWS SQS */
  failedJobs: '/admin/aws/jobs?mail=1',
  /** GET / PATCH: the Email tab of a project's settings */
  project: (identifier: string) => `/projects/${encodeURIComponent(identifier)}/aws_ses_mail_setting.json`,
};

/** A row of values (aws_admin/values' rows), formatted by the server. */
export interface SesRow {
  name: string;
  value: string;
}

/** A section of the stored state: its rows (null before the first refresh), or the error of reading it. */
export type SesSection<T> = { rows: T | null; error?: undefined } | { error: string; rows?: undefined };

export interface SesSuppressed {
  address: string;
  user: string | null;
  reason: string;
  last_update: string;
}

/** GET /admin/aws/mail_sending.json (AwsSesMailHelper#aws_ses_mail_sending_json) */
export interface SesSendingJson {
  updated: string | null;
  domain: string | null;
  account: SesSection<SesRow[]>;
  identity: SesSection<SesRow[]>;
  suppressed: SesSection<SesSuppressed[]>;
  /** Redmine Kit AWS SQS's jobs page is there: the link to the failed email */
  failed_jobs: boolean;
}

export interface SesProjectRef {
  identifier: string;
  name: string;
}

export interface SesReceived {
  id: number;
  status: string;
  received_at: string;
  from: string;
  subject: string;
  project: SesProjectRef | null;
  verdicts: string;
  /** the issue (#12), Imported, or why it was dropped */
  result: string;
  issue_id: number | null;
}

export interface SesSettings {
  global_local_part: string;
  global_mail: string;
  default_project: string;
  import_without_dmarc_pass: string;
  import_spam: string;
  per_project_addresses: string;
  project_senders: string;
}

export interface SesChoice {
  value: string;
  label: string;
}

/** GET /admin/aws/mail_receiving.json (AwsSesMailHelper#aws_ses_mail_receiving_json) */
export interface SesReceivingJson {
  updated: string | null;
  domain: string | null;
  addresses: SesRow[] | null;
  warnings: string[];
  projects: { project: SesProjectRef; address: string; receive: boolean }[] | null;
  /** REDMINE_SES_MAIL_BUCKET is set */
  bucket: boolean;
  received: SesReceived[];
  settings: SesSettings;
  global_mail: SesChoice[];
  default_projects: SesChoice[];
}

/** GET /projects/:id/aws_ses_mail_setting.json (AwsSesMailHelper#aws_ses_project_mail_json) */
export interface SesProjectJson {
  address: string | null;
  values: Record<string, string>;
  /** the values the user may change (the safe attributes) */
  editable: string[];
  trackers: SesChoice[];
  categories: SesChoice[];
  priorities: SesChoice[];
  assignees: SesChoice[];
  unknown_user: SesChoice[];
  forwarded_author: SesChoice[];
}

/** The answer of an action: its notice, and errors. */
export interface SesActionJson {
  notice: string | null;
  errors?: string[];
}
