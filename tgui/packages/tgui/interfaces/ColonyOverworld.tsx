import { useState } from 'react';
import {
  Box,
  Button,
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
  parseCellId,
  RegionMap,
} from './ColonyOverworld/RegionMap';

type Member = {
  id: string;
  name: string;
  ready: boolean;
  present: boolean;
  has_locker: boolean;
  is_you: boolean;
};

type Party = {
  party_id: string;
  state: string;
  is_planning: boolean;
  members: Member[];
  max_members: number;
  everyone_ready: boolean;
  destination_site_id: string | null;
  destination_cell: string | null;
  route: string[];
  route_kind: string | null;
  travel_seconds: number;
  route_danger: number;
  supply_cost: number;
  supplies_held: number;
  supplies_shortfall_price: number;
  has_larder: boolean;
  you_are_a_member: boolean;
  you_are_ready: boolean;
  join_problem: string | null;
  departure_problem: string | null;
};

type RouteOffer = {
  kind: string;
  route: string[];
  steps: number;
  travel_seconds: number;
  danger: number;
  supply_cost: number;
};

type Data = {
  radius: number;
  options: Record<string, string>;
  fingerprint: string | null;
  cells: Cell[];
  terrain_names: Record<string, string>;
  topology_names: Record<string, string>;
  known_cells: KnownCell[];
  known_sites: KnownSite[];
  campaign: string | null;
  chapter: number | null;
  colony_under_attack: boolean;
  viewer_colonist_id: string | null;
  viewer_is_colonist: boolean;
  viewer_has_locker: boolean;
  previewed_site_id: string | null;
  party: Party | null;
  route_offers: RouteOffer[];
};

/** Seconds into something a person can judge at a glance. Journeys are minutes, not thousands of seconds. */
function describeDuration(seconds: number): string {
  if (!seconds) {
    return 'no time at all';
  }
  const minutes = Math.floor(seconds / 60);
  const rest = seconds % 60;
  if (!minutes) {
    return `${rest}s`;
  }
  return rest ? `${minutes}m ${rest}s` : `${minutes}m`;
}

const ROUTE_LABELS: Record<string, string> = {
  fastest: 'Fastest',
  safer: 'Safer',
};

const STATE_LABELS: Record<string, string> = {
  forming: 'being assembled',
  departing: 'setting out',
  outbound: 'on the road',
  decision: 'halted',
  at_site: 'working the site',
  returning: 'heading home',
  complete: 'home',
  lost: 'lost',
};

