import { kitStory, type Meta, type StoryObj } from '@redmine-kit/plugin/storybook';
import { AwsSesMailSending } from './AwsSesMailSending';
import { sending, sendingEmpty, sendingErrors } from './fixtures';

// Administration › AWS › Email sending (the manifest's /admin/aws/mail_sending, a tab of the page AWS), in the app's card
// with the page's title.
const meta = {
  title: 'Screens/AwsSesMailSending',
  component: AwsSesMailSending,
  ...kitStory({ frame: 'card', bare: true, title: 'AWS', responses: { 'GET /admin/aws/mail_sending.json': sending } }),
} satisfies Meta<typeof AwsSesMailSending>;

export default meta;
type Story = StoryObj<typeof meta>;

/** The account, the domain and an address on the suppression list. */
export const Default: Story = {};

/** Before the first refresh, the sender address not of a domain. */
export const Empty: Story = kitStory({ responses: { 'GET /admin/aws/mail_sending.json': sendingEmpty } });

/** SES refused each read. */
export const ReadErrors: Story = kitStory({ responses: { 'GET /admin/aws/mail_sending.json': sendingErrors } });

export const Loading: Story = kitStory({ state: 'loading' });
export const Failed: Story = kitStory({ state: 'error' });
export const Forbidden: Story = kitStory({ state: 'forbidden' });
