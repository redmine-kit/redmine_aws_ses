import { kitStory, type Meta, type StoryObj } from '@redmine-kit/plugin/storybook';
import { AwsSesMailReceiving } from './AwsSesMailReceiving';
import { receiving, receivingEmpty } from './fixtures';

// Administration › AWS › Email receiving (the manifest's /admin/aws/mail_receiving, a tab of the page AWS), in the app's
// card with the page's title.
const meta = {
  title: 'Screens/AwsSesMailReceiving',
  component: AwsSesMailReceiving,
  ...kitStory({ frame: 'card', bare: true, title: 'AWS', responses: { 'GET /admin/aws/mail_receiving.json': receiving } }),
} satisfies Meta<typeof AwsSesMailReceiving>;

export default meta;
type Story = StoryObj<typeof meta>;

/** The addresses with a warning and the projects' addresses, two received email, the settings. */
export const Default: Story = {};

/** No domain, no bucket, no email. */
export const Empty: Story = kitStory({ responses: { 'GET /admin/aws/mail_receiving.json': receivingEmpty } });

export const Loading: Story = kitStory({ state: 'loading' });
export const Failed: Story = kitStory({ state: 'error' });
export const Forbidden: Story = kitStory({ state: 'forbidden' });
