import { useEffect, useRef, useState } from 'react';
import {
  Box,
  Button,
  LabeledList,
  NoticeBox,
  Section,
  Stack,
  Tabs,
} from 'tgui-core/components';

import { useBackend } from '../backend';
import { Window } from '../layouts';
import { type Ledger, LedgerReadout } from './ColonyOverworld/LedgerReadout';
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
  current_cell: string | null;
  next_cell: string | null;
  leg_started_at: number;
  leg_arrives_at: number;
  clock_now: number;
  supplies_carried: number;
  pending_decision: PendingDecision | null;
  gathered_ids: string[];
  has_hitching_post: boolean;
  gather_radius: number;
  you_are_a_member: boolean;
  you_are_ready: boolean;
  join_problem: string | null;
  departure_problem: string | null;
};

type PendingDecision = {
  id: string;
  /** Which archetype this is. Audit and styling only; the choices below are what can be acted on. */
  kind: string;
  name: string;
  reveal: string;
  cell: string;
  choices: string[];
  /** choice id -> [label, detail], written in DM so a new archetype needs no change here. */
  labels: Record<string, [string, string]>;
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
  colonists_at_colony: number;
  colonists_leaving: number;
  viewer_colonist_id: string | null;
  viewer_is_colonist: boolean;
  viewer_has_locker: boolean;
  previewed_site_id: string | null;
  party: Party | null;
  route_offers: RouteOffer[];
  ledger: Ledger | null;
  campaign_clock: number;
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

/**
 * How far along the current leg the party is, 0 to 1.
 *
 * Recomputed locally from the three server anchors on a timer, rather than being pushed every tick. The offset
 * between the server's campaign clock and this client's own clock is measured once per push, so closing the
 * window and reopening it produces the same marker position rather than restarting the animation.
 */
function useLegProgress(party: Party | null): number {
  const [progress, setProgress] = useState(0);
  // Captured on each push: what the local clock read when the server said `clock_now`.
  const anchorRef = useRef({ serverNow: 0, localNow: 0 });

  const serverNow = party?.clock_now ?? 0;
  const startedAt = party?.leg_started_at ?? 0;
  const arrivesAt = party?.leg_arrives_at ?? 0;

  useEffect(() => {
    anchorRef.current = { serverNow, localNow: Date.now() };
  }, [serverNow]);

  useEffect(() => {
    if (!arrivesAt || arrivesAt <= startedAt) {
      setProgress(0);
      return;
    }

    const tick = () => {
      // Deciseconds, to match the campaign clock.
      const elapsedLocal = (Date.now() - anchorRef.current.localNow) / 100;
      const estimated = anchorRef.current.serverNow + elapsedLocal;
      const fraction = (estimated - startedAt) / (arrivesAt - startedAt);
      setProgress(Math.max(0, Math.min(1, fraction)));
    };

    tick();
    const handle = setInterval(tick, 250);
    return () => clearInterval(handle);
  }, [startedAt, arrivesAt]);

  return progress;
}

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
    colonists_at_colony,
    colonists_leaving,
    viewer_is_colonist,
    previewed_site_id,
    party,
    route_offers,
    ledger,
  } = data;

  // Which hex the player is looking at. Local, except that picking one with a site on it asks the server to
  // price the journey there - the totals are its business, not ours.
  const [selected, setSelected] = useState<string | null>(null);
  // Which of the two reference panes the bottom of the column is showing. Tabbed rather than stacked because
  // the accounts are a table and the column is not wide enough to give both of them room at once.
  const [pane, setPane] = useState<'region' | 'ledger'>('region');

  const knownById: Record<string, KnownCell> = {};
  for (const cell of known_cells) {
    knownById[cell.id] = cell;
  }

  const siteByCell: Record<string, KnownSite> = {};
  for (const site of known_sites) {
    siteByCell[site.cell] = site;
  }

  const legProgress = useLegProgress(party);
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
                  !!colony_under_attack && (
                    <Box color="bad">Colony under attack</Box>
                  )
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
                  partyFrom={party?.current_cell ?? undefined}
                  partyTo={party?.next_cell ?? undefined}
                  partyProgress={legProgress}
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
                      legProgress={legProgress}
                      atColony={colonists_at_colony}
                      leaving={colonists_leaving}
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
                          {terrain_names[selectedCell.terrain] ??
                            selectedCell.terrain}
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
                            <Box inline color={selectedSite.available ? undefined : 'label'}>
                              {selectedSite.kind === 'resource'
                                ? `deposit, about ${selectedSite.yield} units`
                                : 'ruin'}
                            </Box>
                            {/*
                              A finished site stays drawn. Removing it would redraw explored ground as
                              unknown and invite somebody to walk out to it a second time for nothing.
                            */}
                            {!selectedSite.available && (
                              <Box color="label">
                                {selectedSite.state === 'depleted'
                                  ? 'Stripped. Nothing left to take.'
                                  : 'Already recovered.'}
                              </Box>
                            )}
                          </LabeledList.Item>
                        )}
                      </LabeledList>
                    )}
                  </Section>
                </Stack.Item>

                <Stack.Item>
                  <Tabs fluid>
                    <Tabs.Tab
                      selected={pane === 'region'}
                      onClick={() => setPane('region')}
                    >
                      Region
                    </Tabs.Tab>
                    <Tabs.Tab
                      selected={pane === 'ledger'}
                      onClick={() => setPane('ledger')}
                    >
                      Accounts
                    </Tabs.Tab>
                  </Tabs>
                  {pane === 'region' ? (
                    <Section>
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
                  ) : (
                    <LedgerReadout ledger={ledger} />
                  )}
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
  legProgress: number;
  atColony: number;
  leaving: number;
  onAct: (action: string, payload?: object) => void;
}) {
  const {
    party,
    offers,
    previewedSiteId,
    viewerIsColonist,
    legProgress,
    atColony,
    leaving,
    onAct,
  } = props;

  if (!party) {
    return (
      <>
        <Box color="label" mb={1}>
          No expedition is being planned. Starting one opens the roll for
          anybody who wants to go.
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
      {/* The road is asking something and the caravan is standing still until somebody answers. */}
      {!!party.pending_decision && (
        <Section title={party.pending_decision.name} mb={1}>
          <Box mb={1}>{party.pending_decision.reveal}</Box>
          <Box color="label" mb={1}>
            The caravan has stopped short of {party.pending_decision.cell}. Any
            member can decide for the party, and the first answer stands.
          </Box>
          {/*
            Every lookup is guarded to the bottom. The copy is content sent by DM, so a payload can legitimately
            arrive without it - an archetype that no longer exists, an older record - and a choice with no label
            should read oddly rather than take the whole window down.
          */}
          {party.pending_decision.choices.map((choice) => (
            <Button
              key={choice}
              fluid
              mb={0.5}
              tooltip={party.pending_decision?.labels?.[choice]?.[1]}
              disabled={!party.you_are_a_member}
              onClick={() =>
                onAct('answer_decision', {
                  decision_id: party.pending_decision?.id,
                  choice: choice,
                })
              }
            >
              {party.pending_decision?.labels?.[choice]?.[0] ?? choice}
            </Button>
          ))}
        </Section>
      )}

      <LabeledList>
        <LabeledList.Item label="Status">
          {STATE_LABELS[party.state] ?? party.state}
        </LabeledList.Item>
        {!!party.next_cell && !party.pending_decision && (
          <LabeledList.Item label="Crossing to">
            {`${party.next_cell} — ${Math.round(legProgress * 100)}% of the way`}
          </LabeledList.Item>
        )}
        {!party.is_planning && (
          <LabeledList.Item label="Rations">
            {`${party.supplies_carried} carried`}
          </LabeledList.Item>
        )}
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

      {/*
        What the colony is left with. Worth saying before departure rather than after: the people signed on are
        still standing here, so the number only becomes true once they walk out.
      */}
      {!!planning &&
        leaving > 0 &&
        (atColony - leaving <= 0 ? (
          <NoticeBox mt={1} danger>
            This would leave nobody in the settlement.
          </NoticeBox>
        ) : (
          <NoticeBox mt={1} info>
            {`This would leave ${atColony - leaving} in the settlement.`}
          </NoticeBox>
        ))}

      <Box mt={1.5} mb={0.5} bold>
        Who is going
      </Box>
      {party.members.length === 0 ? (
        <Box color="label">Nobody has signed on yet.</Box>
      ) : (
        party.members.map((member) => {
          // Two separate things a member can be short of: having said yes, and actually being at the post.
          // Shown apart because they are fixed in different places - one at this table, one by walking.
          const atPost = party.gathered_ids.includes(member.id);
          return (
            <Box key={member.id}>
              <Box inline color={member.ready ? 'good' : 'label'} width="14px">
                {member.ready ? '✓' : '·'}
              </Box>
              <Box inline bold={member.is_you}>
                {member.name}
                {member.is_you ? ' (you)' : ''}
              </Box>
              {!member.present ? (
                <Box inline color="bad" ml={1}>
                  not here
                </Box>
              ) : (
                planning &&
                !atPost && (
                  <Box inline color="average" ml={1}>
                    not at the post
                  </Box>
                )
              )}
            </Box>
          );
        })
      )}

      {/* Where the caravan actually leaves from. Without a post there is nowhere to muster at all. */}
      {!!planning && !!party.members.length && (
        <Box mt={1} color="label">
          {!party.has_hitching_post
            ? 'This colony has no hitching post to muster at.'
            : `${party.gathered_ids.length} of ${party.members.length} gathered at the hitching post (within ${party.gather_radius} paces).`}
        </Box>
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
                  party.route.length
                    ? undefined
                    : 'Choose a route to be ready for.'
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
              {/* Calling the whole muster off. Nothing has been spent yet, so this costs the colony nothing. */}
              <Button.Confirm
                icon="ban"
                color="bad"
                disabled={!planning}
                tooltip="Stand the whole expedition down. Everyone signed on is released."
                onClick={() => onAct('disband')}
              >
                Call it off
              </Button.Confirm>
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

      {party.state === 'at_site' && !!party.you_are_a_member && (
        <Box mt={1.5}>
          <Button
            fluid
            icon="house"
            color="good"
            onClick={() => onAct('head_home')}
          >
            Head home
          </Button>
        </Box>
      )}

      {/*
        Changing your mind on the road. Only between cells and only with no question outstanding - rerouting
        while halted would be answering the road by walking away from it, which the server refuses anyway.
      */}
      {(party.state === 'outbound' || party.state === 'returning') &&
        !party.pending_decision &&
        !!party.you_are_a_member && (
          <Box mt={1.5}>
            <Box color="label" mb={0.5}>
              The expedition can change its mind between cells. Rations are not
              refilled by doing so.
            </Box>
            <Button
              fluid
              icon="map-location-dot"
              disabled={!previewedSiteId}
              tooltip={
                previewedSiteId
                  ? undefined
                  : 'Choose somewhere on the map to head for instead.'
              }
              onClick={() => onAct('reroute')}
            >
              Head for the selected site instead
            </Button>
            <Button
              fluid
              mt={0.5}
              icon="house"
              onClick={() => onAct('turn_for_home')}
            >
              Turn back for the colony
            </Button>
          </Box>
        )}

      {!!planning && !!party.destination_site_id && (
        <Box mt={1.5}>
          {!!party.departure_problem && (
            <NoticeBox info mb={1}>
              {party.departure_problem}
            </NoticeBox>
          )}
          {/*
            The table plans; the post departs. There is no Set out button here because the whole party has to be
            standing at the post to leave, and somebody pressing this would have to not be standing there.
          */}
          <NoticeBox mb={1} success={!party.departure_problem}>
            {party.departure_problem
              ? 'Not ready to leave yet.'
              : 'Ready. Gather at the hitching post and give the word there.'}
          </NoticeBox>
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
