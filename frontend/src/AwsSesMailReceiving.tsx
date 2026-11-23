import { useState } from 'react';
import {
  AttrGridSkeleton,
  Button,
  CardBody,
  CardSection,
  Checkbox,
  DataTable,
  DataTableSkeleton,
  EmptyState,
  FormActions,
  FormRow,
  Icon,
  Input,
  Notice,
  RequestErrorState,
  SegmentedControl,
  Select,
  SkeletonRegion,
  confirmAction,
  useFormDirty,
  type DataTableColumn,
  type DataTableRowBase,
} from '@redmine-kit/ui';
import { AppLink, useApiErrorTexts, useKitMutation, useKitQuery, useT } from '@redmine-kit/plugin';
import { sesPaths, type SesActionJson, type SesReceived, type SesReceivingJson, type SesSettings } from './api';
import { ActionResult, LABEL_WIDTH, RefreshAction, ValueRows } from './parts';

// Administration › AWS › メール受信 (/admin/aws/mail_receiving: the manifest's layout: admin screen with menu_item aws, its
// tab label_aws_ses_mail_receiving at position 40), as Redmine's page shows it (app/views/aws_ses_mail_receiving/index.html.erb):
// - the card's header: when the state was read and 最新の情報に更新 (POST refresh, for both email tabs);
// - メールアドレス: the domain, the default address and the MX record, the page's warnings, and the projects' addresses
//   when addresses per project are on (the warning when the sender address isn't of a domain instead);
// - the warning when REDMINE_SES_MAIL_BUCKET isn't set;
// - 受信履歴: すべて / 未取得 (the page's ?dropped=1), the last 100 email, checked ones imported again (再取得, after
//   「よろしいですか？」);
// - 受信設定: the receiving settings, saved with 保存 (POST { settings }, the page's form; Redmine's errors above it).
// Every value comes formatted by the server (Redmine's helpers); the actions are the page's, behind require_admin.

interface MailRow extends DataTableRowBase {
  mail: SesReceived;
}

interface ProjectRow extends DataTableRowBase {
  project: { identifier: string; name: string };
  address: string;
  receive: boolean;
}

function useMailColumns(): DataTableColumn<MailRow>[] {
  const t = useT();
  return [
    { key: 'check', type: 'check' },
    { key: 'received', label: t('label_aws_ses_mail_received_at'), type: 'text', value: (r) => r.mail.received_at },
    { key: 'from', label: t('label_aws_ses_mail_from'), type: 'text', value: (r) => r.mail.from },
    { key: 'subject', label: t('field_subject'), type: 'text', value: (r) => r.mail.subject },
    {
      key: 'project',
      label: t('label_project'),
      type: 'text',
      value: (r) => r.mail.project?.name ?? '',
      cell: (r) => (r.mail.project ? <AppLink href={`/projects/${encodeURIComponent(r.mail.project.identifier)}`}>{r.mail.project.name}</AppLink> : null),
    },
    { key: 'verdicts', label: t('label_aws_ses_mail_verdicts'), type: 'text', value: (r) => r.mail.verdicts },
    {
      key: 'result',
      label: t('label_aws_ses_mail_result'),
      type: 'text',
      value: (r) => r.mail.result,
      cell: (r) => (r.mail.issue_id ? <AppLink href={`/issues/${r.mail.issue_id}`}>{r.mail.result}</AppLink> : r.mail.result),
    },
  ];
}

