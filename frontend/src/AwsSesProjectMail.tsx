import { useState } from 'react';
import {
  Button,
  Checkbox,
  FormActions,
  FormActionsSkeleton,
  FormRow,
  Notice,
  RequestErrorState,
  Select,
  Skeleton,
  SkeletonRegion,
  Textarea,
  useFormDirty,
} from '@redmine-kit/ui';
import { useApiErrorTexts, useExtensionContext, useKitMutation, useKitQuery, useT } from '@redmine-kit/plugin';
import { sesPaths, type SesChoice, type SesProjectJson } from './api';

// A project's settings › メール (the manifest's settings.project tab aws_ses_mail, with Redmine's permission
// manage_aws_ses_mail_settings), the form Redmine's tab has (app/views/aws_ses_project_mail_settings/_form.html.erb): the
// project's address, メール受信 (only with an address), the values of the issues it makes, 未登録の送信者 and, for system
// administrators only (the setting's safe attributes), 転送元, 転送メール and 転送メールの作成者, which others see disabled
// as Redmine's tab shows them. 保存 sends the values the user may change (PATCH, the tab's own action); Redmine's errors
// above the form. The choices are the server's (the values an issue of the project can take).

const FIELDS = ['receive', 'tracker_id', 'category_id', 'priority_id', 'assigned_to_id', 'is_private', 'unknown_user', 'forwarders', 'import_forwarded', 'forwarded_author'] as const;

export function AwsSesProjectMail() {
  const { project } = useExtensionContext();
  if (!project) return null;
  return <ProjectMail identifier={project.identifier} />;
}

function ProjectMail({ identifier }: { identifier: string }) {
  const query = useKitQuery<SesProjectJson>(sesPaths.project(identifier));
  if (query.isError) return <RequestErrorState error={query.error} onRetry={() => void query.refetch()} retrying={query.isFetching} />;
  if (!query.data) return <FormSkeleton />;
  return <ProjectMailForm identifier={identifier} data={query.data} />;
}

function FormSkeleton() {
  const t = useT();
  return (
    <>
      <SkeletonRegion label={t('label_loading')} className="flex flex-col gap-4 px-6 py-section">
        {Array.from({ length: 6 }, (_, i) => (
          <Skeleton key={i} width="40%" height={32} />
        ))}
      </SkeletonRegion>
      <FormActionsSkeleton />
    </>
  );
}

const truthy = (value: string | undefined) => value === 'true' || value === '1';

function ProjectMailForm({ identifier, data }: { identifier: string; data: SesProjectJson }) {
  const t = useT();
  const save = useKitMutation<SesProjectJson>(sesPaths.project(identifier), 'patch');
  const errorTexts = useApiErrorTexts();
  const [values, setValues] = useState<Record<string, string>>(data.values);
  const form = useFormDirty(values);
  const editable = (name: string) => data.editable.includes(name);
  const set = (name: string, value: string) => setValues({ ...values, [name]: value });
  const select = (name: string, label: string, options: SesChoice[], blank = true) => (
    <FormRow label={label}>
      <Select
        aria-label={label}
        options={blank ? [{ value: '', label: '' }, ...options] : options}
        value={values[name] ?? ''}
        disabled={!editable(name)}
        onChange={(e) => set(name, e.target.value)}
        className="w-60"
      />
    </FormRow>
  );
  // a check box whose row names it (as Redmine's tabular check boxes): the label only for screen readers, unless it says
  // more than the row (転送メール › メンバーが転送したメールを元のメールとして取得)
  const check = (name: string, label: string, { disabled = false, visible = false } = {}) => (
    <span className="inline-flex h-8 items-center">
      <Checkbox
        checked={truthy(values[name])}
        disabled={disabled || !editable(name)}
        onCheckedChange={(v) => set(name, v === true ? '1' : '0')}
        {...(visible ? { label } : { 'aria-label': label })}
      />
    </span>
  );
  const errors = errorTexts(save.error);
  const changed = Object.fromEntries(FIELDS.filter((name) => editable(name)).map((name) => [name, values[name] ?? '']));
  return (
    <>
      {save.isSuccess && !form.dirty && <Notice tone="neutral" role="status" text={t('notice_successful_update')} />}
      {errors.length > 0 && <Notice tone="danger" role="alert" text={errors.join('\n')} wrap />}
      <div className="box-content flex max-w-215 flex-col gap-4 px-6 py-section">
        <FormRow label={t('field_mail')} group>
          <span className="inline-flex h-8 items-center">{data.address ?? '-'}</span>
        </FormRow>
        <FormRow label={t('label_aws_ses_mail_receive')} group>
          {check('receive', t('label_aws_ses_mail_receive'), { disabled: data.address === null })}
        </FormRow>
        {select('tracker_id', t('field_tracker'), data.trackers)}
        {select('category_id', t('field_category'), data.categories)}
        {select('priority_id', t('field_priority'), data.priorities)}
        {select('assigned_to_id', t('field_assigned_to'), data.assignees)}
        <FormRow label={t('field_is_private')} group>
          {check('is_private', t('field_is_private'))}
        </FormRow>
        {select('unknown_user', t('label_aws_ses_mail_unknown_user'), data.unknown_user, false)}
        <FormRow label={t('label_aws_ses_mail_forwarders')} hint={`${t('text_aws_ses_mail_forwarders_info')} ${t('text_line_separated')}`}>
          <Textarea
            aria-label={t('label_aws_ses_mail_forwarders')}
            rows={3}
            value={values.forwarders ?? ''}
            disabled={!editable('forwarders')}
            onChange={(e) => set('forwarders', e.target.value)}
            className="w-full max-w-120"
          />
        </FormRow>
        <FormRow label={t('label_aws_ses_mail_forwarded')} group>
          {check('import_forwarded', t('label_aws_ses_mail_import_forwarded'), { visible: true })}
        </FormRow>
        {select('forwarded_author', t('label_aws_ses_mail_forwarded_author'), data.forwarded_author, false)}
      </div>
      <FormActions placement="sticky">
        <Button data-form-cancel variant="ghost" disabled={!form.dirty || save.isPending} onClick={() => setValues(form.saved)}>
          {t('button_cancel')}
        </Button>
        <Button
          submit="primary"
          variant="primary"
          keycap="⌘↵"
          disabled={!form.dirty || save.isPending}
          onClick={() => save.mutate({ aws_ses_project_mail_setting: changed }, { onSuccess: () => form.markSaved() })}
        >
          {t('button_save')}
        </Button>
      </FormActions>
    </>
  );
}
