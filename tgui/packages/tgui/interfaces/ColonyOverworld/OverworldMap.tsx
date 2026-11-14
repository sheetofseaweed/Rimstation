import { storage } from 'common/storage';
import { useEffect, useState } from 'react';
import { Box, Button } from 'tgui-core/components';

import {
  GlobeMap,
  type GlobeQuality,
  isWebGLAvailable,
  type PlanetInfo,
  type SunInfo,
} from './GlobeMap';
import { RegionMap, type RegionMapProps } from './RegionMap';

/** How the map is drawn. Auto starts with the full globe and steps down when this machine is slow. */
export type MapQuality = 'auto' | 'full' | 'light' | 'flat';

const STORAGE_KEY = 'colony-overworld-map-quality';
const QUALITY_ORDER: MapQuality[] = ['auto', 'full', 'light', 'flat'];
const QUALITY_LABELS: Record<MapQuality, string> = {
  auto: 'Auto',
  full: 'Globe',
  light: 'Globe (light)',
  flat: 'Flat map',
};
/** Frame times, in milliseconds, above which Auto steps down from full to light and from light to flat. */
const FULL_LIMIT_MS = 16;
const LIGHT_LIMIT_MS = 28;

type Props = RegionMapProps & {
  planet?: PlanetInfo | null;
  sun?: SunInfo | null;
};

/**
 * The region map, drawn as a globe where the client can afford it and as the flat hex map where it cannot.
 *
 * The choice is the player's and is remembered on their client. Auto times the globe when it opens and
 * falls back a level at a time, so a weak machine ends on the flat map instead of a slow window.
 */
export function OverworldMap(props: Props) {
  const { planet, sun, ...mapProps } = props;
  const [quality, setQuality] = useState<MapQuality>('auto');
  const [autoLevel, setAutoLevel] = useState<GlobeQuality | 'flat'>('full');
  const [failed, setFailed] = useState(false);
  const [frameMs, setFrameMs] = useState<number | null>(null);

  useEffect(() => {
    storage.get(STORAGE_KEY).then((saved) => {
      if (QUALITY_ORDER.includes(saved)) {
        setQuality(saved);
      }
    });
  }, []);

  const canDrawGlobe = !failed && isWebGLAvailable();
  const level: GlobeQuality | 'flat' = !canDrawGlobe
    ? 'flat'
    : quality === 'auto'
      ? autoLevel
      : quality;

  const choose = (next: MapQuality) => {
    setQuality(next);
    setFrameMs(null);
    if (next === 'auto') {
      setAutoLevel('full');
    }
    storage.set(STORAGE_KEY, next);
  };

  const onFrameTime = (ms: number, measured: GlobeQuality) => {
    setFrameMs(ms);
    if (quality !== 'auto') {
      return;
    }
    if (measured === 'full' && ms > FULL_LIMIT_MS) {
      setAutoLevel('light');
    } else if (measured === 'light' && ms > LIGHT_LIMIT_MS) {
      setAutoLevel('flat');
    }
  };

  const next =
    QUALITY_ORDER[(QUALITY_ORDER.indexOf(quality) + 1) % QUALITY_ORDER.length];

  return (
    <Box style={{ position: 'relative', width: '100%', height: '100%' }}>
      {level === 'flat' ? (
        <RegionMap {...mapProps} />
      ) : (
        <GlobeMap
          {...mapProps}
          planet={planet}
          sun={sun}
          quality={level}
          onFrameTime={onFrameTime}
          onFailure={() => setFailed(true)}
        />
      )}
      <Box style={{ position: 'absolute', bottom: '2px', right: '2px' }}>
        {frameMs !== null && level !== 'flat' && (
          <Box inline color="label" mr={1}>
            {`${frameMs.toFixed(1)} ms`}
          </Box>
        )}
        <Button
          icon="globe"
          tooltip={
            canDrawGlobe
              ? `Map drawing: ${QUALITY_LABELS[quality]}. Click for ${QUALITY_LABELS[next]}. The number is the time this client takes to draw one frame.`
              : 'This client cannot draw the globe, so the flat map is shown.'
          }
          disabled={!canDrawGlobe}
          onClick={() => choose(next)}
        >
          {quality === 'auto' && canDrawGlobe
            ? `Auto: ${QUALITY_LABELS[level]}`
            : QUALITY_LABELS[canDrawGlobe ? quality : 'flat']}
        </Button>
      </Box>
    </Box>
  );
}