export const ColonyOverworld = (props) => {
  const { act, data } = useBackend<Data>();
  const {
    radius,
    options,
    cells,
    terrain_names,
    topology_names,
    known_cells,
    known_sites,
    campaign,
    chapter,
    colony_under_attack,
    viewer_is_colonist,
    previewed_site_id,
    party,
    route_offers,
  } = data;

  // Which hex the player is looking at. Local, except that picking one with a site on it asks the server to
  // price the journey there - the totals are its business, not ours.
  const [selected, setSelected] = useState<string | null>(null);

  const knownById: Record<string, KnownCell> = {};
  for (const cell of known_cells) {
    knownById[cell.id] = cell;
  }

  const siteByCell: Record<string, KnownSite> = {};
  for (const site of known_sites) {
    siteByCell[site.cell] = site;
  }

  const selectedCell = selected ? knownById[selected] : null;
  const selectedSite = selected ? siteByCell[selected] : null;
  const selectedAxial = selected ? parseCellId(selected) : null;

  const selectCell = (cellId: string) => {
    setSelected(cellId);
    const site = siteByCell[cellId];
    // Null clears the preview server-side, so walking your eye over empty ground stops offering a stale route.
    act('preview_site', { site_id: site ? site.id : null });
  };

  return (
    <Window title="Expedition Table" width={1010} height={660}>
      <Window.Content>
        {!radius ? (
          <NoticeBox>
            This table is not showing a region. No campaign is running here.
          </NoticeBox>
        ) : (
          <Stack fill>
            <Stack.Item grow>
              <Section
                fill
                title={campaign ? `${campaign} — chapter ${chapter}` : 'Region'}
                buttons={
                  !!colony_under_attack && <Box color="bad">Colony under attack</Box>
                }
              >
                <RegionMap
                  radius={radius}
                  cells={cells}
                  knownCells={known_cells}
                  knownSites={known_sites}
                  selected={selected}
                  onSelect={selectCell}
                  route={party?.route}
                />
              </Section>
            </Stack.Item>

            <Stack.Item width="330px">
              <Stack fill vertical>
                <Stack.Item grow>
                  <Section fill scrollable title="Expedition">
                    <ExpeditionPanel
                      party={party}
                      offers={route_offers}
                      previewedSiteId={previewed_site_id}
                      viewerIsColonist={viewer_is_colonist}
                      onAct={act}
                    />
                  </Section>
                </Stack.Item>

                <Stack.Item>
                  <Section title="Selected">
                    {!selected ? (
                      <Box color="label">
                        Choose a hex to read what is known about it.
                      </Box>
                    ) : !selectedCell ? (
                      <Box color="label">
                        {selectedAxial
                          ? `Unsurveyed ground, ${Math.max(
                              Math.abs(selectedAxial.q),
                              Math.abs(selectedAxial.r),
                              Math.abs(-selectedAxial.q - selectedAxial.r),
                            )} hexes out. Nobody has been there.`
                          : 'Unsurveyed ground.'}
                      </Box>
                    ) : (
                      <LabeledList>
                        <LabeledList.Item label="Terrain">
                          {terrain_names[selectedCell.terrain] ?? selectedCell.terrain}
                        </LabeledList.Item>
                        <LabeledList.Item label="Going">
                          {topology_names[selectedCell.topology] ??
                            selectedCell.topology}
                        </LabeledList.Item>
                        <LabeledList.Item label="Crossing">
                          {selectedCell.seconds
                            ? `${selectedCell.seconds}s`
                            : 'impassable'}
                        </LabeledList.Item>
                        <LabeledList.Item label="Danger">
                          {selectedCell.danger
                            ? '!'.repeat(selectedCell.danger)
                            : 'nothing reported'}
                        </LabeledList.Item>
                        {!!selectedSite && (
                          <LabeledList.Item label="Site">
                            {selectedSite.kind === 'resource'
                              ? `deposit, about ${selectedSite.yield} units`
                              : 'ruin'}
                          </LabeledList.Item>
                        )}
                      </LabeledList>
                    )}
                  </Section>
                </Stack.Item>

                <Stack.Item>
                  <Section title="Region">
                    <LabeledList>
                      <LabeledList.Item label="Extent">
                        {options.extent}
                      </LabeledList.Item>
                      <LabeledList.Item label="Terrain">
                        {options.roughness}
                      </LabeledList.Item>
                      <LabeledList.Item label="Surveyed">
                        {`${known_cells.length} of ${cells.length} cells`}
                      </LabeledList.Item>
                    </LabeledList>
                  </Section>
                </Stack.Item>
              </Stack>
            </Stack.Item>
          </Stack>
        )}
      </Window.Content>
    </Window>
  );
};