export function AwsSesMailReceiving() {
  const t = useT();
  const [dropped, setDropped] = useState(false);
  const query = useKitQuery<SesReceivingJson>(sesPaths.receiving, dropped ? { dropped: '1' } : undefined);
  const action = useKitMutation<SesActionJson>();
  const errorTexts = useApiErrorTexts();
  const [result, setResult] = useState<SesActionJson | null>(null);
  const [selected, setSelected] = useState<string[]>([]);
  const columns = useMailColumns();
  const run = (path: string, body: unknown = {}) => {
    setResult(null);
    action.mutate(
      { method: 'post', path, body },
      {
        onSuccess: (data) => {
          setResult(data ?? null);
          setSelected([]);
        },
      },
    );
  };
  if (query.isError)
    return (
      <CardBody>
        <RequestErrorState error={query.error} onRetry={() => void query.refetch()} retrying={query.isFetching} />
      </CardBody>
    );
  const data = query.data;
  const projectColumns: DataTableColumn<ProjectRow>[] = [
    { key: 'project', label: t('label_project'), type: 'text', value: (r) => r.project.name, cell: (r) => <AppLink href={`/projects/${encodeURIComponent(r.project.identifier)}`}>{r.project.name}</AppLink> },
    { key: 'mail', label: t('field_mail'), type: 'text', value: (r) => r.address },
    {
      key: 'receive',
      label: t('label_aws_ses_mail_receive'),
      type: 'text',
      align: 'center',
      value: (r) => (r.receive ? t('general_text_Yes') : t('general_text_No')),
      cell: (r) =>
        r.receive ? (
          <span className="flex justify-center text-accent" role="img" aria-label={t('general_text_Yes')}>
            <Icon name="check" size={16} />
          </span>
        ) : null,
    },
  ];
  return (
    <>
      <RefreshAction updated={data?.updated ?? null} busy={!data || action.isPending} onRefresh={() => run(sesPaths.refresh, { tab: 'mail_receiving' })} />
      <CardBody>
        <ActionResult result={result} errors={errorTexts(action.error)} />
        <CardSection line={false} heading={t('label_aws_ses_mail_addresses')}>
          {!data ? (
            <SkeletonRegion label={t('label_loading')} className="px-gutter">
              <AttrGridSkeleton columns={1} labelWidth={LABEL_WIDTH} items={[{ label: t('label_aws_ses_mail_domain') }, { label: t('label_aws_ses_mail_global_address') }, { label: 'MX' }]} />
            </SkeletonRegion>
          ) : data.domain === null ? (
            <Notice tone="warning" text={t('text_aws_ses_mail_no_domain')} wrap />
          ) : (
            <div className="flex flex-col gap-3">
              {data.addresses && <ValueRows rows={data.addresses} />}
              {data.warnings.map((warning) => (
                <Notice key={warning} tone="warning" text={warning} wrap />
              ))}
              {data.projects && (
                <DataTable<ProjectRow>
                  label={t('label_aws_ses_mail_addresses')}
                  columns={projectColumns}
                  rows={data.projects.map((row) => ({ id: row.project.identifier, ...row }))}
                />
              )}
            </div>
          )}
        </CardSection>
        {data && !data.bucket && <Notice tone="warning" text={t('text_aws_ses_mail_no_bucket')} wrap />}
        <CardSection
          heading={t('label_aws_ses_mail_received')}
          controls={
            <SegmentedControl
              size={28}
              aria-label={t('label_aws_ses_mail_received')}
              value={dropped ? 'dropped' : 'all'}
              onValueChange={(value) => {
                setDropped(value === 'dropped');
                setSelected([]);
              }}
              items={[
                { value: 'all', label: t('label_all') },
                { value: 'dropped', label: t('label_aws_ses_mail_dropped_only') },
              ]}
            />
          }
        >
          {selected.length > 0 && (
            <Notice
              tone="neutral"
              icon="none"
              text={
                <span className="flex min-w-0 flex-wrap items-center gap-2">
                  <span className="flex-none">{t('kit.common.selected_items', { count: selected.length })}</span>
                  <Button
                    size={28}
                    disabled={action.isPending}
                    onClick={() =>
                      confirmAction({
                        title: t('button_aws_ses_mail_reimport'),
                        description: t('text_are_you_sure'),
                        action: t('button_aws_ses_mail_reimport'),
                        onConfirm: () => run(sesPaths.reimport, { ids: selected.map(Number) }),
                      })
                    }
                  >
                    {t('button_aws_ses_mail_reimport')}
                  </Button>
                </span>
              }
            />
          )}
          {!data ? (
            <DataTableSkeleton<MailRow> label={t('label_aws_ses_mail_received')} loading={t('label_loading')} columns={columns} rows={3} />
          ) : data.received.length === 0 ? (
            <EmptyState />
          ) : (
            <DataTable<MailRow>
              label={t('label_aws_ses_mail_received')}
              columns={columns}
              rows={data.received.map((mail) => ({ id: String(mail.id), mail }))}
              selected={selected}
              onSelectionChange={setSelected}
            />
          )}
        </CardSection>
        <CardSection heading={t('label_aws_ses_mail_settings')}>{data && <SettingsForm key={JSON.stringify(data.settings)} data={data} />}</CardSection>
      </CardBody>
    </>
  );
}

