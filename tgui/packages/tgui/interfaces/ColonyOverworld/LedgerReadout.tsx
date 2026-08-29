import { Box, LabeledList, Section, Table } from 'tgui-core/components';

export type LedgerEntry = {
  id: number;
  clock: number;
  category: string;
  reason: string;
  amount: number;
  resource: string | null;
  actor: string | null;
  related: string | null;
};

export type Ledger = {
  credits: number;
  debt: number;
  stored_credits: number;
  resources: Record<string, number>;
  entries: LedgerEntry[];
  entry_count: number;
};

/**
 * Campaign deciseconds as something a person can place.
 *
 * Shown as elapsed campaign time rather than a date, because a campaign has no calendar - "day 2, 4h" is how
 * far into the whole thing an entry sits, which is the only frame anybody has for it.
 */
export function describeCampaignClock(deciseconds: number): string {
  const totalMinutes = Math.floor(deciseconds / 600);
  const days = Math.floor(totalMinutes / 1440);
  const hours = Math.floor((totalMinutes % 1440) / 60);
  const minutes = totalMinutes % 60;

  if (days > 0) {
    return `day ${days + 1}, ${hours}h`;
  }
  if (hours > 0) {
    return `${hours}h ${minutes}m`;
  }
  return `${minutes}m`;
}

/** Broad headings, so an entry says what kind of activity moved the money before you read the reason. */
const CATEGORY_LABELS: Record<string, string> = {
  trade: 'Trade',
  incident: 'Incident',
  research: 'Research',
  salvage: 'Salvage',
  upkeep: 'Upkeep',
  admin: 'Admin',
  theft: 'Theft',
  expedition: 'Expedition',
};

/** Reason codes are written for logs, not for people. */
const REASON_LABELS: Record<string, string> = {
  expedition_supplies: 'packed rations for an expedition',
  expedition_rations_returned: 'unspent rations came home',
  expedition_stood_down: 'an expedition stood down',
  site_worked: 'worked a deposit',
  raid_theft: 'raiders carried goods off',
  'food stored': 'food put in the larder',
  'food taken from stores': 'food taken from the larder',
  'bought in rations': 'bought rations in',
  'rations sold back': 'sold rations back',
  'fed a refugee': 'fed a refugee',
};

function describeReason(reason: string): string {
  return REASON_LABELS[reason] ?? reason.replace(/_/g, ' ');
}

/**
 * The colony's books.
 *
 * Shared between the expedition table and the colony register because they are the same question asked in two
 * places: the table wants to know what a journey can afford, the register wants to know what the colony has.
 */
export function LedgerReadout(props: { ledger: Ledger | null; fill?: boolean }) {
  const { ledger, fill } = props;

  if (!ledger) {
    return (
      <Section fill={fill} title="Colony accounts">
        <Box color="label">
          No campaign is running here, so the colony keeps no books.
        </Box>
      </Section>
    );
  }

  const resourceIds = Object.keys(ledger.resources);

  return (
    <Section fill={fill} scrollable title="Colony accounts">
      <LabeledList>
        <LabeledList.Item label="Treasury">
          <Box inline color={ledger.credits > 0 ? 'good' : 'label'}>
            {`${ledger.credits} cr`}
          </Box>
        </LabeledList.Item>
        {ledger.debt > 0 && (
          <LabeledList.Item label="Debt">
            <Box inline color="bad">{`${ledger.debt} cr`}</Box>
          </LabeledList.Item>
        )}
        <LabeledList.Item label="Stores">
          {resourceIds.length === 0
            ? 'nothing tracked'
            : resourceIds
                .map((id) => `${ledger.resources[id]} ${id}`)
                .join(', ')}
        </LabeledList.Item>
      </LabeledList>

      <Box mt={1.5} mb={0.5} bold>
        Recent entries
      </Box>
      {ledger.entries.length === 0 ? (
        <Box color="label">Nothing has been recorded yet.</Box>
      ) : (
        <>
          <Table>
            {ledger.entries.map((entry) => (
              <Table.Row key={entry.id}>
                <Table.Cell collapsing pr={1} color="label">
                  {describeCampaignClock(entry.clock)}
                </Table.Cell>
                <Table.Cell collapsing pr={1}>
                  {CATEGORY_LABELS[entry.category] ?? entry.category}
                </Table.Cell>
                <Table.Cell>{describeReason(entry.reason)}</Table.Cell>
                <Table.Cell collapsing textAlign="right">
                  {/* Zero-amount entries are real records of things that moved no money, so they show a dash
                      rather than a misleading 0. */}
                  {entry.amount === 0 ? (
                    <Box inline color="label">
                      —
                    </Box>
                  ) : (
                    <Box inline color={entry.amount > 0 ? 'good' : 'bad'}>
                      {`${entry.amount > 0 ? '+' : ''}${entry.amount}${entry.resource ? ` ${entry.resource}` : ' cr'}`}
                    </Box>
                  )}
                </Table.Cell>
              </Table.Row>
            ))}
          </Table>
          {ledger.entry_count > ledger.entries.length && (
            <Box mt={1} color="label">
              {`Showing the last ${ledger.entries.length} of ${ledger.entry_count} entries.`}
            </Box>
          )}
        </>
      )}
    </Section>
  );
}