function ExpeditionPanel(props: {
  party: Party | null;
  offers: RouteOffer[];
  previewedSiteId: string | null;
  viewerIsColonist: boolean;
  onAct: (action: string, payload?: object) => void;
}) {
  const { party, offers, previewedSiteId, viewerIsColonist, onAct } = props;

  if (!party) {
    return (
      <>
        <Box color="label" mb={1}>
          No expedition is being planned. Starting one opens the roll for anybody
          who wants to go.
        </Box>
        <Button fluid icon="flag" onClick={() => onAct('form_party')}>
          Start an expedition
        </Button>
      </>
    );
  }

  const planning = party.is_planning;
  const shortOfFood = party.supply_cost > party.supplies_held;

  return (
    <>
      <LabeledList>
        <LabeledList.Item label="Status">
          {STATE_LABELS[party.state] ?? party.state}
        </LabeledList.Item>
        <LabeledList.Item label="Signed on">
          {`${party.members.length} of ${party.max_members}`}
        </LabeledList.Item>
        {!!party.route.length && (
          <>
            <LabeledList.Item label="Journey">
              {`${describeDuration(party.travel_seconds)} out, ${party.route.length - 1} crossings`}
            </LabeledList.Item>
            <LabeledList.Item label="Risk">
              {party.route_danger
                ? '!'.repeat(Math.min(party.route_danger, 9))
                : 'a quiet road'}
            </LabeledList.Item>
            <LabeledList.Item label="Food">
              <Box inline color={shortOfFood ? 'average' : 'good'}>
                {`${party.supply_cost} needed, ${party.supplies_held} in the larder`}
              </Box>
              {/*
                Short stores are not a refusal - the colony buys the difference in. Shown as the price rather
                than as a warning, because it is a cost to weigh, not a problem to fix.
              */}
              {!!shortOfFood && (
                <Box color="label">
                  {party.has_larder
                    ? `buying in the rest costs ${party.supplies_shortfall_price}cr`
                    : `no larder built - all ${party.supplies_shortfall_price}cr comes out of the budget`}
                </Box>
              )}
            </LabeledList.Item>
          </>
        )}
      </LabeledList>

      <Box mt={1.5} mb={0.5} bold>
        Who is going
      </Box>
      {party.members.length === 0 ? (
        <Box color="label">Nobody has signed on yet.</Box>
      ) : (
        party.members.map((member) => (
          <Box key={member.id}>
            <Box inline color={member.ready ? 'good' : 'label'} width="14px">
              {member.ready ? '✓' : '·'}
            </Box>
            <Box inline bold={member.is_you}>
              {member.name}
              {member.is_you ? ' (you)' : ''}
            </Box>
            {!member.present && (
              <Box inline color="bad" ml={1}>
                not here
              </Box>
            )}
          </Box>
        ))
      )}

      {/* Your own row of buttons. Nobody signs anybody else up, so there is only ever one person's worth. */}
      {!viewerIsColonist ? (
        <NoticeBox mt={1.5} info>
          Only this colony&apos;s colonists can join an expedition.
        </NoticeBox>
      ) : (
        <Box mt={1.5}>
          {party.you_are_a_member ? (
            <>
              <Button
                icon={party.you_are_ready ? 'circle-check' : 'circle'}
                color={party.you_are_ready ? 'good' : undefined}
                disabled={!planning || !party.route.length}
                tooltip={
                  party.route.length ? undefined : 'Choose a route to be ready for.'
                }
                onClick={() =>
                  onAct('set_ready', { ready: party.you_are_ready ? 0 : 1 })
                }
              >
                {party.you_are_ready ? 'Ready' : 'Say you are ready'}
              </Button>
              <Button
                icon="right-from-bracket"
                color="bad"
                disabled={!planning}
                onClick={() => onAct('leave')}
              >
                Withdraw
              </Button>
            </>
          ) : (
            <Button
              fluid
              icon="user-plus"
              disabled={!!party.join_problem}
              tooltip={party.join_problem ?? undefined}
              onClick={() => onAct('join')}
            >
              Sign on
            </Button>
          )}
        </Box>
      )}

      {/* The two offers, priced by the server for whoever is signed on right now. */}
      {!!planning && !!previewedSiteId && (
        <>
          <Box mt={1.5} mb={0.5} bold>
            Ways there
          </Box>
          {offers.length === 0 ? (
            <Box color="label">
              No route the colony has walked reaches that site.
            </Box>
          ) : (
            offers.map((offer) => (
              <Button
                key={offer.kind}
                fluid
                mb={0.5}
                selected={
                  party.route_kind === offer.kind &&
                  party.destination_site_id === previewedSiteId
                }
                onClick={() => onAct('choose_route', { kind: offer.kind })}
              >
                {`${ROUTE_LABELS[offer.kind] ?? offer.kind} — ${describeDuration(
                  offer.travel_seconds,
                )}, ${offer.danger ? `${offer.danger} risk` : 'quiet'}, ${offer.supply_cost} food`}
              </Button>
            ))
          )}
        </>
      )}

      {!!planning && !!party.destination_site_id && (
        <Box mt={1.5}>
          {!!party.departure_problem && (
            <NoticeBox info mb={1}>
              {party.departure_problem}
            </NoticeBox>
          )}
          <Button
            fluid
            icon="person-hiking"
            color="good"
            disabled={!!party.departure_problem}
            onClick={() => onAct('depart')}
          >
            Set out
          </Button>
          <Button
            fluid
            mt={0.5}
            icon="xmark"
            onClick={() => onAct('clear_route')}
          >
            Clear the plan
          </Button>
        </Box>
      )}
    </>
  );
}
