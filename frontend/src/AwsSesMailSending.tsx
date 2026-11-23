import { useState } from 'react';
import {
  AttrGridSkeleton,
  Button,
  CardBody,
  CardSection,
  DataTable,
  EmptyState,
  Notice,
  RequestErrorState,
  Skeleton,
  SkeletonRegion,
  confirmAction,
  type DataTableColumn,
  type DataTableRowBase,
} from '@redmine-kit/ui';
import { AppLink, useApiErrorTexts, useKitMutation, useKitQuery, useT } from '@redmine-kit/plugin';
import { sesPaths, type SesActionJson, type SesSendingJson, type SesSuppressed } from './api';
import { ActionResult, LABEL_WIDTH, RefreshAction, StateValues } from './parts';

// Administration › AWS › メール送信 (/admin/aws/mail_sending: the manifest's layout: admin screen with menu_item aws, its
// tab label_aws_ses_mail_sending at position 30), as Redmine's page shows it (app/views/aws_ses_mail_sending/index.html.erb),
// from the state the last refresh stored (the page never calls SES):
// - the card's header: when the state was read and 最新の情報に更新 (POST refresh, for both email tabs);
// - SES アカウント, with テストメールを送信 (Redmine's test email to the administrator) and, with Redmine Kit AWS SQS, a link
//   to its failed mail jobs; ドメイン (the warning when the sender address isn't of a domain), サプレッションリスト with
//   削除 per address (after 「よろしいですか？」); each section's error of reading it in its place.
// Every value comes formatted by the server (Redmine's helpers); the actions are the page's, behind require_admin.

interface Row extends DataTableRowBase {
  destination: SesSuppressed;
}

export function AwsSesMailSending() {
  const t = useT();
  const query = useKitQuery<SesSendingJson>(sesPaths.sending);
  const action = useKitMutation<SesActionJson>();
  const errorTexts = useApiErrorTexts();
  const [result, setResult] = useState<SesActionJson | null>(null);
  const run = (path: string, body: unknown = {}) => {
    setResult(null);
    action.mutate({ method: 'post', path, body }, { onSuccess: (data) => setResult(data ?? null) });
  };
  const columns: DataTableColumn<Row>[] = [
    { key: 'mail', label: t('field_mail'), type: 'text', value: (r) => r.destination.address },
    { key: 'user', label: t('label_user'), type: 'text', value: (r) => r.destination.user ?? '' },
    { key: 'reason', label: t('label_aws_ses_mail_reason'), type: 'text', value: (r) => r.destination.reason },
    { key: 'updated', label: t('field_updated_on'), type: 'text', align: 'right', value: (r) => r.destination.last_update },
    { key: 'actions', label: t('button_aws_ses_mail_unsuppress'), hasLabel: false, type: 'actions', value: () => [{ icon: 'delete', label: t('button_aws_ses_mail_unsuppress'), action: 'unsuppress', danger: true }] },
  ];
  if (query.isError)
    return (
      <CardBody>
        <RequestErrorState error={query.error} onRetry={() => void query.refetch()} retrying={query.isFetching} />
      </CardBody>
    );
  const data = query.data;
  return (
    <>
      <RefreshAction updated={data?.updated ?? null} busy={!data || action.isPending} onRefresh={() => run(sesPaths.refresh, { tab: 'mail_sending' })} />
      <CardBody>
        <ActionResult result={result} errors={errorTexts(action.error)} />
        <CardSection
          line={false}
          heading={t('label_aws_ses_mail_account')}
        >
          {/* the page's links under the heading (a heading with two actions would squeeze its title at a phone's width) */}
          <div className="mb-3 flex flex-wrap items-center gap-2 px-gutter">
            <Button size={28} disabled={!data || action.isPending} onClick={() => run(sesPaths.testEmail)}>
              {t('label_send_test_email')}
            </Button>
            {data?.failed_jobs && (
              <Button size={28} variant="plain" asChild>
                <AppLink href={sesPaths.failedJobs}>{t('label_aws_ses_mail_failed')}</AppLink>
              </Button>
            )}
          </div>
          {data ? (
            <StateValues section={data.account} />
          ) : (
            <RowsSkeleton labels={['enforcement_status', 'sending_enabled', 'production_access', 'quota', 'sent_last_24_hours', 'rate'].map((k) => t(`label_aws_ses_mail_${k}`))} />
          )}
        </CardSection>
        <CardSection heading={t('label_aws_ses_mail_domain')}>
          {!data ? (
            <RowsSkeleton labels={[t('label_aws_ses_mail_domain'), t('label_aws_ses_mail_verified'), 'DKIM']} />
          ) : data.domain === null ? (
            <Notice tone="warning" text={t('text_aws_ses_mail_no_domain')} wrap />
          ) : (
            <StateValues section={data.identity} />
          )}
        </CardSection>
        <CardSection heading={t('label_aws_ses_mail_suppressed')}>
          {!data ? (
            <SkeletonRegion label={t('label_loading')} className="px-gutter">
              <Skeleton width="60%" />
            </SkeletonRegion>
          ) : data.suppressed.error ? (
            <Notice tone="danger" text={data.suppressed.error} wrap />
          ) : !data.suppressed.rows?.length ? (
            <EmptyState />
          ) : (
            <DataTable<Row>
              label={t('label_aws_ses_mail_suppressed')}
              columns={columns}
              rows={data.suppressed.rows.map((destination) => ({ id: destination.address, destination }))}
              onAction={(id) =>
                confirmAction({
                  title: t('button_aws_ses_mail_unsuppress'),
                  description: t('text_are_you_sure'),
                  action: t('button_aws_ses_mail_unsuppress'),
                  onConfirm: () => run(sesPaths.unsuppress, { address: id }),
                })
              }
            />
          )}
        </CardSection>
      </CardBody>
    </>
  );
}

/** A section's values while the tab loads: its labels (the page's), each value a bar. */
function RowsSkeleton({ labels }: { labels: string[] }) {
  const t = useT();
  return (
    <SkeletonRegion label={t('label_loading')} className="px-gutter">
      <AttrGridSkeleton columns={1} labelWidth={LABEL_WIDTH} items={labels.map((label) => ({ label, width: 80 }))} />
    </SkeletonRegion>
  );
}
