import { Box, LabeledList, NoticeBox, Section, Stack } from 'tgui-core/components';

import { useBackend } from '../backend';
import { Window } from '../layouts';
import {
  type Ledger,
  LedgerReadout,
} from './ColonyOverworld/LedgerReadout';

type Skill = {
  name: string;
  level: string;
  /** Only sent for the colonist reading the console. */
  experience: number | null;
};

type Colonist = {
  id: string;
  name: string;
  status: string;
  chapters_attended: number;
  chapter_joined: number;
  generation_joined: number;
  has_home: boolean;
  is_you: boolean;
  skills: Skill[];
};

type Data = {
  campaign: string | null;
  generation: number | null;
  chapter: number | null;
  viewer_id: string | null;
  colonists: Colonist[];
  ledger: Ledger | null;
  campaign_clock: number;
};

const STATUS_COLORS = {
  active: 'good',
  away: 'average',
  dead: 'bad',
} as const;

const STATUS_LABELS = {
  active: 'Here',
  away: 'Away',
  dead: 'Dead',
} as const;

function statusColor(status: string): string {
  return STATUS_COLORS[status] ?? 'label';
}

function statusLabel(status: string): string {
  return STATUS_LABELS[status] ?? status;
}

function ColonistEntry(props: { colonist: Colonist }) {
  const { colonist } = props;

  return (
    <Section
      title={colonist.is_you ? `${colonist.name} (you)` : colonist.name}
      buttons={
        <Box color={statusColor(colonist.status)}>
          {statusLabel(colonist.status)}
        </Box>
      }
    >
      <LabeledList>
        <LabeledList.Item label="Chapters here">
          {colonist.chapters_attended}
        </LabeledList.Item>
        <LabeledList.Item label="Arrived">
          {`Chapter ${colonist.chapter_joined}, generation ${colonist.generation_joined}`}
        </LabeledList.Item>
        <LabeledList.Item label="Home">
          {colonist.has_home ? 'Has claimed a bed' : 'No bed of their own'}
        </LabeledList.Item>
      </LabeledList>
      {colonist.skills.length === 0 ? (
        <Box color="label" mt={1}>
          Nothing learned here yet.
        </Box>
      ) : (
        <Box mt={1}>
          <LabeledList>
            {colonist.skills.map((skill) => (
              <LabeledList.Item key={skill.name} label={skill.name}>
                {skill.level}
                {skill.experience !== null && (
                  <Box as="span" color="label">
                    {` (${skill.experience} exp)`}
                  </Box>
                )}
              </LabeledList.Item>
            ))}
          </LabeledList>
        </Box>
      )}
    </Section>
  );
}

export const ColonyRegister = (props) => {
  const { data } = useBackend<Data>();
  const { campaign, generation, chapter, colonists, ledger } = data;

  return (
    <Window title="Colony Register" width={520} height={640}>
      <Window.Content scrollable>
        {!campaign ? (
          <NoticeBox>
            This settlement keeps no register. Nobody here is being remembered
            between one day and the next.
          </NoticeBox>
        ) : (
          <Stack vertical>
            <Stack.Item>
              <LedgerReadout ledger={ledger} />
            </Stack.Item>
            <Stack.Item>
              <Section title="Settlement">
                <LabeledList>
                  <LabeledList.Item label="Colony">{campaign}</LabeledList.Item>
                  <LabeledList.Item label="Generation">
                    {generation}
                  </LabeledList.Item>
                  <LabeledList.Item label="Chapter">{chapter}</LabeledList.Item>
                  <LabeledList.Item label="People">
                    {colonists.length}
                  </LabeledList.Item>
                </LabeledList>
              </Section>
            </Stack.Item>
            {colonists.length === 0 ? (
              <Stack.Item>
                <NoticeBox>
                  Nobody has lived here yet. The first person to arrive will be
                  written down.
                </NoticeBox>
              </Stack.Item>
            ) : (
              colonists.map((colonist) => (
                <Stack.Item key={colonist.id}>
                  <ColonistEntry colonist={colonist} />
                </Stack.Item>
              ))
            )}
          </Stack>
        )}
      </Window.Content>
    </Window>
  );
};
