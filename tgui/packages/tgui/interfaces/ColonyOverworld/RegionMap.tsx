import { useCallback, useEffect, useRef, useState } from 'react';
import { Box, Button } from 'tgui-core/components';

import {
  clampZoom,
  formatViewBox,
  hexPoints,
  MAX_ZOOM,
  MIN_ZOOM,
  panForZoomAt,
  parseCellId,
  regionBounds,
  routePolyline,
  zoomedViewBox,
} from './hexGeometry';

export const HEX_SIZE = 10;
/** How much one wheel notch changes the scale. */
const ZOOM_STEP = 1.2;
/** How far the pointer must travel before a press counts as a drag rather than a click on a hex. */
const DRAG_THRESHOLD_PIXELS = 4;

export type Cell = {
  id: string;
  q: number;
  r: number;
  distance: number;
};

export type KnownCell = {
  id: string;
  terrain: string;
  topology: string;
  danger: number;
  seconds: number;
};

export type KnownSite = {
  id: string;
  kind: string;
  cell: string;
  distance: number;
  yield: number;
};

/** Terrain fills. Paired with a pattern overlay so the map never depends on colour alone. */
export const TERRAIN_FILL: Record<string, string> = {
  frozen_steppe: '#b9c7cf',
  tundra: '#93a5a2',
  taiga: '#5c7d63',
  scrubland: '#9c9560',
  grassland: '#7f9e57',
  forest: '#3f6b41',
  desert: '#cbb279',
  savanna: '#b09a52',
  marsh: '#5d7160',
};

const UNKNOWN_FILL = '#14161a';

/** One to three marks for how hard a cell is to cross. */
const TOPOLOGY_MARKS: Record<string, string> = {
  easy: '',
  normal: '·',
  difficult: '··',
  impassable: '×',
};

type Props = {
  radius: number;
  cells: Cell[];
  knownCells: KnownCell[];
  knownSites: KnownSite[];
  selected: string | null;
  onSelect: (cellId: string) => void;
  /** Preview mode: nothing is hidden, because you are choosing a world rather than exploring one. */
  revealAll?: boolean;
  /** A planned walk, as cell ids. Drawn over the field so the route is read off the map, not off a list. */
  route?: string[];
};

/**
 * The region as a pan/zoomable SVG field.
 *
 * Shared between the expedition table and the campaign creation preview so that what somebody chooses at
 * creation is drawn by exactly the same code that will draw it for the rest of the campaign.
 */
