import { AttrGrid, Button, EmptyState, Notice } from '@redmine-kit/ui';
import { CardHeaderActions, useT } from '@redmine-kit/plugin';
import type { SesActionJson, SesRow, SesSection } from './api';

// The parts both email tabs draw the same way, as Redmine's pages share them (aws_ses_mail_sending/_updated,
// aws_admin/values).

/** Redmine's .tabular labels (175px), as the classic pages' values line up. */
export const LABEL_WIDTH = 175;

/**
 * When the state of SES and DNS was read and 最新の情報に更新 (reads it again, for both tabs), in the card's header as the
 * tab's action (the classic pages' contextual links at the top right).
 */
export function RefreshAction({ updated, busy, onRefresh }: { updated: string | null; busy: boolean; onRefresh: () => void }) {
  const t = useT();
  return (
    <CardHeaderActions>
      {updated && <span className="text-meta text-text-muted">{t('label_aws_ses_mail_updated', { time: updated })}</span>}
      <Button icon="refresh" disabled={busy} onClick={onRefresh}>
        {t('button_aws_ses_mail_refresh')}
      </Button>
    </CardHeaderActions>
  );
}

/** Values as label and value pairs (the classic pages' aws_admin/values). */
export function ValueRows({ rows }: { rows: SesRow[] }) {
  return (
    <div className="px-gutter">
      <AttrGrid columns={1} labelWidth={LABEL_WIDTH} items={rows.map((row) => ({ label: row.name, value: row.value }))} />
    </div>
  );
}

/** A section of the stored state: the error of reading it, its values, or 表示するデータがありません. */
export function StateValues({ section }: { section: SesSection<SesRow[]> }) {
  if (section.error) return <Notice tone="danger" text={section.error} wrap />;
  return section.rows ? <ValueRows rows={section.rows} /> : <EmptyState />;
}

/** An action's notice and errors, above the sections. */
export function ActionResult({ result, errors }: { result: SesActionJson | null; errors: string[] }) {
  return (
    <>
      {result?.notice && <Notice tone="neutral" text={result.notice} />}
      {errors.length > 0 && <Notice tone="danger" role="alert" text={errors.join('\n')} wrap />}
    </>
  );
}