/** 受信設定: the receiving settings as the page's form has them; 保存 posts them (POST { settings }), Redmine's errors above. */
function SettingsForm({ data }: { data: SesReceivingJson }) {
  const t = useT();
  const save = useKitMutation<SesActionJson>(sesPaths.receiving, 'post');
  const errorTexts = useApiErrorTexts();
  const [values, setValues] = useState<SesSettings>(data.settings);
  const form = useFormDirty(values);
  const set = (name: keyof SesSettings, value: string) => setValues({ ...values, [name]: value });
  const check = (name: keyof SesSettings, label: string) => (
    <Checkbox key={name} checked={values[name] === '1'} onCheckedChange={(v) => set(name, v === true ? '1' : '0')} label={label} />
  );
  const errors = errorTexts(save.error);
  return (
    <>
      {save.isSuccess && !form.dirty && <Notice tone="neutral" role="status" text={t('notice_successful_update')} />}
      {errors.length > 0 && <Notice tone="danger" role="alert" text={errors.join('\n')} wrap />}
      <div className="box-content flex max-w-215 flex-col gap-4 px-6">
        <FormRow label={t('label_aws_ses_mail_global_address')}>
          <span className="flex items-center gap-1">
            <Input value={values.global_local_part} onChange={(e) => set('global_local_part', e.target.value)} className="w-40" aria-label={t('label_aws_ses_mail_global_address')} />
            {data.domain && <span>@{data.domain}</span>}
          </span>
        </FormRow>
        <FormRow label={t('label_incoming_emails')}>
          <Select options={data.global_mail} value={values.global_mail} onChange={(e) => set('global_mail', e.target.value)} className="w-60" />
        </FormRow>
        <FormRow label={t('label_aws_ses_mail_default_project')}>
          <Select
            options={[{ value: '', label: '' }, ...data.default_projects]}
            value={values.default_project}
            onChange={(e) => set('default_project', e.target.value)}
            className="w-60"
          />
        </FormRow>
        <FormRow label={t('label_aws_ses_mail_import')} group>
          <div className="flex flex-col gap-2">
            {check('import_without_dmarc_pass', t('label_aws_ses_mail_import_without_dmarc_pass'))}
            {check('import_spam', t('label_aws_ses_mail_import_spam'))}
          </div>
        </FormRow>
        <FormRow label={t('label_project_plural')} group>
          <div className="flex flex-col gap-2">
            {check('per_project_addresses', t('label_aws_ses_mail_per_project'))}
            {check('project_senders', t('label_aws_ses_mail_project_senders'))}
          </div>
        </FormRow>
      </div>
      <FormActions>
        <Button data-form-cancel variant="ghost" disabled={!form.dirty || save.isPending} onClick={() => setValues(form.saved)}>
          {t('button_cancel')}
        </Button>
        <Button
          submit="primary"
          variant="primary"
          disabled={!form.dirty || save.isPending}
          onClick={() => save.mutate({ settings: values }, { onSuccess: () => form.markSaved() })}
        >
          {t('button_save')}
        </Button>
      </FormActions>
    </>
  );
}
