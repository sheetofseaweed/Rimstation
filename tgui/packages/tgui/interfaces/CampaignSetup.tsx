import {
  Box,
  Button,
  Input,
  LabeledList,
  NoticeBox,
  Section,
  Stack,
} from 'tgui-core/components';

import { useBackend } from '../backend';
import { Window } from '../layouts';
import {
  type Cell,
  type KnownCell,
  type KnownSite,
  RegionMap,
} from './ColonyOverworld/RegionMap';

type Choice = {
  id: string;
  label: string;
  detail: string;
};

type Data = {
  campaign_id: string;
  id_is_usable: boolean;
  id_problem: string | null;
  options: Record<string, string>;
  extent_choices: Choice[];
  roughness_choices: Choice[];
  abundance_choices: Choice[];
  preview_stale: boolean;
  preview_building: boolean;
  radius: number;
  cells: Cell[];
  known_cells: KnownCell[];
  known_sites: KnownSite[];
  resource_site_count: number;
  ruin_site_count: number;
  fingerprint: string | null;
  can_confirm: boolean;
  blocked_reason: string | null;
};

export const CampaignSetup = (props) => {
  const { act, data } = useBackend<Data>();
  const {
    campaign_id,
    id_is_usable,
    id_problem,
    options,
    extent_choices,
    roughness_choices,
    abundance_choices,
    preview_stale,
    preview_building,
    radius,
    cells,
    known_cells,
    known_sites,
    resource_site_count,
    ruin_site_count,
    can_confirm,
    blocked_reason,
  } = data;

  return (
    <Window title="Start a Colony Campaign" width={900} height={660}>
      <Window.Content>
        <Stack fill>
          <Stack.Item width="300px">
            <Stack fill vertical>
              <Stack.Item>
                <Section title="Campaign">
                  <LabeledList>
                    <LabeledList.Item label="Name">
                      <Input
                        fluid
                        value={campaign_id}
                        onChange={(value) => act('set_id', { campaign_id: value })}
                      />
                    </LabeledList.Item>
                  </LabeledList>
                  {!id_is_usable && !!id_problem && (
                    <Box mt={1} color="bad">
                      {id_problem}
                    </Box>
                  )}
                </Section>
              </Stack.Item>

              <Stack.Item grow>
                <Section fill scrollable title="The region">
                  <Box color="label" mb={1}>
                    These shape the country around the colony. They do not change the
                    settlement map you are standing on.
                  </Box>

                  <OptionGroup
                    label="Extent"
                    choices={extent_choices}
                    chosen={options.extent}
                    onPick={(id) => act('set_option', { option: 'extent', value: id })}
                  />
                  <OptionGroup
                    label="Terrain"
                    choices={roughness_choices}
                    chosen={options.roughness}
                    onPick={(id) => act('set_option', { option: 'roughness', value: id })}
                  />
                  <OptionGroup
                    label="Resources"
                    choices={abundance_choices}
                    chosen={options.abundance}
                    onPick={(id) => act('set_option', { option: 'abundance', value: id })}
                  />
                </Section>
              </Stack.Item>

              <Stack.Item>
                <Section>
                  {!!blocked_reason && (
                    <NoticeBox danger mb={1}>
                      {blocked_reason}
                    </NoticeBox>
                  )}
                  <Button
                    fluid
                    color="good"
                    disabled={!can_confirm}
                    tooltip={
                      can_confirm
                        ? 'This round becomes chapter one. The colony is committed at round end.'
                        : undefined
                    }
                    onClick={() => act('confirm')}
                  >
                    Start this campaign
                  </Button>
                </Section>
              </Stack.Item>
            </Stack>
          </Stack.Item>

          <Stack.Item grow>
            <Section
              fill
              title="Regional preview"
              buttons={
                <Button
                  icon="rotate"
                  disabled={preview_building}
                  onClick={() => act('generate_preview')}
                >
                  {preview_building ? 'Generating…' : 'Generate preview'}
                </Button>
              }
            >
              {!radius ? (
                <Box color="label">
                  Choose your options and generate a preview to see the region this
                  campaign would begin on.
                </Box>
              ) : (
                <Stack fill vertical>
                  {!!preview_stale && (
                    <Stack.Item>
                      <NoticeBox info>
                        Options changed since this preview was drawn. Generate it again to
                        see what you would actually get.
                      </NoticeBox>
                    </Stack.Item>
                  )}
                  <Stack.Item>
                    <Box color="label">
                      {`${cells.length} hexes · ${resource_site_count} deposits · ${ruin_site_count} ruins`}
                    </Box>
                  </Stack.Item>
                  <Stack.Item grow>
                    <RegionMap
                      radius={radius}
                      cells={cells}
                      knownCells={known_cells}
                      knownSites={known_sites}
                      selected={null}
                      onSelect={() => undefined}
                      revealAll
                    />
                  </Stack.Item>
                </Stack>
              )}
            </Section>
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};

function OptionGroup(props: {
  label: string;
  choices: Choice[];
  chosen: string;
  onPick: (id: string) => void;
}) {
  const { label, choices, chosen, onPick } = props;
  const detail = choices.find((choice) => choice.id === chosen)?.detail;

  return (
    <Box mb={2}>
      <Box bold mb={0.5}>
        {label}
      </Box>
      {choices.map((choice) => (
        <Button
          key={choice.id}
          selected={chosen === choice.id}
          onClick={() => onPick(choice.id)}
        >
          {choice.label}
        </Button>
      ))}
      {!!detail && (
        <Box mt={0.5} color="label">
          {detail}
        </Box>
      )}
    </Box>
  );
}
