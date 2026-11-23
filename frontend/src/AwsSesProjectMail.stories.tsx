import { kitStory, type Meta, type StoryObj } from '@redmine-kit/plugin/storybook';
import { AwsSesProjectMail } from './AwsSesProjectMail';
import { project, projectAdmin } from './fixtures';

// A project's settings › Email (the manifest's settings.project tab aws_ses_mail), in the settings' card.
const meta = {
  title: 'Settings/AwsSesProjectMail',
  component: AwsSesProjectMail,
  ...kitStory({
    frame: 'card',
    bare: true,
    title: 'label_aws_ses_project_mail',
    project: { identifier: 'support', name: 'サポート' },
    permissions: ['manage_aws_ses_mail_settings'],
    responses: { 'GET /projects/:project_id/aws_ses_mail_setting.json': project, 'PATCH /projects/:project_id/aws_ses_mail_setting.json': project },
  }),
} satisfies Meta<typeof AwsSesProjectMail>;

export default meta;
type Story = StoryObj<typeof meta>;

/** A project's manager: the forwarded email's values disabled, as only system administrators change them. */
export const Default: Story = {};

/** A system administrator. */
export const Administrator: Story = kitStory({ responses: { 'GET /projects/:project_id/aws_ses_mail_setting.json': projectAdmin } });

/** A project whose identifier can't be an address: Email receiving off. */
export const NoAddress: Story = kitStory({ responses: { 'GET /projects/:project_id/aws_ses_mail_setting.json': { ...project, address: null } } });

export const Loading: Story = kitStory({ state: 'loading' });
export const Failed: Story = kitStory({ state: 'error' });
export const Forbidden: Story = kitStory({ state: 'forbidden' });