export function RegionMap(props: Props) {
  const { radius, cells, knownCells, knownSites, selected, onSelect, revealAll, route } =
    props;

  const [zoom, setZoom] = useState(MIN_ZOOM);
  const [pan, setPan] = useState({ x: 0, y: 0 });

  const svgRef = useRef<SVGSVGElement>(null);
  const dragRef = useRef<{ x: number; y: number; panX: number; panY: number } | null>(null);
  const movedRef = useRef(false);

  const base = regionBounds(radius || 1, HEX_SIZE);

  const resetView = useCallback(() => {
    setZoom(MIN_ZOOM);
    setPan({ x: 0, y: 0 });
  }, []);

  /**
   * Wheel zoom, anchored on the cursor.
   *
   * Attached natively with `passive: false` because React registers wheel listeners as passive, where
   * preventDefault silently does nothing - and without it the whole window scrolls while you are zooming.
   */
  useEffect(() => {
    const element = svgRef.current;
    if (!element) {
      return;
    }

    const onWheel = (event: WheelEvent) => {
      event.preventDefault();
      const rect = element.getBoundingClientRect();
      if (!rect.width || !rect.height) {
        return;
      }
      const fractionX = (event.clientX - rect.left) / rect.width;
      const fractionY = (event.clientY - rect.top) / rect.height;

      setZoom((current) => {
        const next = clampZoom(event.deltaY < 0 ? current * ZOOM_STEP : current / ZOOM_STEP);
        if (next !== current) {
          setPan((currentPan) =>
            panForZoomAt(base, current, next, currentPan.x, currentPan.y, fractionX, fractionY),
          );
        }
        return next;
      });
    };

    element.addEventListener('wheel', onWheel, { passive: false });
    return () => element.removeEventListener('wheel', onWheel);
  }, [base]);

  const box = zoomedViewBox(base, zoom, pan.x, pan.y);

  const knownById: Record<string, KnownCell> = {};
  for (const cell of knownCells) {
    knownById[cell.id] = cell;
  }

  const siteByCell: Record<string, KnownSite> = {};
  for (const site of knownSites) {
    siteByCell[site.cell] = site;
  }

  const onPointerDown = (event: React.PointerEvent<SVGSVGElement>) => {
    // Stops the browser starting a native drag of the SVG itself, which is what was picking the whole tgui
    // window up and moving it instead of panning the map. Safe for selection: preventDefault on a pointer or
    // mouse down suppresses drag, focus and text selection, but the click still fires afterwards.
    event.preventDefault();

    // No setPointerCapture here. Capturing retargets later pointer events - and the click that follows them -
    // onto this SVG, which stops the hexes being clickable at all. Capture is taken on first real movement.
    dragRef.current = { x: event.clientX, y: event.clientY, panX: pan.x, panY: pan.y };
    movedRef.current = false;
  };

  const onPointerMove = (event: React.PointerEvent<SVGSVGElement>) => {
    const drag = dragRef.current;
    const element = svgRef.current;
    if (!drag || !element) {
      return;
    }

    // Measured in pixels so the threshold means the same thing at every zoom.
    const movedPixels = Math.hypot(event.clientX - drag.x, event.clientY - drag.y);
    if (!movedRef.current) {
      if (movedPixels < DRAG_THRESHOLD_PIXELS) {
        return;
      }
      movedRef.current = true;
      event.currentTarget.setPointerCapture(event.pointerId);
    }

    const rect = element.getBoundingClientRect();
    const dx = ((event.clientX - drag.x) / rect.width) * box.width;
    const dy = ((event.clientY - drag.y) / rect.height) * box.height;
    setPan({ x: drag.panX - dx, y: drag.panY - dy });
  };

  const endDrag = (event: React.PointerEvent<SVGSVGElement>) => {
    dragRef.current = null;
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
  };

  return (
    <Box style={{ position: 'relative', width: '100%', height: '100%' }}>
      <Box style={{ position: 'absolute', top: '2px', right: '2px', zIndex: 1 }}>
        <Box inline mr={1} color="label">
          {`${zoom.toFixed(1)}x`}
        </Box>
        <Button
          icon="magnifying-glass-minus"
          tooltip="Zoom out"
          disabled={zoom <= MIN_ZOOM}
          onClick={() => setZoom((current) => clampZoom(current / ZOOM_STEP))}
        />
        <Button
          icon="magnifying-glass-plus"
          tooltip="Zoom in"
          disabled={zoom >= MAX_ZOOM}
          onClick={() => setZoom((current) => clampZoom(current * ZOOM_STEP))}
        />
        <Button icon="expand" tooltip="Fit the whole region" onClick={resetView} />
      </Box>

      <svg
        ref={svgRef}
        viewBox={formatViewBox(box)}
        style={{
          width: '100%',
          height: '100%',
          cursor: 'grab',
          touchAction: 'none',
          // Belt and braces with the preventDefault above: an SVG is a draggable element by default, and a
          // half-started native drag is what reaches the window's own drag handling.
          userSelect: 'none',
          WebkitUserSelect: 'none',
        }}
        onDragStart={(event) => event.preventDefault()}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={endDrag}
        onPointerCancel={endDrag}
      >
        <defs>
          {/* Hatching for hard going, so difficulty is legible without relying on the colour behind it. */}
          <pattern id="rough-hatch" width="4" height="4" patternUnits="userSpaceOnUse">
            <path d="M0,4 l4,-4" stroke="#00000055" strokeWidth="1" />
          </pattern>
        </defs>

        {cells.map((cell) => {
          const known = knownById[cell.id];
          const site = siteByCell[cell.id];
          const isHome = cell.q === 0 && cell.r === 0;
          const isSelected = selected === cell.id;
          const visible = known || revealAll;

          return (
            <g
              key={cell.id}
              onClick={() => {
                // A drag that ended over a hex is a pan, not a selection.
                if (movedRef.current) {
                  return;
                }
                onSelect(cell.id);
              }}
            >
              <polygon
                points={hexPoints(cell, HEX_SIZE)}
                fill={
                  visible && known
                    ? (TERRAIN_FILL[known.terrain] ?? UNKNOWN_FILL)
                    : UNKNOWN_FILL
                }
                stroke={isSelected ? '#ffd24a' : '#000000'}
                strokeWidth={isSelected ? 1.4 : 0.4}
              />
              {!!known && (known.topology === 'difficult' || known.topology === 'impassable') && (
                <polygon
                  points={hexPoints(cell, HEX_SIZE)}
                  fill="url(#rough-hatch)"
                  style={{ pointerEvents: 'none' }}
                />
              )}
              {isHome && <HexLabel cell={cell} text="⌂" size={7} fill="#ffffff" />}
              {!isHome && !!site && (
                <HexLabel
                  cell={cell}
                  text={site.kind === 'resource' ? '◆' : '⌖'}
                  size={6}
                  fill="#ffe9a8"
                />
              )}
              {!isHome && !site && !!known && (
                <HexLabel
                  cell={cell}
                  text={TOPOLOGY_MARKS[known.topology] ?? ''}
                  size={6}
                  fill="#0d0d0d"
                />
              )}
              {!!known && known.danger > 0 && (
                <HexLabel
                  cell={cell}
                  text={'!'.repeat(known.danger)}
                  size={5}
                  fill="#ff6b6b"
                  dy={6}
                />
              )}
            </g>
          );
        })}

        {/*
          The planned walk, drawn last so it sits on top of the field rather than under it. Pointer events are
          off so the hexes underneath stay clickable - the route is something to read, not something to grab.
        */}
        {!!route?.length && (
          <polyline
            points={routePolyline(
              route
                .map((id) => parseCellId(id))
                .filter((axial): axial is { q: number; r: number } => !!axial),
              HEX_SIZE,
            )}
            fill="none"
            stroke="#ffd24a"
            strokeWidth={1.6}
            strokeLinejoin="round"
            strokeLinecap="round"
            strokeDasharray="3 2"
            style={{ pointerEvents: 'none' }}
          />
        )}
      </svg>
    </Box>
  );
}

/** A centred glyph on a hex. Split out because every marker needs the same centring maths. */
function HexLabel(props: {
  cell: { q: number; r: number };
  text: string;
  size: number;
  fill: string;
  dy?: number;
}) {
  const { cell, text, size, fill, dy = 0 } = props;
  if (!text) {
    return null;
  }
  const width = Math.sqrt(3) * HEX_SIZE;
  const height = 2 * HEX_SIZE;
  const x = width * (cell.q + cell.r / 2);
  const y = height * (3 / 4) * cell.r;

  return (
    <text
      x={x}
      y={y + dy}
      fontSize={size}
      fill={fill}
      textAnchor="middle"
      dominantBaseline="central"
      style={{ pointerEvents: 'none' }}
    >
      {text}
    </text>
  );
}

export { parseCellId };
